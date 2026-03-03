# Infra Server

Flask-приложение для управления инфраструктурой. Работает внутри Tailscale-сети.

## Функции

- Отображение статуса хабов в Tailscale-сети (online/offline, периферия)
- Генерация персонализированных образов Raspberry Pi (hostname + Tailscale authkey)
- Dashboard с метриками из Zabbix (CPU, RAM, Disk, Network)
- Встроенная документация (рендер markdown из `docs/`)

## Веб-интерфейс

| Раздел | URL | Описание |
|--------|-----|----------|
| Устройства | `/` | Список хабов, статус, ссылки на Hub UI и терминал |
| Образы | `/images` | Генерация и скачивание образов |
| Dashboard | `/dashboard` | Графики Zabbix (CPU, Memory, Disk, Network, Load) |
| Документация | `/docs` | Markdown-документация |

## Быстрый старт

```bash
cp .env.example .env
nano .env                          # заполнить значения

python3 -m venv venv
./venv/bin/pip install -r requirements.txt

sudo ./venv/bin/python app.py      # sudo нужен для генерации образов
```

Порт по умолчанию: `5100`

## Переменные окружения

См. `.env.example`. Основные:

| Переменная | Описание |
|------------|----------|
| `BIND_IP` | IP для bind (Tailscale IP или 0.0.0.0) |
| `BIND_PORT` | Порт (по умолчанию 5100) |
| `ZABBIX_URL` | URL Zabbix web UI |
| `ZABBIX_API_URL` | URL Zabbix JSON-RPC API |
| `HEADSCALE_SERVER` | Адрес Headscale сервера |
| `HEADSCALE_USER` | SSH пользователь Headscale |
| `HEADSCALE_PASSWORD` | SSH пароль Headscale |

## Генерация образов

Требуется базовый образ в `images/base/base-trixie.img` и установленные пакеты:

```bash
sudo apt-get install -y qemu-user-static jq openssl sshpass util-linux
```

Процесс: копирование базового образа → mount → chroot → установка hostname + Tailscale authkey → umount → отдача .img.

Образы автоматически удаляются через 5 часов.

## Зависимости

- Python 3.10+
- Flask, requests, markdown
- Tailscale (для `tailscale status`)
- Zabbix Server (для Dashboard)

## Структура

```
server/
├── app.py              # Flask-приложение
├── config.py           # Конфигурация
├── .env.example        # Шаблон переменных
├── requirements.txt
├── static/             # CSS, JS
├── templates/          # HTML-шаблоны
├── docs/               # Документация (markdown)
├── images/
│   ├── base/           # Базовый образ (base-trixie.img)
│   ├── output/         # Готовые образы (временные)
│   ├── scripts/        # personalize.sh
│   └── logs/           # Логи генерации
└── INSTALL.md          # Инструкция установки
```
