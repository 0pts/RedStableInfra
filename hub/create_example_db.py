#!/usr/bin/env python3
"""
Создаёт примерную базу данных Devices.db с тестовыми данными.
Запустить один раз перед первым запуском Hub.

Usage:
    python3 create_example_db.py
"""
import sqlite3
import os

DB_NAME = "Devices.db"

if os.path.exists(DB_NAME):
    print(f"[!] {DB_NAME} уже существует. Удалите вручную если хотите пересоздать.")
    exit(1)

conn = sqlite3.connect(DB_NAME)
conn.execute("PRAGMA journal_mode=WAL")

# Таблица устройств: Name = имя Wi-Fi AP, Type = тип, MAC = MAC-адрес
conn.execute("""
CREATE TABLE Devices (
    Name TEXT NOT NULL,
    Type TEXT NOT NULL,
    MAC  TEXT NOT NULL
)
""")

# Таблица паролей Wi-Fi по типу устройства
conn.execute("""
CREATE TABLE pass (
    Type TEXT NOT NULL,
    Pass TEXT NOT NULL
)
""")

# --- Тестовые данные ---

devices = [
    ("KeyLog-01",   "keylogger", "aa:bb:cc:dd:ee:01"),
    ("KeyLog-02",   "keylogger", "aa:bb:cc:dd:ee:02"),
    ("BadUSB-01",   "badusb",    "aa:bb:cc:dd:ee:03"),
    ("WiFi-Deauth", "deauth",    "aa:bb:cc:dd:ee:04"),
    ("BLE-Scan-01", "ble",       "aa:bb:cc:dd:ee:05"),
]

passwords = [
    ("keylogger", "keylogger_wifi_pass"),
    ("badusb",    "badusb_wifi_pass"),
    ("deauth",    "deauth_wifi_pass"),
    ("ble",       "ble_wifi_pass"),
]

conn.executemany("INSERT INTO Devices VALUES (?, ?, ?)", devices)
conn.executemany("INSERT INTO pass VALUES (?, ?)", passwords)
conn.commit()
conn.close()

print(f"[+] {DB_NAME} создана с {len(devices)} устройствами и {len(passwords)} паролями.")
print()
print("Устройства:")
for name, typ, mac in devices:
    print(f"  {name:15s}  type={typ:10s}  MAC={mac}")
print()
print("Пароли Wi-Fi:")
for typ, pwd in passwords:
    print(f"  {typ:10s} → {pwd}")
