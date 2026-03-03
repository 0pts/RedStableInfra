# Установка серверного приложения

## Быстрая установка

```bash
# 1. Клонировать/скопировать server/ в /opt/redteam-server
sudo mkdir -p /opt/redteam-server
sudo cp -r server/* /opt/redteam-server/

# 2. Создать venv и установить зависимости
cd /opt/redteam-server
sudo python3 -m venv venv
sudo venv/bin/pip install -r requirements.txt

# 3. Настроить переменные окружения
cp .env.example .env
nano .env  # заполнить значения

# 4. Запустить
sudo venv/bin/python app.py
```

## Доступ

- Web UI: `http://<server-ip>:5100`

## Требования

- Python 3.10+
- Tailscale установлен и подключён к сети
- Любая машина внутри Tailscale сети (не обязательно headscale сервер)
