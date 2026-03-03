# Архитектура

Централизованное управление распределёнными атакующими устройствами. Трёхуровневая модель.

## Обзор

Функции системы:
- Генерация и развёртывание образов устройств
- Мониторинг состояния инфраструктуры
- Удалённое управление через VPN
- Иерархическая организация устройств

## Схема

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': { 'primaryColor': '#1e1e1e', 'primaryTextColor': '#e8e8e8', 'primaryBorderColor': '#2a2a2a', 'lineColor': '#22c55e', 'secondaryColor': '#141414', 'tertiaryColor': '#0a0a0a'}}}%%
flowchart TB
    subgraph tailscale["TAILNET"]
        subgraph level1["УРОВЕНЬ 1: СЕРВЕРЫ"]
            HS[("Headscale<br/>VPN координатор<br/>публичный IP")]
            SRV["Infra Server<br/>Flask :5100<br/>Zabbix :8081"]
        end
        
        subgraph level2["УРОВЕНЬ 2: ХАБЫ"]
            H1["Raspberry Pi 5<br/>Hub :5000<br/>Terminal (ttyd) :7681"]
            H_OTHER[["Другие устройства,<br/>например<br/>Rock Pi E, NanoPi R5S, ..."]]
        end
    end
    
    subgraph level3["УРОВЕНЬ 3: ПЕРИФЕРИЯ"]
        E1["Keylogger<br/>ESP8266/ESP32"]
        E2["BadUSB<br/>ESP32"]
        E3[["Импланты"]]
    end
    
    HS <--> SRV
    SRV -->|HTTP API| H1
    SRV -->|Zabbix| H1
    SRV -.->|HTTP API| H_OTHER
    H1 <-->|Wi-Fi| E1
    H1 <-->|Wi-Fi| E2
    H1 <-.->|Wi-Fi| E3

    style tailscale fill:#0a0a0a,stroke:#22c55e,color:#e8e8e8
    style level1 fill:#1e1e1e,stroke:#ca8a04,color:#e8e8e8
    style level2 fill:#1e1e1e,stroke:#22c55e,color:#e8e8e8
    style level3 fill:#1e1e1e,stroke:#a855f7,color:#e8e8e8
    style HS fill:#141414,stroke:#2563eb,color:#60a5fa
    style SRV fill:#141414,stroke:#ca8a04,color:#eab308
    style H1 fill:#141414,stroke:#22c55e,color:#22c55e
    style H_OTHER fill:#141414,stroke:#22c55e,color:#a0a0a0,stroke-dasharray: 5 5
    style E1 fill:#141414,stroke:#a855f7,color:#c4b5fd
    style E2 fill:#141414,stroke:#a855f7,color:#c4b5fd
    style E3 fill:#141414,stroke:#a855f7,color:#a0a0a0,stroke-dasharray: 5 5
```

## Уровни системы

### Уровень 1: Сервер

Центральное управление всей инфраструктурой.

| Компонент | Расположение | Функции |
|-----------|--------------|---------|
| Headscale Server | Интернет (VPS) | Координация Tailscale VPN, авторизация устройств |
| Infra Server | Tailscale сеть | Веб-интерфейс, генерация образов, Zabbix мониторинг |

### Уровень 2: Хабы

Одноплатные компьютеры, развёрнутые на целевых локациях.

| Устройство | Назначение | Сервисы |
|------------|------------|---------|
| Raspberry Pi 5 | Основной хаб | Hub (:5000), ttyd (:7681), SSH (:22) |

Также поддерживаются: Rock Pi E (sniffer), NanoPi R5S (3-port router) и другие ARM64 SBC.

Особенности хабов:
- Подключены к Tailscale VPN
- eth0 отключён по умолчанию (безопасность)
- Zabbix Agent для мониторинга
- Управляют устройствами 3-го уровня через Wi-Fi AP

### Уровень 3: Периферия (ESP8266/ESP32)

Микроконтроллеры для специализированных задач.

| Устройство | Функция |
|------------|---------|
| Keylogger | Перехват ввода с клавиатуры |
| BadUSB | Эмуляция HID-устройств |
| Wi-Fi Deauth | Деаутентификация клиентов |
| BLE Scanner | Сканирование Bluetooth устройств |

Особенности:
- Работают автономно
- Подключаются к хабам через Wi-Fi (AP режим)
- Отдают логи по HTTP на хаб
- Не имеют прямого доступа в Tailscale

## Безопасность

- Все коммуникации через Tailscale VPN (WireGuard)
- eth0 на хабах отключён по умолчанию
- Веб-интерфейсы доступны только внутри VPN
- Периферия изолирована в локальной сети хаба
- Авторизация устройств через Headscale

## Компоненты репозитория

```
├── server/              # Infra Server (Flask)
│   ├── app.py          # Основное приложение
│   └── images/         # Генерация образов
├── hub/                 # Hub приложение (Flask)
│   └── app.py          # Управление периферией
├── image-scripts/       # Скрипты сборки образов
└── docs/               # Документация
```
