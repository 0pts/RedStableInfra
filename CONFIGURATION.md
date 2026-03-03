# Настройка перед запуском

В репозитории все реальные значения заменены на плейсхолдеры. Перед использованием нужно подставить свои данные.

---

## Плейсхолдеры и что подставить

| Плейсхолдер | Что подставить | Пример |
|-------------|----------------|--------|
| `YOUR_PASSWORD` | Пароль пользователя `kali` на устройствах | `MyStr0ngPass!` |
| `YOUR_TAILSCALE_IP` | IP вашего сервера в Tailscale-сети | `100.64.0.5` |
| `headscale.example.com` | Адрес вашего Headscale сервера | `vpn.mycompany.com` |
| `your-zabbix-password` | Пароль от Zabbix API (пользователь Admin) | `zabbix_api_pass` |
| `your-password-here` | Пароль SSH к Headscale серверу | `ssh_pass_123` |

---

## Где менять

### 1. Серверное приложение

**`server/.env.example`** → скопировать в `server/.env` и заполнить:

```
BIND_IP=<ваш Tailscale IP или 0.0.0.0>
BIND_PORT=5100
ZABBIX_URL=http://<ваш Tailscale IP>:8081
ZABBIX_API_URL=http://<ваш Tailscale IP>:8081/api_jsonrpc.php
ZABBIX_USER=Admin
ZABBIX_PASSWORD=<пароль Zabbix API>
HEADSCALE_SERVER=<адрес Headscale>
HEADSCALE_USER=root
HEADSCALE_PASSWORD=<пароль SSH к Headscale>
```

**`server/config.py`** — дефолтные значения (используются если нет `.env`):
- Строка `BIND_IP` — заменить `YOUR_TAILSCALE_IP` на IP сервера
- Строка `ZABBIX_URL` — заменить `YOUR_TAILSCALE_IP`
- Строка `ZABBIX_API_URL` — заменить `YOUR_TAILSCALE_IP`

**`server/templates/images.html`** — строка с `kali:YOUR_PASSWORD`:
- Заменить на реальный пароль пользователя в образе

---

### 2. Скрипты сборки образа

**`image-scripts/01-build-base-pi-image-trixie.sh`**:
- Поиск `YOUR_PASSWORD` — пароль пользователя `kali` (задаётся через `chpasswd`)
- Это пароль, с которым пользователь будет заходить по SSH

**`image-scripts/02-personalize-pi-image-trixie.sh`**:
- `YOUR_TAILSCALE_IP` — IP Zabbix-сервера в Tailscale (переменная `ZBX_SERVER_IP`)
- `YOUR_PASSWORD` — пароль пользователя `kali` (в `userconf.txt`)
- При запуске передаются через env: `HEADSCALE_SERVER`, `HEADSCALE_USER`, `HEADSCALE_PASSWORD`

---

### 3. Серверный скрипт персонализации

**`server/images/scripts/personalize.sh`**:
- `YOUR_PASSWORD` — пароль пользователя `kali`
- `headscale.example.com` → ваш Headscale login server (переменная `LOGIN_SERVER` внутри chroot)
- Credentials Headscale передаются через environment при вызове из Flask

---

### 4. Документация

Файлы в `docs/` и `server/docs/` содержат плейсхолдеры в примерах команд. Их менять не обязательно — это справочные примеры. Но если хотите актуальную документацию для команды:

- `docs/BUILD-GUIDE.md` — `YOUR_PASSWORD` в разделе "Доступ"
- `docs/IMAGE-CONTENTS.md` — `YOUR_PASSWORD` в описании пользователя
- `server/docs/BUILD-GUIDE.md` — `YOUR_PASSWORD` в разделе "Доступ"
- `server/docs/IMAGE-CONTENTS.md` — `YOUR_PASSWORD` в описании пользователя
- `server/docs/SERVER-SETUP.md` — `YOUR_TAILSCALE_IP` в примерах

---

## Быстрый старт

```bash
# 1. Скопировать и заполнить env
cp server/.env.example server/.env
nano server/.env

# 2. Найти и заменить плейсхолдеры в скриптах
grep -rn "YOUR_PASSWORD" image-scripts/
grep -rn "YOUR_TAILSCALE_IP" image-scripts/
grep -rn "headscale.example.com" server/images/scripts/

# 3. Заменить (пример для Linux)
sed -i 's/YOUR_PASSWORD/MyRealPassword/g' image-scripts/*.sh
sed -i 's/YOUR_PASSWORD/MyRealPassword/g' server/images/scripts/personalize.sh
sed -i 's/YOUR_TAILSCALE_IP/100.64.0.5/g' image-scripts/*.sh
sed -i 's|headscale.example.com|vpn.mycompany.com|g' server/images/scripts/personalize.sh
```

---

### 5. Hub (приложение на хабах)

Hub — веб-приложение для управления периферийными устройствами (ESP8266/ESP32 и др.), запускается на каждом Raspberry Pi.

**`hub/app.py`** — секретов нет, всё работает через локальную SQLite базу.

**`hub/Devices.db`** — НЕ включена в репозиторий. Создайте свою базу:

```sql
-- Таблица устройств
CREATE TABLE Devices (
    Name TEXT NOT NULL,
    Type TEXT NOT NULL,
    MAC  TEXT NOT NULL
);

-- Таблица паролей Wi-Fi по типу устройства
CREATE TABLE pass (
    Type TEXT NOT NULL,
    Pass TEXT NOT NULL
);

-- Пример
INSERT INTO Devices VALUES ('MyKeylogger', 'keylogger', 'aa:bb:cc:dd:ee:ff');
INSERT INTO pass VALUES ('keylogger', 'wifi_password_here');
```

---

