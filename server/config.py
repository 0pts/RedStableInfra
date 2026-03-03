# server/config.py
# Настройки серверного приложения
import os

# IP для bind (Tailscale интерфейс — доступ только из VPN)
BIND_IP = os.environ.get("BIND_IP", "YOUR_TAILSCALE_IP")
BIND_PORT = int(os.environ.get("BIND_PORT", "5100"))

# Zabbix
ZABBIX_URL = os.environ.get("ZABBIX_URL", "http://YOUR_TAILSCALE_IP:8081")
ZABBIX_API_URL = os.environ.get("ZABBIX_API_URL", "http://YOUR_TAILSCALE_IP:8081/api_jsonrpc.php")
ZABBIX_USER = os.environ.get("ZABBIX_USER", "Admin")
ZABBIX_PASSWORD = os.environ.get("ZABBIX_PASSWORD", "")

# Пути для образов
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
IMAGES_DIR = os.path.join(BASE_DIR, "images")
IMAGES_BASE_DIR = os.path.join(IMAGES_DIR, "base")
IMAGES_OUTPUT_DIR = os.path.join(IMAGES_DIR, "output")
IMAGES_SCRIPTS_DIR = os.path.join(IMAGES_DIR, "scripts")
IMAGES_LOGS_DIR = os.path.join(IMAGES_DIR, "logs")

# Базовый образ
BASE_IMAGE_NAME = "base-trixie.img"
BASE_IMAGE_PATH = os.path.join(IMAGES_BASE_DIR, BASE_IMAGE_NAME)

# Скрипт персонализации
PERSONALIZE_SCRIPT = os.path.join(IMAGES_SCRIPTS_DIR, "personalize.sh")

# Headscale credentials (из environment)
HEADSCALE_SERVER = os.environ.get("HEADSCALE_SERVER", "")
HEADSCALE_USER = os.environ.get("HEADSCALE_USER", "")
HEADSCALE_PASSWORD = os.environ.get("HEADSCALE_PASSWORD", "")

# Документация
DOCS_DIR = os.path.join(BASE_DIR, "docs")

# Таймауты
IMAGE_EXPIRE_HOURS = 5  # Удалить образ если не скачали за N часов
