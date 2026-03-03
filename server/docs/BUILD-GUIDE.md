# Сборка образа Raspberry Pi (Trixie)

## Требования

- Linux с sudo
- ~30 GB свободного места
- Интернет

## Сборка

### 1. Артефакты (~30 мин)

```bash
bash 00-build-arm64-artifacts-trixie.sh
```

### 2. Базовый образ (~1-2 часа)

```bash
sudo ARTIFACTS_DIR="$(pwd)/artifacts-arm64" bash 01-build-base-pi-image-trixie.sh
```

> CGO инструменты (naabu, bettercap, katana) собираются через qemu — это долго, не прерывать!

### 3. Персонализация (~2-3 мин)

```bash
export HEADSCALE_SERVER="your-server"
export HEADSCALE_USER="root"
export HEADSCALE_PASSWORD="password"

sudo -E bash 02-personalize-pi-image-trixie.sh rpi-base-*.img
```

## Запись на SD 

**Linux:**
```bash
sudo dd if=image.*.img of=/dev/sdX bs=4M status=progress
```

**Windows:**
Использовать [Raspberry Pi Imager](https://www.raspberrypi.com/software/) или [balenaEtcher](https://etcher.balena.io/) — выбрать "Use custom" и указать .img файл.

## Первый запуск

1. Вставить SD в Pi 5
2. Подключить питание
3. Устройство автоматически подключится к Tailscale или необходимо запустить скрипт /usr/local/sbin/eth0-unlock.sh для разблокировки eth0

**Доступ:**
- SSH: `ssh kali@<ip>` (пароль: YOUR_PASSWORD)
- Web-терминал: `http://<ip>:7681`
- Hub: `http://<ip>:5000`

## Логи

При ошибках смотреть `logs/*.err`
