# server/app.py
import subprocess
import json
import os
import time
import threading
import requests
import markdown
from pathlib import Path
from flask import Flask, render_template, jsonify, send_file, abort, Response
from config import (
    ZABBIX_URL, ZABBIX_API_URL, ZABBIX_USER, ZABBIX_PASSWORD,
    IMAGES_BASE_DIR, IMAGES_OUTPUT_DIR, IMAGES_SCRIPTS_DIR,
    IMAGES_LOGS_DIR, BASE_IMAGE_PATH, PERSONALIZE_SCRIPT, DOCS_DIR,
    HEADSCALE_SERVER, HEADSCALE_USER, HEADSCALE_PASSWORD, IMAGE_EXPIRE_HOURS
)

app = Flask(__name__)

# === Глобальное состояние генерации образов ===
image_generation_lock = threading.Lock()
image_generation_status = {
    "busy": False,
    "started_at": None,
    "ready_file": None,
    "error": None
}

# === Создание директорий при старте ===
for d in [IMAGES_BASE_DIR, IMAGES_OUTPUT_DIR, IMAGES_LOGS_DIR, DOCS_DIR]:
    os.makedirs(d, exist_ok=True)


# === Фоновая очистка старых образов ===
def cleanup_old_images():
    """Удаляет образы старше IMAGE_EXPIRE_HOURS"""
    while True:
        time.sleep(600)  # Проверять каждые 10 минут
        try:
            now = time.time()
            expire_seconds = IMAGE_EXPIRE_HOURS * 3600
            for f in Path(IMAGES_OUTPUT_DIR).glob("*.img"):
                if now - f.stat().st_mtime > expire_seconds:
                    f.unlink()
                    print(f"[CLEANUP] Deleted expired image: {f.name}")
        except Exception as e:
            print(f"[CLEANUP] Error: {e}")

cleanup_thread = threading.Thread(target=cleanup_old_images, daemon=True)
cleanup_thread.start()


# === Zabbix API ===
class ZabbixAPI:
    def __init__(self):
        self.url = ZABBIX_API_URL
        self.auth_token = None
        self.token_time = 0

    def _call(self, method, params=None):
        """Вызов Zabbix API (совместимо с Zabbix 7.0)"""
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
            "id": 1
        }

        headers = {"Content-Type": "application/json-rpc"}

        # Zabbix 7.0: токен передаётся через Authorization header
        if self.auth_token and method != "user.login":
            headers["Authorization"] = f"Bearer {self.auth_token}"

        try:
            resp = requests.post(self.url, json=payload, headers=headers, timeout=10)
            data = resp.json()
            if "error" in data:
                raise Exception(data["error"].get("data", str(data["error"])))
            return data.get("result")
        except requests.RequestException as e:
            raise Exception(f"Connection error: {e}")

    def login(self):
        """Авторизация в Zabbix"""
        if not ZABBIX_USER or not ZABBIX_PASSWORD:
            raise Exception("Zabbix credentials not configured")

        # Кэшируем токен на 30 минут
        if self.auth_token and time.time() - self.token_time < 1800:
            return self.auth_token

        self.auth_token = self._call("user.login", {
            "username": ZABBIX_USER,
            "password": ZABBIX_PASSWORD
        })
        self.token_time = time.time()
        return self.auth_token

    def get_hosts(self):
        """Получить список хостов с их статусом"""
        self.login()
        hosts = self._call("host.get", {
            "output": ["hostid", "host", "name", "status"],
            "selectInterfaces": ["ip"],
            "filter": {"status": 0}
        })

        for host in hosts:
            host["available"] = self._get_host_availability(host["hostid"])
            host["ip"] = host.get("interfaces", [{}])[0].get("ip", "N/A")

        return hosts

    def _get_host_availability(self, hostid):
        """Проверка доступности хоста через agent ping"""
        try:
            items = self._call("item.get", {
                "hostids": hostid,
                "search": {"key_": "agent.ping"},
                "output": ["lastvalue", "lastclock"]
            })
            if items and items[0].get("lastvalue") == "1":
                return "available"
            return "unavailable"
        except:
            return "unknown"

    def get_host_items(self, hostid):
        """Получить items хоста для графиков"""
        self.login()
        return self._call("item.get", {
            "hostids": hostid,
            "output": ["itemid", "name", "key_", "lastvalue", "units", "value_type"],
            "filter": {"status": 0},
            "sortfield": "name"
        })

    def get_history(self, itemid, history_type=0, limit=120):
        """Получить историю значений для графика"""
        self.login()
        time_from = int(time.time()) - 7200  # Последние 2 часа
        return self._call("history.get", {
            "itemids": itemid,
            "history": history_type,
            "sortfield": "clock",
            "sortorder": "ASC",
            "time_from": time_from,
            "limit": limit
        })


zabbix_api = ZabbixAPI()


# === Tailscale ===
def parse_tailscale_status():
    """Возвращает два списка: хабы (tag:hub) и остальные устройства."""
    try:
        result = subprocess.check_output(["tailscale", "status", "--json"], universal_newlines=True)
        data = json.loads(result)
        
        hubs = []
        others = []
        
        peers = data.get("Peer", {})
        for peer_id, peer in peers.items():
            tags = peer.get("Tags", [])
            tailscale_ips = peer.get("TailscaleIPs", [])
            ip = tailscale_ips[0] if tailscale_ips else ""
            
            device = {
                "ip": ip,
                "hostname": peer.get("HostName", "unknown"),
                "os": peer.get("OS", "unknown"),
                "status": "active" if peer.get("Online", False) else "offline"
            }
            
            if "tag:hub" in tags:
                hubs.append(device)
            else:
                others.append(device)
        
        return hubs, others
    except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError):
        return [], []


# === Основные страницы ===
@app.route("/")
def index():
    hubs, others = parse_tailscale_status()
    return render_template("index.html", hubs=hubs, others=others, zabbix_url=ZABBIX_URL)


@app.route("/data")
def data():
    hubs, others = parse_tailscale_status()
    result_hubs = []

    for hub in hubs:
        ip = hub["ip"]
        hostname = hub["hostname"]
        try:
            response = requests.get(f"http://{ip}:5000/devices", timeout=3)
            response.raise_for_status()
            level3 = response.json()
        except Exception:
            level3 = []

        result_hubs.append({
            "hostname": hostname,
            "ip": ip,
            "os": hub["os"],
            "status": hub["status"],
            "level3": level3,
            "is_hub": True
        })

    result_others = [{**dev, "is_hub": False, "level3": []} for dev in others]
    return jsonify({"hubs": result_hubs, "others": result_others})




@app.route("/ui/<ip>")
def ui(ip):
    return render_template("iframe.html", title="Web UI", url=f"http://{ip}:5000")


@app.route("/terminal/<ip>")
def terminal(ip):
    return render_template("iframe.html", title="Терминал", url=f"http://{ip}:7681")




@app.route("/images")
def images():
    # Проверяем наличие базового образа
    base_exists = os.path.isfile(BASE_IMAGE_PATH)
    return render_template("images.html", zabbix_url=ZABBIX_URL, base_exists=base_exists)


# === Генерация образов ===
@app.route("/images/status")
def images_status():
    """Возвращает статус генерации образа"""
    with image_generation_lock:
        status = image_generation_status.copy()
    
    # Проверяем есть ли готовые образы для скачивания
    ready_files = list(Path(IMAGES_OUTPUT_DIR).glob("*.img")) + list(Path(IMAGES_OUTPUT_DIR).glob("*.img.gz"))
    
    return jsonify({
        "busy": status["busy"],
        "ready_file": status["ready_file"],
        "error": status["error"],
        "available_images": [f.name for f in ready_files]
    })


@app.route("/images/generate", methods=["POST"])
def images_generate():
    """Запускает генерацию персонализированного образа"""
    global image_generation_status
    
    # Проверяем credentials
    if not all([HEADSCALE_SERVER, HEADSCALE_USER, HEADSCALE_PASSWORD]):
        return jsonify({
            "success": False,
            "error": "Headscale credentials not configured"
        }), 500
    
    # Проверяем базовый образ
    if not os.path.isfile(BASE_IMAGE_PATH):
        return jsonify({
            "success": False,
            "error": f"Base image not found: {BASE_IMAGE_PATH}"
        }), 500
    
    # Проверяем скрипт
    if not os.path.isfile(PERSONALIZE_SCRIPT):
        return jsonify({
            "success": False,
            "error": f"Personalize script not found: {PERSONALIZE_SCRIPT}"
        }), 500
    
    # Пробуем захватить lock
    acquired = image_generation_lock.acquire(blocking=False)
    if not acquired:
        return jsonify({
            "success": False,
            "error": "Образ уже генерируется для другого пользователя. Попробуйте через несколько минут."
        }), 429
    
    try:
        if image_generation_status["busy"]:
            image_generation_lock.release()
            return jsonify({
                "success": False,
                "error": "Образ уже генерируется. Попробуйте позже."
            }), 429
        
        # Устанавливаем статус
        image_generation_status = {
            "busy": True,
            "started_at": time.time(),
            "ready_file": None,
            "error": None
        }
    finally:
        image_generation_lock.release()
    
    # Запускаем генерацию в фоне
    def run_generation():
        global image_generation_status
        try:
            env = os.environ.copy()
            env["HEADSCALE_SERVER"] = HEADSCALE_SERVER
            env["HEADSCALE_USER"] = HEADSCALE_USER
            env["HEADSCALE_PASSWORD"] = HEADSCALE_PASSWORD
            
            result = subprocess.run(
                ["bash", PERSONALIZE_SCRIPT, BASE_IMAGE_PATH, IMAGES_OUTPUT_DIR],
                env=env,
                capture_output=True,
                text=True,
                timeout=600  # 10 минут максимум
            )
            
            if result.returncode == 0:
                # Последняя строка stdout — имя файла
                filename = result.stdout.strip().split('\n')[-1]
                with image_generation_lock:
                    image_generation_status["ready_file"] = filename
                    image_generation_status["busy"] = False
            else:
                with image_generation_lock:
                    image_generation_status["error"] = result.stderr or "Unknown error"
                    image_generation_status["busy"] = False
                    
        except subprocess.TimeoutExpired:
            with image_generation_lock:
                image_generation_status["error"] = "Timeout: generation took too long"
                image_generation_status["busy"] = False
        except Exception as e:
            with image_generation_lock:
                image_generation_status["error"] = str(e)
                image_generation_status["busy"] = False
    
    thread = threading.Thread(target=run_generation, daemon=True)
    thread.start()
    
    return jsonify({"success": True, "message": "Генерация запущена"})


@app.route("/images/download/<filename>")
def images_download(filename):
    """Скачивание образа с последующим удалением"""
    # Безопасность: только .img или .img.gz файлы из output директории
    if not (filename.endswith(".img") or filename.endswith(".img.gz")) or "/" in filename or "\\" in filename:
        abort(400)
    
    filepath = os.path.join(IMAGES_OUTPUT_DIR, filename)
    if not os.path.isfile(filepath):
        abort(404)
    
    def generate_and_delete():
        """Генератор для стриминга файла с удалением после"""
        try:
            with open(filepath, 'rb') as f:
                while chunk := f.read(8192 * 1024):  # 8MB chunks
                    yield chunk
        finally:
            # Удаляем файл после скачивания
            try:
                os.unlink(filepath)
                print(f"[DOWNLOAD] Deleted after download: {filename}")
                # Сбрасываем статус если это был текущий файл
                with image_generation_lock:
                    if image_generation_status.get("ready_file") == filename:
                        image_generation_status["ready_file"] = None
            except Exception as e:
                print(f"[DOWNLOAD] Error deleting {filename}: {e}")
    
    return Response(
        generate_and_delete(),
        mimetype='application/octet-stream',
        headers={
            'Content-Disposition': f'attachment; filename={filename}',
            'Content-Length': os.path.getsize(filepath)
        }
    )


# === Документация ===
@app.route("/docs")
def docs_list():
    """Список всех документов"""
    docs = []
    if os.path.isdir(DOCS_DIR):
        for f in sorted(Path(DOCS_DIR).glob("*.md")):
            docs.append({
                "name": f.stem,
                "filename": f.name
            })
    return render_template("docs.html", docs=docs, zabbix_url=ZABBIX_URL)


@app.route("/docs/<name>")
def docs_view(name):
    """Просмотр конкретного документа"""
    # Безопасность
    if "/" in name or "\\" in name or ".." in name:
        abort(400)
    
    filepath = os.path.join(DOCS_DIR, f"{name}.md")
    if not os.path.isfile(filepath):
        # Попробуем с расширением
        filepath = os.path.join(DOCS_DIR, name)
        if not os.path.isfile(filepath):
            abort(404)
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Конвертируем markdown в HTML
    html_content = markdown.markdown(
        content,
        extensions=['fenced_code', 'tables', 'toc']
    )
    
    return render_template("doc_view.html", 
                          title=name, 
                          content=html_content, 
                          zabbix_url=ZABBIX_URL)


# === Dashboard ===
@app.route("/dashboard")
def dashboard():
    """Страница дашборда с мониторингом устройств"""
    return render_template("dashboard.html", zabbix_url=ZABBIX_URL)


@app.route("/api/zabbix/hosts")
def api_zabbix_hosts():
    """API: список хостов из Zabbix"""
    try:
        hosts = zabbix_api.get_hosts()
        return jsonify({"success": True, "hosts": hosts})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/zabbix/host/<hostid>/items")
def api_zabbix_host_items(hostid):
    """API: items конкретного хоста"""
    try:
        items = zabbix_api.get_host_items(hostid)
        filtered = []
        interesting_keys = [
            "system.cpu", "vm.memory", "net.if", "system.uptime",
            "agent.ping", "system.load", "vfs.fs", "vfs.dev"
        ]
        for item in items:
            if any(k in item.get("key_", "") for k in interesting_keys):
                filtered.append(item)
        return jsonify({"success": True, "items": filtered})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@app.route("/api/zabbix/history/<itemid>")
def api_zabbix_history(itemid):
    """API: история значений для графика"""
    try:
        # Определяем тип истории (0=float, 3=unsigned)
        items = zabbix_api._call("item.get", {
            "itemids": itemid,
            "output": ["value_type"]
        })
        if not items:
            return jsonify({"success": False, "error": "Item not found"}), 404
        
        value_type = int(items[0].get("value_type", 0))
        history = zabbix_api.get_history(itemid, history_type=value_type)
        
        # Форматируем для Chart.js
        data = []
        for point in history:
            data.append({
                "x": int(point["clock"]) * 1000,  # JS timestamp
                "y": float(point["value"]) if value_type in [0, 3] else point["value"]
            })
        
        return jsonify({"success": True, "data": data})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


if __name__ == "__main__":
    from config import BIND_IP, BIND_PORT
    app.run(host=BIND_IP, port=BIND_PORT, debug=False, threaded=True)
