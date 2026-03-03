# Инструкция по сборке образа Raspberry Pi (Trixie)

Пошаговое руководство по сборке кастомного образа для Raspberry Pi 5 на базе Debian 13 (trixie).

## Требования

### Хост-система

- Linux (Debian/Ubuntu рекомендуется)
- ~30 GB свободного места
- Интернет-соединение
- sudo доступ

### Зависимости (устанавливаются автоматически)

- curl, git, tar, xz-utils
- qemu-user-static (для ARM64 эмуляции)
- parted, e2fsprogs
- rsync, jq, openssl

## Структура скриптов

```
├── 00-build-arm64-artifacts-trixie.sh  # Сборка артефактов на хосте
├── 01-build-base-pi-image-trixie.sh    # Создание базового образа
├── 02-personalize-pi-image-trixie.sh   # Персонализация образа
├── verify-tools.sh                      # Проверка установки
└── hub/                                 # Hub приложение (опционально)
    ├── app.py
    ├── requirements.txt
    ├── templates/
    └── static/
```

## Шаг 1: Сборка артефактов

Скрипт `00-build-arm64-artifacts-trixie.sh` собирает на хосте:
- Go для ARM64
- Prebuilt бинарники (tailscale, nuclei, httpx, ffuf, dalfox, ligolo)
- Tarballs (Responder, dirsearch, SecLists, sqlmap, nuclei-templates)

### Запуск

```bash
bash 00-build-arm64-artifacts-trixie.sh
```

### Переменные окружения (опционально)

```bash
# Прокси для Go modules (по умолчанию goproxy.cn)
export GOPROXY="https://proxy.golang.org,direct"

# Директория для артефактов
export ART_DIR="./artifacts-arm64"

# Директория для логов
export LOG_DIR="./logs"

# Debug режим
export DEBUG=1
```

### Результат

```
artifacts-arm64/
├── bin/                    # Prebuilt бинарники
├── systemd/                # tailscaled.service
├── src/                    # Tarballs
├── cache/gomod/            # Go module cache
├── go-*.linux-arm64.tar.gz # Go для образа
└── NEEDS_IN_IMAGE_*        # Маркеры для CGO сборки
```

### Время выполнения

~30 минут (зависит от скорости интернета)

---

## Шаг 2: Создание базового образа

Скрипт `01-build-base-pi-image-trixie.sh`:
- Скачивает Raspberry Pi OS Lite (trixie)
- Расширяет образ до 16 GB
- Устанавливает все инструменты через chroot
- Собирает CGO-инструменты (naabu, bettercap, katana)

### Запуск

```bash
sudo ARTIFACTS_DIR="$(pwd)/artifacts-arm64" bash 01-build-base-pi-image-trixie.sh
```

### Переменные окружения

```bash
# ОБЯЗАТЕЛЬНО: путь к артефактам
export ARTIFACTS_DIR="/path/to/artifacts-arm64"

# Размер образа (по умолчанию 16G)
export IMG_SIZE="16G"

# Имя выходного файла
export BASE_IMG="rpi-base-$(date +%Y%m%d).img"

# Go proxy для сборки внутри образа
export GOPROXY_IMG="https://goproxy.cn,https://proxy.golang.org,direct"
```

### Результат

```
rpi-base-YYYYMMDD.img  # Базовый образ 16 GB
```

### Время выполнения

~1–2 часа (CGO сборка через qemu очень медленная)

### Важно

- Скрипт требует sudo
- CGO инструменты (naabu, bettercap, katana) собираются внутри образа через qemu эмуляцию — это нормально что занимает 1-2 часа
- Если скрипт упал — проверьте `logs/01-base.*.err`

---

## Шаг 3: Персонализация

Скрипт `02-personalize-pi-image-trixie.sh`:
- Получает preauth key от Headscale
- Устанавливает hostname (случайная пони)
- Настраивает Zabbix Agent
- Создаёт tailscale-firstboot сервис

### Запуск

```bash
export HEADSCALE_SERVER="your-headscale-server"
export HEADSCALE_USER="root"
export HEADSCALE_PASSWORD="your-password"

sudo -E bash 02-personalize-pi-image-trixie.sh rpi-base-YYYYMMDD.img
```

### Переменные окружения

```bash
# ОБЯЗАТЕЛЬНО: Headscale credentials
export HEADSCALE_SERVER="headscale.example.com"
export HEADSCALE_USER="root"
export HEADSCALE_PASSWORD="password"

# Zabbix настройки (опционально)
export ZBX_SERVER_IP="YOUR_TAILSCALE_IP"
export ZBX_SERVER_PORT="10051"
export ZBX_ENABLE_PSK="no"  # или "yes" для PSK шифрования
```

### Результат

```
image.{pony_name}.img  # Персонализированный образ
```

### Время выполнения

~2-3 минуты

---

## Запись на SD-карту

### Linux

```bash
# Найти устройство SD-карты
lsblk

# Записать образ (ОСТОРОЖНО с выбором устройства!)
sudo dd if=image.twilight_sparkle.img of=/dev/sdX bs=4M status=progress
sudo sync
```

### Windows

Использовать [Raspberry Pi Imager](https://www.raspberrypi.com/software/) или [balenaEtcher](https://etcher.balena.io/).

---

## Первый запуск

1. Вставить SD-карту в Raspberry Pi 5
2. Подключить питание
3. Дождаться загрузки (~1-2 минуты)
4. Устройство автоматически подключится к Tailscale

### Доступ

```bash
# SSH (через Tailscale IP или локальную сеть)
ssh kali@<ip>
# Пароль: YOUR_PASSWORD

# Web-терминал
http://<ip>:7681

# Hub интерфейс
http://<ip>:5000
```

### Проверка

```bash
bash verify-tools.sh
```

---

## Логи и отладка

### Структура логов

```
logs/
├── 00-artifacts.YYYYMMDD-HHMMSS.log  # stdout
├── 00-artifacts.YYYYMMDD-HHMMSS.err  # stderr
├── 01-base.YYYYMMDD-HHMMSS.log
├── 01-base.YYYYMMDD-HHMMSS.err
├── 02-personalize.YYYYMMDD-HHMMSS.log
└── 02-personalize.YYYYMMDD-HHMMSS.err
```

### При ошибках

1. Проверить `.err` файл соответствующего скрипта
2. Формат ошибки:
   ```
   ----
   [FATAL] rc=1
   [FATAL] line=123
   [FATAL] cmd=go install ...
   ----
   ```

### Debug режим

```bash
DEBUG=1 bash 01-build-base-pi-image-trixie.sh
```

---

## Частые проблемы

### "No space left on device"

Увеличить размер образа:
```bash
export IMG_SIZE="20G"
```

### pip/cryptography конфликт

Скрипт использует `--ignore-installed` для системного pip. Если проблема повторяется — проверить что используется правильная версия скрипта.

### CGO сборка зависает

Это нормально. naabu/bettercap/katana собираются через qemu эмуляцию и занимают 1-2 часа. Не прерывать!

### Tailscale не подключается

1. Проверить что Headscale сервер доступен
2. Проверить credentials
3. На устройстве: `journalctl -u tailscale-firstboot`

### Hub не запускается

```bash
# Проверить статус
sudo systemctl status hub

# Проверить Flask
/opt/hub/venv/bin/python -c "import flask"

# Переустановить если нужно
/opt/hub/venv/bin/pip install flask requests
sudo systemctl restart hub
```

---

## Полный пример

```bash
# 1. Клонировать репозиторий
git clone <repo> && cd <repo>

# 2. Собрать артефакты
bash 00-build-arm64-artifacts-trixie.sh

# 3. Собрать базовый образ
sudo ARTIFACTS_DIR="$(pwd)/artifacts-arm64" bash 01-build-base-pi-image-trixie.sh

# 4. Персонализировать
export HEADSCALE_SERVER="headscale.example.com"
export HEADSCALE_USER="root"
export HEADSCALE_PASSWORD="secret"
sudo -E bash 02-personalize-pi-image-trixie.sh rpi-base-*.img

# 5. Записать на SD-карту
sudo dd if=image.*.img of=/dev/sdX bs=4M status=progress
```
