#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 00-build-arm64-artifacts-trixie.sh
# На хосте готовит артефакты для ARM64 (Debian 13 trixie):
#  - Go latest для хоста (чтобы собирать) и Go tar.gz для ARM64 (в образ)
#  - tailscale/tailscaled (arm64) + tailscaled.service
#  - nuclei/httpx/ffuf/dalfox + ligolo-agent/ligolo-proxy (arm64)
#  - tarball-исходники: Responder/dirsearch/SecLists/sqlmap/nuclei-templates
#  - markers: naabu/bettercap/katana (соберём в образе с CGO)
#
# Логи:
#  logs/00-artifacts.<timestamp>.log
#  logs/00-artifacts.<timestamp>.err
# -----------------------------------------------------------------------------

set -euo pipefail
[[ ${DEBUG:-0} -eq 1 ]] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/00-artifacts.${RUN_ID}.log"
ERR_FILE="$LOG_DIR/00-artifacts.${RUN_ID}.err"

exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$ERR_FILE" >&2)

on_err() {
  local rc=$?
  {
    echo "----"
    echo "[FATAL] rc=$rc"
    echo "[FATAL] line=${BASH_LINENO[0]}"
    echo "[FATAL] cmd=${BASH_COMMAND}"
    echo "----"
  } >> "$ERR_FILE"
  exit $rc
}
trap on_err ERR

echo "[INFO] Logs: $LOG_FILE"
echo "[INFO] Errs: $ERR_FILE"

START_TIME=$(date +%s)

ART_DIR="${ART_DIR:-$SCRIPT_DIR/artifacts-arm64}"
BIN_DIR="$ART_DIR/bin"
SYS_DIR="$ART_DIR/systemd"
SRC_DIR="$ART_DIR/src"
CACHE_DIR="$ART_DIR/cache"
GO_WORK="$ART_DIR/_go"
GOPATH_DIR="$ART_DIR/gopath"

# Прокси для Go modules с fallback
export GOPROXY="${GOPROXY:-https://goproxy.cn,https://proxy.golang.org,direct}"
export GOSUMDB="${GOSUMDB:-off}"
export GODEBUG="${GODEBUG:-http2client=0}"
export GIT_TERMINAL_PROMPT=0

mkdir -p "$BIN_DIR" "$SYS_DIR" "$SRC_DIR" "$CACHE_DIR" "$GO_WORK" "$GOPATH_DIR"
rm -f "$ART_DIR"/NEEDS_IN_IMAGE_* 2>/dev/null || true

need(){ command -v "$1" >/dev/null 2>&1; }
info(){ echo -e "\e[1;34m[INFO]\e[0m $*"; }
warn(){ echo -e "\e[1;33m[WARN]\e[0m $*"; }
err(){ echo "[ERROR] $*" >&2; exit 1; }

# curl через HTTP/1.1 (меньше HTTP/2 CANCEL на больших архивах)
# --retry-delay 5: пауза между попытками
# --speed-limit/--speed-time: прерывать если скорость < 1KB/s более 60 сек
curl_retry() {
  curl --http1.1 -fL \
    --retry 8 --retry-all-errors --retry-delay 5 \
    --connect-timeout 30 --max-time 600 \
    --speed-limit 1024 --speed-time 60 \
    "$@"
}

# deps
DEPS=(curl git tar xz)
MISS=()
for d in "${DEPS[@]}"; do need "$d" || MISS+=("$d"); done
if ((${#MISS[@]})); then
  info "Installing host deps: ${MISS[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y -qq curl git tar xz-utils
fi

# --- 1) Go for host ---
info "Fetching latest Go version…"
GO_VERSION="$(curl_retry https://go.dev/VERSION?m=text | head -n1)"
[[ -n "$GO_VERSION" ]] || err "Could not fetch Go version"
info "Go version: $GO_VERSION"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64) GO_HOST_ARCH=amd64 ;;
  aarch64) GO_HOST_ARCH=arm64 ;;
  armv6l|armv7l) GO_HOST_ARCH=armv6l ;;
  *) err "Unsupported host arch: $HOST_ARCH" ;;
esac

GO_HOST_URL="https://dl.google.com/go/${GO_VERSION}.linux-${GO_HOST_ARCH}.tar.gz"
info "Downloading Go for host ($GO_HOST_ARCH)…"
curl_retry "$GO_HOST_URL" -o "$GO_WORK/go-host.tgz"

rm -rf "$GO_WORK/go"
mkdir -p "$GO_WORK/go"
tar -C "$GO_WORK/go" -xzf "$GO_WORK/go-host.tgz"

export PATH="$GO_WORK/go/go/bin:$PATH"
go version

# --- 2) Go for ARM64 (в образ) ---
GO_ARM_URL="https://dl.google.com/go/${GO_VERSION}.linux-arm64.tar.gz"
info "Downloading Go for ARM64 (for image)…"
curl_retry "$GO_ARM_URL" -o "$ART_DIR/go-${GO_VERSION}.linux-arm64.tar.gz"

# --- 3) Cross env ---
export GOOS=linux
export GOARCH=arm64
export CGO_ENABLED=0
export GOPATH="$GOPATH_DIR"
export GOMODCACHE="$CACHE_DIR/gomod"
export GOCACHE="$CACHE_DIR/gobuild"
mkdir -p "$GOMODCACHE" "$GOCACHE"

CROSS_BIN_DIR="$GOPATH/bin/${GOOS}_${GOARCH}"
mkdir -p "$CROSS_BIN_DIR"

go_install_retry() {
  local name="$1"; shift
  local i
  for i in 1 2 3; do
    info "go install ($name) attempt $i/3: $*"
    if go install -v "$@"; then return 0; fi
    warn "go install ($name) failed, retry in 5s…"
    sleep 5
  done
  return 1
}

copy_cross_bin() {
  local src_name="$1" dst_name="${2:-$1}"
  [[ -x "$CROSS_BIN_DIR/$src_name" ]] || return 1
  install -m0755 "$CROSS_BIN_DIR/$src_name" "$BIN_DIR/$dst_name"
}

# --- 4) tailscale from source (arm64) ---
info "Building tailscale from source (arm64)…"
TS_DIR="$GO_WORK/tailscale"
rm -rf "$TS_DIR"
git clone --depth 1 https://github.com/tailscale/tailscale.git "$TS_DIR"
pushd "$TS_DIR" >/dev/null
go build -trimpath -ldflags "-s -w" -o "$BIN_DIR/tailscale"  ./cmd/tailscale
go build -trimpath -ldflags "-s -w" -o "$BIN_DIR/tailscaled" ./cmd/tailscaled
cp -f cmd/tailscaled/tailscaled.service "$SYS_DIR/tailscaled.service"
popd >/dev/null
chmod +x "$BIN_DIR/tailscale" "$BIN_DIR/tailscaled"

# --- 5) Go tools (no-CGO) ---
info "Building Go tools (cross, no-CGO)…"

go_install_retry nuclei github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
copy_cross_bin nuclei || err "nuclei binary not found"

go_install_retry httpx github.com/projectdiscovery/httpx/cmd/httpx@latest
copy_cross_bin httpx || err "httpx binary not found"

go_install_retry ffuf github.com/ffuf/ffuf/v2@latest
copy_cross_bin ffuf || err "ffuf binary not found"

go_install_retry dalfox github.com/hahwul/dalfox/v2@latest
copy_cross_bin dalfox || err "dalfox binary not found"

# ligolo (если не соберётся — соберём внутри образа)
if go_install_retry ligolo-agent github.com/nicocha30/ligolo-ng/cmd/agent@latest && copy_cross_bin agent ligolo-agent; then
  info "ligolo-agent OK"
else
  warn "ligolo-agent will be built inside image"
  echo "ligolo" > "$ART_DIR/NEEDS_IN_IMAGE_LIGOLO"
fi

if go_install_retry ligolo-proxy github.com/nicocha30/ligolo-ng/cmd/proxy@latest && copy_cross_bin proxy ligolo-proxy; then
  info "ligolo-proxy OK"
else
  warn "ligolo-proxy will be built inside image"
  echo "ligolo" > "$ART_DIR/NEEDS_IN_IMAGE_LIGOLO"
fi

# --- 6) Markers for CGO/problematics ---
echo "naabu"     > "$ART_DIR/NEEDS_IN_IMAGE_NAABU"
echo "bettercap" > "$ART_DIR/NEEDS_IN_IMAGE_BETTERCAP"
echo "katana"    > "$ART_DIR/NEEDS_IN_IMAGE_KATANA"
warn "naabu/bettercap/katana will be built inside image (CGO/libpcap etc.)"

# --- 7) Tarballs (параллельная загрузка для ускорения) ---
fetch_tar() {
  local name="$1" url="$2"
  local dst="$SRC_DIR/$name"
  info "Fetching $name tarball…"
  rm -rf "$dst"; mkdir -p "$dst"
  local tmp="$GO_WORK/${name}.tgz"
  local i
  for i in 1 2 3; do
    info "Downloading $name (attempt $i/3)…"
    rm -f "$tmp"
    if curl_retry "$url" -o "$tmp" && gzip -t "$tmp" 2>/dev/null; then
      tar -xzf "$tmp" -C "$dst" --strip-components=1
      rm -f "$tmp"
      return 0
    fi
    warn "$name download corrupted or incomplete, retrying in 10s…"
    sleep 10
  done
  err "Failed to download $name after 3 attempts"
}

# Параллельная загрузка для ускорения
info "Downloading tarballs in parallel…"
fetch_tar Responder "https://github.com/lgandx/Responder/archive/refs/heads/master.tar.gz" &
PID_RESPONDER=$!
fetch_tar dirsearch "https://github.com/maurosoria/dirsearch/archive/refs/heads/master.tar.gz" &
PID_DIRSEARCH=$!
fetch_tar sqlmap "https://github.com/sqlmapproject/sqlmap/archive/refs/heads/master.tar.gz" &
PID_SQLMAP=$!
fetch_tar nuclei-templates "https://github.com/projectdiscovery/nuclei-templates/archive/refs/heads/master.tar.gz" &
PID_NUCLEI=$!

# SecLists большой, качаем отдельно чтобы не блокировать
wait $PID_RESPONDER || warn "Responder download failed"
wait $PID_DIRSEARCH || warn "dirsearch download failed"
wait $PID_SQLMAP || warn "sqlmap download failed"
wait $PID_NUCLEI || warn "nuclei-templates download failed"

# SecLists качаем последним (самый большой)
fetch_tar SecLists "https://github.com/danielmiessler/SecLists/archive/refs/heads/master.tar.gz"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

info "Artifacts ready in: $ART_DIR"
echo "  - markers:"
ls -1 "$ART_DIR"/NEEDS_IN_IMAGE_* 2>/dev/null || true
echo "[INFO] SUCCESS. Elapsed time: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
echo "[INFO] If something fails later, send: $ERR_FILE"
