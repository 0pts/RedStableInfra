# RedStableInfra

Централизованное управление распределённой атакующей инфраструктурой на базе Raspberry Pi, Tailscale и ESP8266/ESP32.

## Возможности

- Веб-интерфейс мониторинга всех устройств в сети
- Генерация персонализированных образов для хабов (~2-3 мин)
- Mesh VPN: Tailscale + self-hosted Headscale (NAT traversal, без проброса портов)
- Мониторинг и алерты: Zabbix + Telegram
- Сбор данных с периферии (ESP8266/ESP32) через Wi-Fi

## Архитектура

```
Уровень 1: Серверы
├── Headscale (VPN координатор, публичный VPS)
└── Infra Server (Flask, Zabbix, генерация образов)

Уровень 2: Хабы
└── Raspberry Pi 5 (Debian 13 Trixie, offensive-инструменты, Hub UI, ttyd)

Уровень 3: Периферия
└── ESP8266/ESP32 (кейлоггеры, BadUSB, импланты — связь через Wi-Fi)
```

## Структура репозитория

```
├── server/                  # Infra Server (Flask)
│   ├── app.py              # Основное приложение
│   ├── config.py           # Конфигурация (плейсхолдеры)
│   ├── .env.example        # Шаблон переменных окружения
│   ├── images/scripts/     # Скрипт персонализации образов
│   ├── templates/          # HTML-шаблоны
│   ├── static/             # CSS, JS
│   └── docs/               # Документация (доступна через веб-интерфейс)
│
├── hub/                     # Hub-приложение (Flask, работает на каждом хабе)
│   ├── app.py              # Управление периферией
│   ├── create_example_db.py # Создание тестовой БД
│   ├── templates/
│   └── static/
│
├── image-scripts/           # Скрипты сборки образов
│   ├── 00-build-arm64-artifacts-trixie.sh  # Сборка артефактов
│   ├── 01-build-base-pi-image-trixie.sh    # Базовый образ
│   ├── 02-personalize-pi-image-trixie.sh   # Персонализация
│   └── verify-tools.sh                     # Проверка установки
│
├── docs/                    # Документация
│   ├── ARCHITECTURE.md     # Архитектура системы
│   ├── BUILD-GUIDE.md      # Инструкция по сборке образов
│   ├── HEADSCALE-GUIDE.md  # Настройка Headscale/Tailscale
│   ├── IMAGE-CONTENTS.md   # Содержимое образа
│   └── ZABBIX-MONITORING.md # Метрики мониторинга
│
├── install_go_tailscale.sh  # Установка Go + сборка Tailscale из исходников
├── CONFIGURATION.md         # Гайд по замене плейсхолдеров
└── README.md
```

## Документация

### С чего начать

1. [CONFIGURATION.md](CONFIGURATION.md) — замена плейсхолдеров на свои значения
2. [server/INSTALL.md](server/INSTALL.md) — запуск серверного приложения
3. [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md) — сборка образа Raspberry Pi

### Справочники

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — архитектура системы (схема, уровни)
- [docs/IMAGE-CONTENTS.md](docs/IMAGE-CONTENTS.md) — что внутри образа (инструменты, сервисы)
- [docs/HEADSCALE-GUIDE.md](docs/HEADSCALE-GUIDE.md) — команды Headscale/Tailscale
- [docs/ZABBIX-MONITORING.md](docs/ZABBIX-MONITORING.md) — метрики мониторинга
- [server/docs/SERVER-SETUP.md](server/docs/SERVER-SETUP.md) — развёртывание сервера (подробно)

### Компоненты

- [server/README.md](server/README.md) — Infra Server
- [hub/README.md](hub/README.md) — Hub (управление периферией)
