# Развёртывание RedTeam Server

## Требования

- Linux (Debian/Ubuntu)
- Python 3.10+
- ~20-30 GB свободного места (для базового образа)
- Tailscale подключён к сети
- Доступ к Headscale серверу по SSH

## Установка

### 1. Клонирование и настройка

```bash
# Клонировать репозиторий
git clone <repo> /opt/redteam
cd /opt/redteam/server

# Создать venv и установить зависимости
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

# Проверить что все модули установлены (flask, requests, markdown)
./venv/bin/pip list
```

### 2. Environment переменные

Создать файл `/opt/redteam/server/.env` или экспортировать:

```bash
export BIND_IP="0.0.0.0"
export BIND_PORT="5100"
export ZABBIX_URL="http://YOUR_TAILSCALE_IP:8081"
export ZABBIX_API_URL="http://YOUR_TAILSCALE_IP:8081/api_jsonrpc.php"

# Headscale credentials (для генерации образов)
export HEADSCALE_SERVER="headscale.example.com"
export HEADSCALE_USER="root"
export HEADSCALE_PASSWORD="your-password"
```

### 3. Базовый образ

Для генерации образов через веб-интерфейс нужен базовый образ:

```bash
# Собрать на машине для сборки
cd /path/to/image-scripts/
bash 00-build-arm64-artifacts-trixie.sh
sudo ARTIFACTS_DIR=./artifacts-arm64 bash 01-build-base-pi-image-trixie.sh

# Скопировать на сервер
scp rpi-base-*.img user@server:/opt/redteam/server/images/base/base-trixie.img
```

### 4. Зависимости для генерации образов

На сервере должны быть установлены:

```bash
sudo apt-get install -y \
  qemu-user-static \
  jq \
  openssl \
  sshpass \
  util-linux \
  coreutils
```

### 5. Запуск

```bash
cd /opt/redteam/server
sudo ./venv/bin/python app.py
```

Генерация образов требует root (losetup, mount, chroot), поэтому запуск от root.

## Разделы веб-интерфейса

| Раздел | URL | Описание |
|--------|-----|----------|
| Устройства | `/` | Список хабов в Tailscale-сети, статус, ссылки на Hub UI и терминал |
| Образы | `/images` | Генерация персонализированных образов, скачивание, статус |
| Dashboard | `/dashboard` | Графики метрик с Zabbix: CPU, Memory, Disk, Network, Load Average |
| Документация | `/docs` | Встроенная документация (рендер markdown-файлов из `docs/`) |

### Dashboard

Dashboard отображает метрики хабов из Zabbix в реальном времени (обновление каждые 30 сек):

- Карточки: CPU %, Memory %, Disk %, Uptime
- Графики: CPU Utilization, Memory Utilization, Disk Space, Disk I/O (mmcblk0), Load Average
- Сетевые интерфейсы: автоматически обнаруживаются все интерфейсы хоста (tailscale0, wlan0, eth0 и др.), для каждого строится график In/Out

Для работы Dashboard необходим настроенный Zabbix с агентами на хабах (см. `ZABBIX-MONITORING.md`).

## Структура

```
/opt/redteam/server/
├── app.py              # Flask приложение
├── config.py           # Конфигурация
├── .env                # Переменные окружения (создать из .env.example)
├── requirements.txt
├── static/             # CSS, JS
├── templates/          # HTML шаблоны
├── docs/               # Документация (markdown, доступна через /docs)
├── images/
│   ├── base/           # Базовый образ (base-trixie.img)
│   ├── output/         # Готовые образы (временные, автоочистка)
│   ├── scripts/        # Скрипт персонализации
│   └── logs/           # Логи генерации
└── venv/               # Python virtual environment
```

## Проверка

```bash
curl http://localhost:5100/
```

## Доступ

- Главная: `http://<server-ip>:5100/`
- Образы: `http://<server-ip>:5100/images`
- Dashboard: `http://<server-ip>:5100/dashboard`
- Документация: `http://<server-ip>:5100/docs`
