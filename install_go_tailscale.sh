#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install_go_tailscale.sh
#
# Установка Go и сборка Tailscale из исходников.
# Работает на любой Linux-системе (amd64, arm64, armv6l/v7l).
#
# Что делает:
#   1. Устанавливает зависимости (wget, curl, git, build-essential, iptables)
#   2. Скачивает и устанавливает последнюю версию Go
#   3. Клонирует Tailscale из GitHub и собирает из исходников
#   4. Устанавливает systemd-сервис tailscaled
#
# Использование:
#   sudo bash install_go_tailscale.sh
#
# После установки:
#   sudo tailscale up --login-server https://your-headscale-server
# -----------------------------------------------------------------------------

set -euo pipefail

info() { echo -e "\e[1;34m[INFO]\e[0m $*"; }
err()  { echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

# Проверка root
[[ $EUID -eq 0 ]] || err "Запустите с sudo: sudo bash $0"

# --- 1. Зависимости ---
info "Установка зависимостей..."
apt-get update -qq
apt-get install -y -qq wget curl git build-essential iptables
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent

# --- 2. Определение архитектуры ---
UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
  aarch64)       ARCH=arm64  ;;
  armv6l|armv7l) ARCH=armv6l ;;
  x86_64)        ARCH=amd64  ;;
  *) err "Неподдерживаемая архитектура: $UNAME_ARCH" ;;
esac

# --- 3. Установка Go ---
GO_VERSION=$(curl -sL https://go.dev/VERSION?m=text | head -n1)
[[ -n "$GO_VERSION" ]] || err "Не удалось определить версию Go"

GO_URL="https://dl.google.com/go/${GO_VERSION}.linux-${ARCH}.tar.gz"
info "Скачивание Go ${GO_VERSION} для ${ARCH}..."
wget -q "$GO_URL" -O /tmp/go.tar.gz

info "Установка Go ${GO_VERSION}..."
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tar.gz
rm -f /tmp/go.tar.gz

export PATH="/usr/local/go/bin:$PATH"

# Добавляем Go в PATH для всех пользователей
if [[ ! -f /etc/profile.d/go.sh ]]; then
  cat > /etc/profile.d/go.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin
EOF
  chmod 644 /etc/profile.d/go.sh
fi

info "Go $(go version | awk '{print $3}') установлен"

# --- 4. Сборка Tailscale из исходников ---
WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

info "Клонирование репозитория Tailscale..."
git clone --depth 1 https://github.com/tailscale/tailscale.git "$WORK/tailscale"

info "Сборка tailscale и tailscaled..."
export GOBIN="$WORK/bin"
mkdir -p "$GOBIN"

cd "$WORK/tailscale"
go install ./cmd/tailscale ./cmd/tailscaled

# --- 5. Установка бинарников ---
info "Установка бинарников в /usr/sbin..."
install -m 0755 "$GOBIN/tailscale"  /usr/sbin/tailscale
install -m 0755 "$GOBIN/tailscaled" /usr/sbin/tailscaled

# --- 6. Настройка systemd ---
info "Установка systemd-сервиса..."
cp "$WORK/tailscale/cmd/tailscaled/tailscaled.service" /etc/systemd/system/tailscaled.service

# Параметры по умолчанию
cat > /etc/default/tailscaled <<'CONF'
PORT="0"
FLAGS=""
CONF

systemctl daemon-reload
systemctl enable --now tailscaled.service

# --- Готово ---
info "Проверка..."
tailscale version
tailscaled --version 2>/dev/null || true
systemctl is-active --quiet tailscaled && info "tailscaled запущен" || info "tailscaled не запущен (проверьте systemctl status tailscaled)"

echo ""
info "Установка завершена."
echo ""
echo "Следующий шаг — подключение к Headscale:"
echo "  sudo tailscale up --login-server https://your-headscale-server"
echo ""
echo "Или с pre-auth ключом:"
echo "  sudo tailscale up --login-server https://your-headscale-server --authkey <KEY>"
