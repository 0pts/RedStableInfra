#!/usr/bin/env python3
"""
Hub — веб-приложение для управления периферийными устройствами (ESP32 и др.)
Запускается на каждом хабе (Raspberry Pi).

Функции:
- Сканирование Wi-Fi для обнаружения устройств
- Подключение/отключение к устройствам через nmcli
- Скачивание логов с устройств (keylogger и др.)
- API для серверного приложения (/devices)
"""
import datetime
import os
import re
import sqlite3
import subprocess
import threading
import time
from pathlib import Path

import requests
from flask import (Flask, jsonify, render_template, send_from_directory)


# --------------------------------------------------------------------------- #
#  TAILSCALE IP DETECTION
# --------------------------------------------------------------------------- #
def get_tailscale_ip() -> str | None:
    """Получает Tailscale IP этого устройства."""
    try:
        result = subprocess.check_output(
            ["tailscale", "ip", "-4"],
            universal_newlines=True,
            timeout=5
        ).strip()
        return result.split('\n')[0] if result else None
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        pass

    try:
        import json
        result = subprocess.check_output(
            ["tailscale", "status", "--json"],
            universal_newlines=True,
            timeout=5
        )
        data = json.loads(result)
        ips = data.get("Self", {}).get("TailscaleIPs", [])
        for ip in ips:
            if "." in ip:
                return ip
    except Exception:
        pass

    return None

# --------------------------------------------------------------------------- #
#  ПАРАМЕТРЫ КОНФИГУРАЦИИ
# --------------------------------------------------------------------------- #
SCAN_INTERVAL   = 10            # секунд между вызовами iwlist
ACTIVE_WINDOW   = 30            # секунд, сколько устройство считается активным
DOWNLOAD_TTL    = 7 * 24 * 3600 # секунд — срок хранения лог-файлов

# --------------------------------------------------------------------------- #
#  ИНИЦИАЛИЗАЦИЯ ПРИЛОЖЕНИЯ
# --------------------------------------------------------------------------- #
app = Flask(__name__)

app.config['DOWNLOAD_FOLDER'] = Path(os.getcwd()) / "download_logs"
app.config['DOWNLOAD_FOLDER'].mkdir(exist_ok=True)

# --------------------------------------------------------------------------- #
#  ГЛОБАЛЬНОЕ СОСТОЯНИЕ
# --------------------------------------------------------------------------- #
wifi_scan_lock = threading.Lock()
last_seen: dict[str, float] = {}
scan_ts: int = 0
latest_wifi_scan: str = ""

MAC_RE = re.compile(r"Address:\s*([0-9A-F:]{17})", re.I)

# --------------------------------------------------------------------------- #
#  DB УТИЛИТЫ
# --------------------------------------------------------------------------- #
def db_connect():
    conn = sqlite3.connect("Devices.db", timeout=10, check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def get_devices_from_db() -> list[dict]:
    with db_connect() as conn:
        rows = conn.execute("SELECT Name, Type, MAC FROM Devices").fetchall()
    return [{"name": n, "type": t, "MAC": m.lower()} for n, t, m in rows]


def get_wifi_password_by_type(type_name: str) -> str | None:
    with db_connect() as conn:
        row = conn.execute("SELECT Pass FROM pass WHERE Type=? LIMIT 1",
                           (type_name,)).fetchone()
    return row[0] if row else None


# --------------------------------------------------------------------------- #
#  СЕТЕВОЕ СКАНИРОВАНИЕ
# --------------------------------------------------------------------------- #
def parse_scan(raw: str) -> set[str]:
    return {m.group(1).lower() for m in MAC_RE.finditer(raw)}


def scan_wifi() -> str:
    try:
        return subprocess.check_output(
            ["sudo", "iwlist", "wlan0", "scan"],
            stderr=subprocess.STDOUT,
            universal_newlines=True)
    except subprocess.CalledProcessError as e:
        return e.output or ""


def update_scan() -> None:
    global scan_ts, latest_wifi_scan
    while True:
        raw = scan_wifi()
        macs = parse_scan(raw)
        now  = time.time()

        with wifi_scan_lock:
            for mac in macs:
                last_seen[mac] = now
            latest_wifi_scan = raw.lower()
            scan_ts = int(now)

        time.sleep(SCAN_INTERVAL)


def get_device_status(mac: str) -> str:
    with wifi_scan_lock:
        ts = last_seen.get(mac.lower())
    return "Active" if ts and (time.time() - ts) <= ACTIVE_WINDOW else "Inactive"


# --------------------------------------------------------------------------- #
#  NMCLI
# --------------------------------------------------------------------------- #
def get_current_connection() -> str | None:
    try:
        out = subprocess.check_output(
            ["nmcli", "-t", "-f", "NAME,DEVICE",
             "connection", "show", "--active"],
            universal_newlines=True).strip()
    except subprocess.CalledProcessError:
        return None

    for line in out.splitlines():
        if line.endswith(":wlan0"):
            return line.split(":")[0]
    return None


# --------------------------------------------------------------------------- #
#  АВТО-ОЧИСТКА ЛОГ-ФАЙЛОВ
# --------------------------------------------------------------------------- #
def cleanup_downloads() -> None:
    while True:
        now = time.time()
        for p in app.config['DOWNLOAD_FOLDER'].iterdir():
            if p.is_file() and now - p.stat().st_mtime > DOWNLOAD_TTL:
                p.unlink(missing_ok=True)
        time.sleep(3600)


# --------------------------------------------------------------------------- #
#  ROUTES
# --------------------------------------------------------------------------- #
@app.route("/")
def index():
    active, inactive = [], []
    for dev in get_devices_from_db():
        dev["status"] = get_device_status(dev["MAC"])
        (active if dev["status"] == "Active" else inactive).append(dev)

    return render_template("index.html",
                           active_devices=active,
                           inactive_devices=inactive)


@app.route("/data")
def data():
    payload = []
    for d in get_devices_from_db():
        status = get_device_status(d["MAC"])
        age = (int(time.time() - last_seen[d["MAC"]])
               if status == "Active" else None)
        payload.append({**d, "status": status, "age": age})

    return jsonify(scan_success=True,
                   scan_timestamp=scan_ts,
                   devices=payload)


@app.route("/devices")
def devices_api():
    """API endpoint — используется серверным приложением."""
    return jsonify([{
        **d,
        "status": get_device_status(d["MAC"])
    } for d in get_devices_from_db()])


@app.route("/connection_status")
def connection_status():
    conn_name = get_current_connection()
    if not conn_name:
        return jsonify(connected=False,
                       connection="Нет активного подключения",
                       type=None)

    device_type = None
    for dev in get_devices_from_db():
        if dev["name"].lower() == conn_name.lower():
            device_type = dev["type"]
            break

    return jsonify(connected=True,
                   connection=conn_name,
                   type=device_type)


@app.route("/connect/<mac>", methods=["POST"])
def connect_device(mac: str):
    target = next((d for d in get_devices_from_db()
                   if d["MAC"] == mac.lower()), None)
    if not target:
        return jsonify(message=f"Устройство {mac} не найдено", device_type=None), 404

    pwd = get_wifi_password_by_type(target["type"])
    if not pwd:
        return jsonify(message="Пароль для типа не найден", device_type=None), 500

    try:
        subprocess.run(
            ["nmcli", "device", "wifi", "connect", target["name"],
             "password", pwd],
            check=True)
        return jsonify(message=f"Подключено к {target['name']}",
                       device_type=target["type"]), 200
    except subprocess.CalledProcessError as e:
        return jsonify(message=f"Ошибка nmcli: {e}", device_type=None), 500


@app.route("/disconnect/<mac>", methods=["POST"])
def disconnect_device(mac: str):
    target = next((d for d in get_devices_from_db()
                   if d["MAC"] == mac.lower()), None)
    if not target:
        return jsonify(message=f"Устройство {mac} не найдено", device_type=None), 404
    try:
        subprocess.run(
            ["nmcli", "connection", "down", target["name"]],
            check=True)
        return jsonify(message=f"Отключено от {target['name']}",
                       device_type=None), 200
    except subprocess.CalledProcessError as e:
        return jsonify(message=f"Ошибка nmcli: {e}", device_type=None), 500


@app.route("/download_log", methods=["GET", "POST"])
def download_log():
    """Скачивает лог с подключённого устройства (ESP32 AP: 192.168.4.1)."""
    try:
        resp = requests.get("http://192.168.4.1/", timeout=5)
        resp.raise_for_status()
    except requests.RequestException as e:
        return f"Ошибка при скачивании лога: {e}", 500

    device_name = (get_current_connection() or "unknown_device").replace(" ", "_")
    timestamp   = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    filename    = f"{device_name}_{timestamp}.txt"
    filepath    = app.config['DOWNLOAD_FOLDER'] / filename
    filepath.write_bytes(resp.content)

    return send_from_directory(directory=app.config['DOWNLOAD_FOLDER'],
                               path=filename,
                               as_attachment=True,
                               download_name=filename)


@app.route("/clear_log", methods=["POST"])
def clear_log():
    try:
        resp = requests.get("http://192.168.4.1/clear", timeout=5)
        resp.raise_for_status()
        return "Лог успешно очищен", 200
    except requests.RequestException as e:
        return f"Ошибка при очистке лога: {e}", 500


# --------------------------------------------------------------------------- #
#  ЗАПУСК
# --------------------------------------------------------------------------- #
if __name__ == "__main__":
    threading.Thread(target=update_scan,    daemon=True).start()
    threading.Thread(target=cleanup_downloads, daemon=True).start()

    tailscale_ip = get_tailscale_ip()
    if tailscale_ip:
        print(f"[INFO] Binding to Tailscale IP: {tailscale_ip}:5000")
        app.run(host=tailscale_ip, port=5000)
    else:
        print("[WARNING] Tailscale IP not found, binding to 127.0.0.1")
        app.run(host="127.0.0.1", port=5000)
