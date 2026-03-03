#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# verify-tools.sh
# Проверка установки всех инструментов на Raspberry Pi после сборки образа.
# Запускать на устройстве: bash verify-tools.sh
# -----------------------------------------------------------------------------

set -uo pipefail

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
NC='\e[0m'

PASS=0
FAIL=0
WARN=0

ok()   { echo -e "${GREEN}[✓]${NC} $*"; ((PASS++)); }
fail() { echo -e "${RED}[✗]${NC} $*"; ((FAIL++)); }
warn() { echo -e "${YELLOW}[!]${NC} $*"; ((WARN++)); }
info() { echo -e "${BLUE}[i]${NC} $*"; }

# Инструменты которые зависают на --version или не поддерживают его
declare -A SKIP_VERSION=(
  [ligolo-proxy]=1
  [msfconsole]=1
  [responder]=1
  [bettercap]=1
  [nslookup]=1
  [kinit]=1
  [klist]=1
)

check_bin() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    local path ver
    path="$(command -v "$name")"
    if [[ -n "${SKIP_VERSION[$name]:-}" ]]; then
      ver="(skip --version)"
    else
      # timeout для команд которые могут зависнуть
      ver="$(timeout 2s "$name" --version 2>/dev/null | head -n1 || echo "?")"
    fi
    ok "$name → $path ($ver)"
  else
    fail "$name — НЕ НАЙДЕН"
  fi
}

check_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    local count
    count="$(find "$dir" -type f 2>/dev/null | wc -l)"
    ok "$dir (${count} файлов)"
  else
    fail "$dir — НЕ СУЩЕСТВУЕТ"
  fi
}

check_service() {
  local svc="$1"
  if systemctl is-enabled "$svc" >/dev/null 2>&1; then
    local status
    status="$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")"
    if [[ "$status" == "active" ]]; then
      ok "service $svc (enabled, active)"
    else
      warn "service $svc (enabled, $status)"
    fi
  else
    fail "service $svc — НЕ ВКЛЮЧЁН"
  fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "          ПРОВЕРКА ИНСТРУМЕНТОВ RASPBERRY PI IMAGE"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# --- OS Info ---
info "Информация о системе:"
echo "  Hostname: $(hostname)"
grep -E "^(PRETTY_NAME|VERSION_CODENAME)=" /etc/os-release 2>/dev/null | sed 's/^/  /'
uname -a | sed 's/^/  /'
echo ""

# --- MUST Binaries ---
echo "─────────────────────────────────────────────────────────────────"
echo "ОБЯЗАТЕЛЬНЫЕ БИНАРНИКИ (MUST)"
echo "─────────────────────────────────────────────────────────────────"

echo ""
info "Python/pip/pipx:"
check_bin python3
check_bin pip
check_bin pipx

echo ""
info "Go/Rust/uv:"
check_bin go
check_bin rustc
check_bin cargo
check_bin uv

echo ""
info "Tailscale/ttyd/Zabbix:"
check_bin tailscale
check_bin tailscaled
check_bin ttyd
check_bin zabbix_agent2

echo ""
info "Базовые утилиты:"
check_bin psql
check_bin vim
check_bin ponysay
check_bin fastfetch

echo ""
info "Сетевые инструменты:"
check_bin nmap
check_bin masscan
check_bin naabu
check_bin dig
check_bin nslookup
check_bin tcpdump
check_bin bettercap
check_bin macchanger

echo ""
info "MITM/Proxy:"
check_bin mitmproxy
check_bin mitm6
check_bin certipy
check_bin nxc

echo ""
info "Pentest tools:"
check_bin hydra
check_bin msfconsole
check_bin sqlmap
check_bin responder
check_bin dirsearch
check_bin nikto

echo ""
info "Web recon:"
check_bin nuclei
check_bin httpx
check_bin katana
check_bin ffuf
check_bin dalfox

echo ""
info "Kubernetes/Ligolo:"
check_bin kubectl
check_bin ligolo-agent
check_bin ligolo-proxy

echo ""
info "LDAP/Kerberos:"
check_bin ldapsearch
check_bin kinit
check_bin klist

# --- MUST Directories ---
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "ОБЯЗАТЕЛЬНЫЕ ДИРЕКТОРИИ"
echo "─────────────────────────────────────────────────────────────────"
check_dir /usr/share/seclists
check_dir /opt/Responder
check_dir /opt/dirsearch
check_dir /opt/sqlmap
check_dir /opt/nuclei-templates
check_dir /opt/hub

# --- Services ---
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "SYSTEMD СЕРВИСЫ"
echo "─────────────────────────────────────────────────────────────────"
check_service tailscaled
check_service hub
check_service ttyd
check_service zabbix-agent2
check_service ssh
check_service NetworkManager
check_service postgresql

# --- Network ---
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "СЕТЕВЫЕ ИНТЕРФЕЙСЫ"
echo "─────────────────────────────────────────────────────────────────"
info "IP адреса:"
ip -4 addr show 2>/dev/null | grep -E "inet " | sed 's/^/  /'

info "Tailscale статус:"
if tailscale status >/dev/null 2>&1; then
  tailscale status 2>/dev/null | head -n5 | sed 's/^/  /'
else
  warn "Tailscale не подключён"
fi

# --- Hub check ---
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "HUB ПРИЛОЖЕНИЕ"
echo "─────────────────────────────────────────────────────────────────"
if [[ -f /opt/hub/app.py ]]; then
  ok "/opt/hub/app.py существует"
  if [[ -d /opt/hub/venv ]]; then
    ok "/opt/hub/venv существует"
    if /opt/hub/venv/bin/python -c "import flask" 2>/dev/null; then
      ok "Flask установлен в venv"
    else
      fail "Flask НЕ установлен в venv"
    fi
  else
    fail "/opt/hub/venv НЕ существует"
  fi
else
  warn "/opt/hub/app.py не найден (hub не установлен)"
fi

# --- Summary ---
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                         ИТОГО"
echo "═══════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}Успешно:${NC}    $PASS"
echo -e "  ${RED}Ошибок:${NC}     $FAIL"
echo -e "  ${YELLOW}Warnings:${NC}   $WARN"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}✓ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ!${NC}"
  exit 0
else
  echo -e "${RED}✗ ЕСТЬ ПРОБЛЕМЫ ($FAIL ошибок)${NC}"
  exit 1
fi
