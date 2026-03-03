# Headscale / Tailscale — Руководство

## Обзор

- **Headscale** — self-hosted сервер координации (замена Tailscale SaaS)
- **Tailscale** — клиент на устройствах, создаёт mesh VPN

## Headscale (серверная часть)

### Проверка статуса

```bash
# Статус сервиса
sudo systemctl status headscale

# Список всех нод
headscale nodes list
```

### Управление нодами

```bash
# Список нод
headscale nodes list

# Удалить ноду по ID
headscale nodes delete --identifier <NODE_ID>

# Удалить ноду по имени
headscale nodes delete --identifier $(headscale nodes list -o json | jq -r '.[] | select(.givenName=="hostname") | .id')

# Переименовать ноду
headscale nodes rename --identifier <NODE_ID> new-hostname

# Принудительно отключить ноду (expire)
headscale nodes expire --identifier <NODE_ID>
```

### Теги (ACL Tags)

Теги используются для управления доступом через ACL.

```bash
# Присвоить тег ноде
headscale nodes tag --identifier <NODE_ID> --tags tag:server

# Несколько тегов
headscale nodes tag --identifier <NODE_ID> --tags tag:server,tag:prod

# Убрать все теги
headscale nodes tag --identifier <NODE_ID> --tags ""

# Посмотреть теги ноды
headscale nodes list -o json | jq '.[] | select(.id==<NODE_ID>) | .forcedTags'
```

**Важно:** теги должны начинаться с `tag:` и быть определены в ACL политике.

### Pre-auth ключи

```bash
# Создать одноразовый ключ
headscale preauthkeys create --user redteam

# Создать многоразовый ключ
headscale preauthkeys create --user redteam --reusable

# Создать ключ с истечением (24 часа)
headscale preauthkeys create --user redteam --expiration 24h

# Список ключей
headscale preauthkeys list --user redteam
```

## Tailscale (клиентская часть)

### Подключение к Headscale

```bash
# Подключение с pre-auth ключом
sudo tailscale up --login-server https://headscale.example.com --authkey <PREAUTH_KEY>

# Подключение интерактивно (покажет URL для авторизации)
sudo tailscale up --login-server https://headscale.example.com

# Принудительная переавторизация
sudo tailscale up --login-server https://headscale.example.com --force-reauth
```

### Проверка статуса

```bash
# Статус подключения
tailscale status

# Подробный статус (JSON)
tailscale status --json

# IP адрес в сети Tailscale
tailscale ip

# Информация о текущей ноде
tailscale whois $(tailscale ip)
```

### Диагностика

```bash
# Проверка соединения с другой нодой
tailscale ping <hostname-or-ip>

# Сетевая диагностика
tailscale netcheck

# Debug информация
tailscale debug
```

### Управление

```bash
# Отключиться от сети (но оставить сервис)
sudo tailscale down

# Полный logout (удалит ноду с сервера)
sudo tailscale logout

# Перезапустить демон
sudo systemctl restart tailscaled
```

## Добавление нового устройства

### Вариант 1: Pre-auth ключ (автоматически)

На сервере Headscale:
```bash
headscale preauthkeys create --user redteam --expiration 1h
# Скопировать ключ
```

На новом устройстве:
```bash
# Установить Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Подключиться
sudo tailscale up --login-server https://headscale.example.com --authkey <KEY>
```

### Вариант 2: Интерактивно

На новом устройстве:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --login-server https://headscale.example.com
# Покажет URL — открыть в браузере или скопировать команду
```

На сервере Headscale:
```bash
# Одобрить ноду (если требуется)
headscale nodes register --user redteam --key nodekey:<KEY_FROM_URL>
```