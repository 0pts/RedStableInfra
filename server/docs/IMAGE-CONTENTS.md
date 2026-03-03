# Raspberry Pi Pentest Image (Trixie)

Образ для Raspberry Pi 5 на базе Debian 13 (trixie) с инструментами для пентеста.

## Система

- **ОС:** Debian 13 (trixie) ARM64
- **Размер:** 16 GB 
- **SSH:** включён
- **Пользователь:** `kali` / `YOUR_PASSWORD`

## Сетевая безопасность (eth0-guard)

Ethernet интерфейс (eth0) по умолчанию **отключён** для безопасности. NetworkManager полностью игнорирует eth0.

### Первый запуск

1. `eth0-guard.service` отключает eth0 при загрузке
2. `tailscale-firstboot.service` временно поднимает eth0 для получения DHCP
3. Устройство подключается к Tailscale (Headscale)
4. eth0 автоматически отключается после успешного подключения
5. Скрипт удаляет сам себя — повторно не запускается

### Последующие запуски

eth0 остаётся отключённым. Разблокировка возможна двумя способами:

**Способ 1: GPIO (физический)**
- Замкнуть GPIO17 (pin 11) на GND (pin 9)
- Сервис `eth0-guard-watch.service` автоматически поднимет eth0

**Способ 2: Скрипт (через SSH/Tailscale)**
```bash
sudo /usr/local/sbin/eth0-unlock.sh
```

### Повторная блокировка

```bash
sudo /usr/local/sbin/eth0-guard.sh
```

### Конфигурация GPIO

Файл `/etc/default/eth0-guard`:
```ini
GPIOCHIP=gpiochip0
GPIOLINE=17
ALLOW_LEVEL=0   # 0 = пин замкнут на GND → разрешить eth0
```

## Мониторинг (Zabbix)

Zabbix Agent 2 предустановлен и настроен на авторегистрацию.

- **Сервер:** задаётся через `ZBX_SERVER_IP` при сборке (по умолчанию `YOUR_TAILSCALE_IP`)
- **HostMetadata:** `autoreg-rpi` — для автоматического добавления в Zabbix
- **Hostname:** имя пони (например `twilight_sparkle`)

Конфиг: `/etc/zabbix/zabbix_agent2.conf`

## Инструменты

**Сканирование:** nmap, masscan, naabu, nuclei, httpx, katana, ffuf, dalfox, dirsearch, nikto

**AD/Windows:** Impacket, NetExec (nxc), Certipy, Responder, ldapsearch, kinit/klist

**MITM:** bettercap, mitmproxy, mitm6, tcpdump, macchanger

**Эксплуатация:** Metasploit, Hydra, SQLMap

**Туннели:** ligolo-agent/proxy, Tailscale

**Языки:** Python 3.13, Go, Rust, uv

## Словари

- `/usr/share/seclists` — SecLists (~6000 файлов)
- `/opt/nuclei-templates` — Nuclei шаблоны (~5000)

## Сервисы

| Сервис | Порт | Описание |
|--------|------|----------|
| Hub | 5000 | Веб-интерфейс |
| ttyd | 7681 | Web-терминал |
| SSH | 22 | Secure Shell |
| Zabbix Agent | 10050 | Мониторинг (active checks) |

## Systemd сервисы

| Сервис | Описание |
|--------|----------|
| `hub.service` | Flask веб-интерфейс |
| `ttyd.service` | Web-терминал |
| `tailscaled.service` | Tailscale daemon |
| `zabbix-agent2.service` | Zabbix мониторинг |
| `eth0-guard.service` | Блокировка eth0 при загрузке |
| `eth0-guard-watch.service` | GPIO мониторинг для разблокировки eth0 |

## Проверка

```bash
bash verify-tools.sh
```
