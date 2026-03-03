# Мониторинг Zabbix: метрики и графики

## Обзор

Zabbix Agent 2 на каждом хабе (Raspberry Pi) отправляет метрики на сервер.
Ниже — список доступных items по категориям.

---

## 1. CPU

| Item | Key | Интервал | Что показывает |
|------|-----|----------|----------------|
| CPU utilization | `system.cpu.util` (calculated) | 1m | Общая загрузка CPU в % |
| CPU user time | `system.cpu.util[,user]` | 1m | Время в user-space |
| CPU system time | `system.cpu.util[,system]` | 1m | Время в kernel-space |
| CPU iowait time | `system.cpu.util[,iowait]` | 1m | Ожидание I/O |
| CPU idle time | `system.cpu.util[,idle]` | 1m | Простой |
| CPU nice/steal/irq/softirq/guest | `system.cpu.util[,*]` | 1m | Детализация |
| Load average 1/5/15m | `system.cpu.load[all,avg1/5/15]` | 1m | Средняя нагрузка |
| Context switches/sec | `system.cpu.switches` | 1m | Переключения контекста |
| Interrupts/sec | `system.cpu.intr` | 1m | Аппаратные прерывания |
| Number of CPUs | `system.cpu.num` | 1m | Количество ядер |

**Графики:**
- CPU Utilization (%) — stacked area: user + system + iowait + idle
- Load Average — line: avg1, avg5, avg15 на одном графике
- Context Switches + Interrupts — line (для диагностики аномалий)

---

## 2. Память

| Item | Key | Интервал | Что показывает |
|------|-----|----------|----------------|
| Total memory | `vm.memory.size[total]` | 1m | Всего RAM |
| Available memory | `vm.memory.size[available]` | 1m | Доступно RAM (байты) |
| Available memory % | `vm.memory.size[pavailable]` | 1m | Доступно RAM (%) |
| Memory utilization | `vm.memory.utilization` | — | Использование RAM (%) |
| Total swap | `system.swap.size[,total]` | 1m | Всего swap |
| Free swap | `system.swap.size[,free]` | 1m | Свободный swap |
| Free swap % | `system.swap.size[,pfree]` | 1m | Свободный swap (%) |

**Графики:**
- Memory Usage (%) — line: utilization
- Memory Available vs Total — area
- Swap Usage — line (если swap > 0)

---

## 3. Диск / Файловая система

| Item | Key | Что показывает |
|------|-----|----------------|
| FS [/]: Space Total | `vfs.fs.dependent.size[/,total]` | Размер раздела |
| FS [/]: Space Used | `vfs.fs.dependent.size[/,used]` | Занято |
| FS [/]: Space Available | `vfs.fs.dependent.size[/,free]` | Свободно |
| FS [/]: Space Used % | `vfs.fs.dependent.size[/,pused]` | Занято (%) |
| FS [/]: Inodes Free % | `vfs.fs.dependent.inode[/,pfree]` | Свободные inodes (%) |
| FS [/]: Read-only | `vfs.fs.dependent[/,readonly]` | Флаг read-only |
| mmcblk0: Disk read rate | `vfs.dev.read.rate[mmcblk0]` | Чтение (ops/sec) |
| mmcblk0: Disk write rate | `vfs.dev.write.rate[mmcblk0]` | Запись (ops/sec) |
| mmcblk0: Disk utilization | `vfs.dev.util[mmcblk0]` | Утилизация диска (%) |
| mmcblk0: Queue size | `vfs.dev.queue_size[mmcblk0]` | Очередь I/O |
| mmcblk0: Read await | `vfs.dev.read.await[mmcblk0]` | Задержка чтения (ms) |
| mmcblk0: Write await | `vfs.dev.write.await[mmcblk0]` | Задержка записи (ms) |

**Графики:**
- Disk Space Usage (%) — line/gauge: pused
- Disk I/O — stacked area: read rate + write rate
- Disk Latency — line: read await + write await
- Disk Utilization (%) — line

---

## 4. Сеть

Доступны интерфейсы: **eth0**, **wlan0**, **tailscale0**

| Item | Key (пример для eth0) | Что показывает |
|------|------------------------|----------------|
| Bits received | `net.if.in["eth0"]` | Входящий трафик |
| Bits sent | `net.if.out["eth0"]` | Исходящий трафик |
| Inbound errors | `net.if.in["eth0",errors]` | Ошибки входящие |
| Outbound errors | `net.if.out["eth0",errors]` | Ошибки исходящие |
| Inbound dropped | `net.if.in["eth0",dropped]` | Отброшенные входящие |
| Outbound dropped | `net.if.out["eth0",dropped]` | Отброшенные исходящие |
| Operational status | `operstate` файл | UP/DOWN |
| Speed | `speed` файл | Скорость линка |

**Графики:**
- Network Traffic (bits/sec) — stacked area: in + out (для каждого интерфейса)
- Network Errors — line: errors + dropped (для алертов)
- Tailscale Traffic — отдельный график для VPN-трафика

---

## 5. Система

| Item | Key | Что показывает |
|------|-----|----------------|
| System uptime | `system.uptime` | Время работы |
| Number of processes | `proc.num` | Всего процессов |
| Running processes | `proc.num[,,run]` | Активных процессов |
| Logged in users | `system.users.num` | Залогиненных пользователей |
| System name | `system.hostname` | Имя хоста |
| OS | `system.sw.os` | Версия ОС |
| Architecture | `system.sw.arch` | Архитектура |
| Boot time | `system.boottime` | Время последней загрузки |
| Installed packages | `system.sw.packages.get` | Количество пакетов |
| Max open files | `kernel.maxfiles` | Лимит файловых дескрипторов |
| Max processes | `kernel.maxproc` | Лимит процессов |
| /etc/passwd checksum | `vfs.file.cksum[/etc/passwd,sha256]` | Контроль целостности |

**Графики:**
- Uptime — value widget (дни/часы)
- Processes — line: total + running

---

## 6. Zabbix Agent

| Item | Key | Что показывает |
|------|-----|----------------|
| Agent ping | `agent.ping` | Агент жив (1/0) |
| Agent availability | `zabbix[host,agent,available]` | Доступность |
| Agent version | `agent.version` | Версия агента |
| Agent hostname | `agent.hostname` | Имя в конфиге |

---

## Рекомендуемые графики для Dashboard

### Критичные

1. **Agent Availability** — онлайн/офлайн (agent.ping)
2. **CPU Utilization %** — перегрузка процессора
3. **Memory Utilization %** — утечки памяти, OOM
4. **Disk Space Used %** — заполнение SD-карты
5. **System Uptime** — перезагрузки (проблемы с питанием)

### Диагностика

6. **Network Traffic (tailscale0)** — VPN-трафик
7. **Network Traffic (wlan0)** — Wi-Fi трафик
8. **Load Average** — общая нагрузка
9. **Disk I/O** — bottleneck SD-карты

### Расширенные

10. **CPU breakdown** (user/system/iowait)
11. **Disk Latency** — деградация SD-карты
12. **Network Errors** — проблемы Wi-Fi
13. **/etc/passwd checksum** — контроль целостности
