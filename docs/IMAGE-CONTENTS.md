# Raspberry Pi Pentest Image (Debian 13 Trixie)

Кастомный образ для Raspberry Pi 5 на базе Debian 13 (trixie) с предустановленным набором инструментов для пентеста и сетевого анализа.

## Базовая система

| Компонент | Версия |
|-----------|--------|
| ОС | Debian GNU/Linux 13 (trixie) |
| Ядро | 6.12.x aarch64 |
| Архитектура | ARM64 |
| Размер образа | 16 GB |
| Пользователь | kali:YOUR_PASSWORD |
| SSH | Включён по умолчанию |

## Языки программирования и рантаймы

| Инструмент | Путь | Описание |
|------------|------|----------|
| Python 3.13 | /usr/bin/python3 | Системный Python |
| pip | /usr/bin/pip | Менеджер пакетов Python |
| pipx | /usr/local/bin/pipx | Изолированная установка Python CLI |
| Go | /usr/local/go | Последняя версия Go |
| Rust | /opt/cargo | Rust toolchain (rustc, cargo) |
| uv | /usr/local/bin/uv | Быстрый Python package manager |

## Сетевые инструменты

### Сканирование и разведка

| Инструмент | Описание |
|------------|----------|
| nmap | Сетевой сканер портов |
| masscan | Быстрый сканер портов |
| naabu | Go-based port scanner (ProjectDiscovery) |
| nuclei | Vulnerability scanner с шаблонами |
| httpx | HTTP toolkit для веб-разведки |
| katana | Web crawler |
| ffuf | Fuzzer для веб-приложений |
| dalfox | XSS scanner |
| dirsearch | Directory bruteforcer |
| nikto | Web server scanner |

### DNS утилиты

| Инструмент | Описание |
|------------|----------|
| dig | DNS lookup utility |
| nslookup | DNS query tool |

### Перехват трафика

| Инструмент | Описание |
|------------|----------|
| tcpdump | Packet analyzer |
| bettercap | Network attack framework |
| mitmproxy | HTTP/HTTPS proxy |
| mitm6 | IPv6 MITM attack tool |
| macchanger | MAC address changer |

## Инструменты для пентеста

### Active Directory / Windows

| Инструмент | Описание |
|------------|----------|
| Impacket | Python AD/SMB toolkit (pipx) |
| NetExec (nxc) | Network execution tool |
| Certipy | AD Certificate Services tool |
| Responder | LLMNR/NBT-NS/MDNS poisoner |
| ldapsearch | LDAP query tool |
| kinit/klist | Kerberos utilities |

### Брутфорс и эксплуатация

| Инструмент | Описание |
|------------|----------|
| Hydra | Network login cracker |
| Metasploit | Exploitation framework |
| SQLMap | SQL injection tool |

### Туннелирование

| Инструмент | Описание |
|------------|----------|
| ligolo-agent | Tunneling agent |
| ligolo-proxy | Tunneling proxy |
| Tailscale | Mesh VPN client |

## Словари и шаблоны

| Ресурс | Путь | Описание |
|--------|------|----------|
| SecLists | /usr/share/seclists | Коллекция словарей (~6000 файлов) |
| Nuclei Templates | /opt/nuclei-templates | Шаблоны для nuclei (~5000 шаблонов) |

## Веб-сервисы

| Сервис | Порт | Описание |
|--------|------|----------|
| Hub | 5000 | Веб-интерфейс управления (Flask) |
| ttyd | 7681 | Web-терминал |
| SSH | 22 | Secure Shell |

## Системные сервисы

| Сервис | Статус | Описание |
|--------|--------|----------|
| tailscaled | enabled | Tailscale daemon |
| hub | enabled | Hub web UI |
| ttyd | enabled | Web terminal |
| zabbix-agent2 | enabled | Мониторинг |
| ssh | enabled | SSH server |
| NetworkManager | enabled | Сетевое управление |
| postgresql | enabled | База данных (для Metasploit) |

## Структура файловой системы

```
/opt/
├── hub/              # Hub приложение
│   ├── app.py
│   ├── venv/         # Python virtual environment
│   ├── templates/
│   └── static/
├── Responder/        # LLMNR/NBT-NS poisoner
├── dirsearch/        # Directory bruteforcer
├── sqlmap/           # SQL injection tool
├── nuclei-templates/ # Nuclei шаблоны
├── rustup/           # Rust installation
├── cargo/            # Cargo home
└── pipx/             # pipx home

/usr/local/
├── go/               # Go installation
├── bin/              # Все CLI инструменты
└── src/ttyd/         # ttyd source

/usr/share/
└── seclists/         # SecLists словари

/etc/
├── profile.d/
│   ├── go.sh         # Go PATH
│   ├── rust.sh       # Rust PATH
│   ├── pipx.sh       # pipx env
│   └── nuclei.sh     # Nuclei templates path
└── zabbix/
    └── zabbix_agent2.conf
```

## Переменные окружения

После логина автоматически настраиваются:

```bash
# Go
export PATH=$PATH:/usr/local/go/bin

# Rust
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
export PATH=/opt/cargo/bin:$PATH

# pipx
export PIPX_HOME=/opt/pipx
export PIPX_BIN_DIR=/usr/local/bin

# Nuclei
export NUCLEI_TEMPLATES=/opt/nuclei-templates
```

## Tailscale интеграция

При первом запуске образ автоматически подключается к Headscale серверу через сервис `tailscale-firstboot`. После успешного подключения сервис самоудаляется.

## Проверка установки

Для проверки что все инструменты установлены корректно:

```bash
bash verify-tools.sh
```

Скрипт проверяет:
- Наличие всех бинарников
- Существование директорий
- Статус systemd сервисов
- Сетевые интерфейсы
- Hub приложение
