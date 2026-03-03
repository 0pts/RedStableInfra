#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 01-build-base-pi-image-trixie.sh
#
# Базовый образ Raspberry Pi OS Lite (arm64, Debian 13 trixie).
# + Автозапуск hub как только это возможно (NetworkManager + tailscaled).
#
# Требует артефакты из 00:
#   ARTIFACTS_DIR=/path/to/artifacts-arm64
#
# Требует исходники hub в папке рядом со скриптом:
#   ./hub/app.py, ./hub/requirements.txt, ./hub/templates, ./hub/static
#
# Логи:
#   logs/01-base.<timestamp>.log
#   logs/01-base.<timestamp>.err
# -----------------------------------------------------------------------------

set -euo pipefail
[[ ${DEBUG:-0} -eq 1 ]] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/01-base.${RUN_ID}.log"
ERR_FILE="$LOG_DIR/01-base.${RUN_ID}.err"

exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$ERR_FILE" >&2)
trap 'rc=$?; echo "----" >>"$ERR_FILE"; echo "[FATAL] rc=$rc line=${BASH_LINENO[0]} cmd=${BASH_COMMAND}" >>"$ERR_FILE"; echo "----" >>"$ERR_FILE"; exit $rc' ERR

echo "[INFO] Logs: $LOG_FILE"
echo "[INFO] Errs: $ERR_FILE"

START_TIME=$(date +%s)

ARCH="${ARCH:-arm64}"
TARGET_CODENAME="${TARGET_CODENAME:-trixie}"
IMG_SIZE="${IMG_SIZE:-16G}"
BASE_IMG="${BASE_IMG:-rpi-base-$(date +%Y%m%d).img}"

ARTIFACTS_DIR="${ARTIFACTS_DIR:-}"
[[ -n "$ARTIFACTS_DIR" && -d "$ARTIFACTS_DIR" ]] || { echo "[ERROR] Set ARTIFACTS_DIR to artifacts-arm64 dir" >&2; exit 1; }

GOPROXY_IMG="${GOPROXY_IMG:-https://goproxy.cn,https://proxy.golang.org,direct}"
GOSUMDB_IMG="${GOSUMDB_IMG:-off}"

HOST_PWD="$(pwd)"
HUB_SRC="${SCRIPT_DIR}/hub"

err(){ echo "[ERROR] $*" >&2; exit 1; }
info(){ echo -e "\e[1;34m[INFO]\e[0m $*"; }
need(){ command -v "$1" >/dev/null 2>&1; }

curl_retry(){ curl --http1.1 -fL --retry 8 --retry-all-errors --connect-timeout 20 --max-time 0 "$@"; }

# Функция для определения URL образа Raspberry Pi OS trixie
resolve_trixie_lite_url() {
  local arch="$1"
  # Для trixie используем raspios_lite (не oldstable)
  local candidates=(
    "https://downloads.raspberrypi.com/raspios_lite_${arch}_latest"
    "https://downloads.raspberrypi.org/raspios_lite_${arch}_latest"
  )
  for u in "${candidates[@]}"; do
    local eff=""
    eff="$(curl -Ls -o /dev/null -w '%{url_effective}' "$u" 2>/dev/null || true)"
    if [[ "$eff" =~ \.img\.xz$ ]]; then
      echo "$eff"; return 0
    fi
  done

  info "Redirect URL not found. Scraping: https://www.raspberrypi.com/software/operating-systems/"
  local html
  html="$(curl_retry "https://www.raspberrypi.com/software/operating-systems/" 2>/dev/null)" || return 1
  # Ищем ссылку на lite образ
  local re="https://downloads\\.raspberrypi\\.(com|org)/raspios_lite_${arch}/images/[^\"' ]+\\.img\\.xz"
  local url
  url="$(printf '%s' "$html" | grep -oE "$re" | head -n1 || true)"
  [[ -n "$url" ]] || return 1
  echo "$url"
}

# host deps
HOST_DEPS=(xz curl qemu-img parted losetup rsync qemu-aarch64-static jq openssl e2fsck resize2fs mountpoint tar)
MISS=(); for b in "${HOST_DEPS[@]}"; do need "$b" || MISS+=("$b"); done
if ((${#MISS[@]})); then
  info "Installing host deps: ${MISS[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y -qq xz-utils curl qemu-utils parted qemu-user-static rsync jq openssl e2fsprogs util-linux tar
fi

WORK="$(mktemp -d)"
cleanup() {
  set +e
  if mountpoint -q "$WORK/root/dev/pts"; then sudo umount -l "$WORK/root/dev/pts"; fi
  for fs in proc sys dev; do
    if mountpoint -q "$WORK/root/$fs"; then sudo umount -lR "$WORK/root/$fs"; fi
  done
  if mountpoint -q "$WORK/root/boot/firmware"; then sudo umount -l "$WORK/root/boot/firmware"; fi
  if mountpoint -q "$WORK/boot"; then sudo umount -l "$WORK/boot"; fi
  if mountpoint -q "$WORK/root"; then sudo umount -l "$WORK/root"; fi
  if [[ -n "${LOOP:-}" ]]; then sudo losetup -d "$LOOP" 2>/dev/null || true; fi
  rm -rf "$WORK"
  cd "$HOST_PWD" || true
}
trap cleanup EXIT

# --- 1) Download / reuse image ---
info "Resolving Raspberry Pi OS Lite (${TARGET_CODENAME}) URL…"
IMG_URL="$(resolve_trixie_lite_url "$ARCH")" || err "Could not resolve image URL"
FNAME="$(basename "$IMG_URL")"

if [[ -f "$FNAME" ]]; then
  info "Using local: $FNAME"
else
  # если у тебя уже есть похожий файл — можно использовать его
  LOCAL="$(find . -maxdepth 1 -type f -name "*raspios*${ARCH}*.img.xz" -print -quit 2>/dev/null || true)"
  if [[ -n "$LOCAL" ]]; then
    info "Found local image: $LOCAL"
    FNAME="${LOCAL#./}"
  else
    info "Downloading $FNAME…"
    curl_retry "$IMG_URL" -o "$FNAME"
  fi
fi

info "Decompressing…"
xz -T0 -dkf "$FNAME"
SRC_IMG="${FNAME%.xz}"
[[ -f "$SRC_IMG" ]] || err "Missing decompressed image"

# --- 2) Resize ---
cp "$SRC_IMG" "$BASE_IMG"
info "Resizing to $IMG_SIZE…"
qemu-img resize "$BASE_IMG" "$IMG_SIZE" >/dev/null
parted -s "$BASE_IMG" unit % resizepart 2 100% >/dev/null

LOOP_TMP="$(sudo losetup -f --show -P "$BASE_IMG")"
sudo e2fsck -f -y "${LOOP_TMP}p2" >/dev/null
sudo resize2fs "${LOOP_TMP}p2" >/dev/null
sudo losetup -d "$LOOP_TMP"

# --- 3) Mount ---
info "Mounting image…"
LOOP="$(sudo losetup -f --show -P "$BASE_IMG")"
sudo mkdir -p "$WORK/root" "$WORK/boot"
sudo mount "${LOOP}p2" "$WORK/root"
sudo mount "${LOOP}p1" "$WORK/boot"
sudo mkdir -p "$WORK/root/boot/firmware"
sudo mount --bind "$WORK/boot" "$WORK/root/boot/firmware"

# Проверка версии ОС
if ! grep -qE "^VERSION_CODENAME=${TARGET_CODENAME}\$" "$WORK/root/etc/os-release"; then
  warn "Downloaded image is not ${TARGET_CODENAME}, checking actual version…"
  cat "$WORK/root/etc/os-release"
  # Продолжаем если это trixie или testing
  if ! grep -qE "^VERSION_CODENAME=(trixie|testing)\$" "$WORK/root/etc/os-release"; then
    err "Downloaded image is not trixie/testing"
  fi
fi

sudo cp /etc/resolv.conf "$WORK/root/etc/resolv.conf"
sudo install -m0755 /usr/bin/qemu-aarch64-static "$WORK/root/usr/bin/qemu-aarch64-static"
for fs in proc sys dev; do sudo mount --bind "/$fs" "$WORK/root/$fs"; done
sudo mount -t devpts devpts "$WORK/root/dev/pts" 2>/dev/null || true

# --- 3a) Copy hub into image ---
if [[ -d "$HUB_SRC" && -f "$HUB_SRC/app.py" ]]; then
  info "Copy hub → /opt/hub (exclude .git)…"
  sudo mkdir -p "$WORK/root/opt/hub"
  sudo rsync -a --delete --exclude '.git' "$HUB_SRC"/ "$WORK/root/opt/hub/"
else
  info "No hub sources at $HUB_SRC (skip hub copy)."
fi

# --- 3b) Copy artifacts into image ---
info "Copying artifacts into image…"
sudo install -d -m0755 "$WORK/root/opt/artifacts"

GO_TGZ="$(ls -1 "$ARTIFACTS_DIR"/go-*.linux-arm64.tar.gz 2>/dev/null | head -n1 || true)"
[[ -n "$GO_TGZ" ]] || err "No go-*.linux-arm64.tar.gz in ARTIFACTS_DIR"
sudo cp -f "$GO_TGZ" "$WORK/root/opt/artifacts/"

for m in "$ARTIFACTS_DIR"/NEEDS_IN_IMAGE_*; do
  [[ -f "$m" ]] && sudo cp -f "$m" "$WORK/root/opt/artifacts/" || true
done

# go module cache (optional)
if [[ -d "$ARTIFACTS_DIR/cache/gomod" ]]; then
  sudo mkdir -p "$WORK/root/opt/artifacts/cache"
  sudo rsync -a --delete "$ARTIFACTS_DIR/cache/gomod/" "$WORK/root/opt/artifacts/cache/gomod/"
fi

# keep copy of prebuilt go bins for final restore
if [[ -d "$ARTIFACTS_DIR/bin" ]]; then
  sudo mkdir -p "$WORK/root/opt/artifacts/bin"
  sudo rsync -a --delete "$ARTIFACTS_DIR/bin/" "$WORK/root/opt/artifacts/bin/"
fi

# tailscale into /usr/sbin
sudo install -d -m0755 "$WORK/root/usr/sbin" "$WORK/root/etc/systemd/system" "$WORK/root/etc/default"
sudo install -m0755 "$ARTIFACTS_DIR/bin/tailscale"  "$WORK/root/usr/sbin/tailscale"
sudo install -m0755 "$ARTIFACTS_DIR/bin/tailscaled" "$WORK/root/usr/sbin/tailscaled"
sudo install -m0644 "$ARTIFACTS_DIR/systemd/tailscaled.service" "$WORK/root/etc/systemd/system/tailscaled.service"
echo -e 'PORT="0"\nFLAGS=""' | sudo tee "$WORK/root/etc/default/tailscaled" >/dev/null

# other prebuilt go bins into /usr/local/bin
sudo install -d -m0755 "$WORK/root/usr/local/bin"
if [[ -d "$ARTIFACTS_DIR/bin" ]]; then
  for f in "$ARTIFACTS_DIR/bin/"*; do
    bn="$(basename "$f")"
    [[ "$bn" == "tailscale" || "$bn" == "tailscaled" ]] && continue
    sudo install -m0755 "$f" "$WORK/root/usr/local/bin/$bn"
  done
fi

# sources/templates
sudo install -d -m0755 "$WORK/root/opt" "$WORK/root/usr/share"
[[ -d "$ARTIFACTS_DIR/src/Responder" ]]        && sudo rsync -a --delete "$ARTIFACTS_DIR/src/Responder/"        "$WORK/root/opt/Responder/"
[[ -d "$ARTIFACTS_DIR/src/dirsearch" ]]        && sudo rsync -a --delete "$ARTIFACTS_DIR/src/dirsearch/"        "$WORK/root/opt/dirsearch/"
[[ -d "$ARTIFACTS_DIR/src/sqlmap" ]]           && sudo rsync -a --delete "$ARTIFACTS_DIR/src/sqlmap/"           "$WORK/root/opt/sqlmap/"
[[ -d "$ARTIFACTS_DIR/src/SecLists" ]]         && sudo rsync -a --delete "$ARTIFACTS_DIR/src/SecLists/"         "$WORK/root/usr/share/seclists/"
[[ -d "$ARTIFACTS_DIR/src/nuclei-templates" ]] && sudo rsync -a --delete "$ARTIFACTS_DIR/src/nuclei-templates/" "$WORK/root/opt/nuclei-templates/"


# --- 4) Chroot install/config ---
info "Entering chroot…"
sudo --preserve-env=GOPROXY_IMG,GOSUMDB_IMG chroot "$WORK/root" /bin/bash -euxo pipefail -c "$(cat <<'EOS'
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

log(){ echo -e "\e[32m[CHROOT]\e[0m $*"; }

GOPROXY_IMG="${GOPROXY_IMG:-https://goproxy.cn,https://proxy.golang.org,direct}"
GOSUMDB_IMG="${GOSUMDB_IMG:-off}"

# apt retries и параллельная загрузка
cat >/etc/apt/apt.conf.d/80retries <<'APT'
Acquire::Retries "8";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::Queue-Mode "access";
APT

# prevent service start in chroot
cat >/usr/sbin/policy-rc.d <<'PRC'
#!/bin/sh
exit 101
PRC
chmod +x /usr/sbin/policy-rc.d

enable_unit() {
  local unit="$1" target="${2:-multi-user.target}"
  mkdir -p "/etc/systemd/system/${target}.wants"
  local src=""
  if [[ -f "/etc/systemd/system/${unit}" ]]; then
    src="/etc/systemd/system/${unit}"
  elif [[ -f "/lib/systemd/system/${unit}" ]]; then
    src="/lib/systemd/system/${unit}"
  else
    echo "[WARN] Unit not found: ${unit}" >&2
    return 0
  fi
  ln -sf "${src}" "/etc/systemd/system/${target}.wants/${unit}"
}

curl_retry(){ curl --http1.1 -fL --retry 8 --retry-all-errors --connect-timeout 20 --max-time 0 "$@"; }

# debconf seeds (avoid prompts)
echo "krb5-config krb5-config/default_realm string EXAMPLE.LOCAL" | debconf-set-selections || true
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections || true
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections || true

# pip robustness
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_DEFAULT_TIMEOUT=600
PIP_RETRIES=25
export PIP_INDEX_URL="https://www.piwheels.org/simple"
export PIP_EXTRA_INDEX_URL="https://pypi.org/simple"

pip_retry() {
  local desc="$1"; shift
  local i
  for i in 1 2 3; do
    log "pip install (${desc}) attempt ${i}/3"
    if python3 -m pip install --no-cache-dir --break-system-packages --ignore-installed \
        --retries "${PIP_RETRIES}" --timeout "${PIP_DEFAULT_TIMEOUT}" "$@"; then
      return 0
    fi
    log "pip install (${desc}) failed; retry in 15s"
    sleep 15
  done
  return 1
}

pipx_install_retry() {
  local pkg="$1"
  local i
  for i in 1 2 3; do
    log "pipx install ${pkg} attempt ${i}/3"
    if pipx install --pip-args="--retries ${PIP_RETRIES} --timeout ${PIP_DEFAULT_TIMEOUT}" "$pkg"; then
      return 0
    fi
    log "pipx install ${pkg} failed; retry in 15s"
    sleep 15
  done
  f="$(ls -t /opt/pipx/logs/*pip_errors.log 2>/dev/null | head -n1 || true)"
  [[ -n "$f" ]] && { echo "---- tail $f ----" >&2; tail -n 200 "$f" >&2 || true; echo "----" >&2; }
  return 1
}

log "APT update/upgrade + packages"
apt-get update
apt-get -y -o DPkg::Options::='--force-confdef' -o DPkg::Options::='--force-confold' upgrade

# IMPORTANT:
# - python3-dev for mitm6/netifaces
# - wireless-tools provides iwlist (hub needs it)
# - fastfetch вместо neofetch (удалён в trixie)
apt-get -y --no-install-recommends install \
  ca-certificates curl wget git gnupg gnupg2 \
  build-essential cmake pkg-config \
  libjson-c-dev libwebsockets-dev libuv1-dev \
  network-manager gpiod rfkill wireless-tools \
  sudo iptables iptables-persistent \
  python3 python3-dev python3-pip python3-venv python3-wheel pipx \
  locales less dialog texinfo openssh-server jq bash-completion \
  postgresql postgresql-contrib \
  nmap tcpdump masscan hydra macchanger nikto \
  bind9-dnsutils vim ldap-utils krb5-user krb5-config \
  libpcap-dev libusb-1.0-0-dev libnetfilter-queue-dev \
  libffi-dev libssl-dev libpq-dev zlib1g-dev libldap2-dev libsasl2-dev libkrb5-dev \
  libcap2-bin \
  isc-dhcp-client

# fastfetch вместо neofetch (neofetch удалён в Debian 13)
apt-get -y --no-install-recommends install fastfetch || apt-get -y --no-install-recommends install neofetch || true

log "Locales"
sed -Ei 's/^# ?(en_US\.UTF-8 UTF-8)/\1/' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
sed -Ei 's/^# ?(en_GB\.UTF-8 UTF-8)/\1/' /etc/locale.gen || echo 'en_GB.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8

log "User kali + sudo NOPASSWD"
id -u kali >/dev/null 2>&1 || useradd -m -s /bin/bash kali
echo 'kali:YOUR_PASSWORD' | chpasswd
usermod -aG sudo,adm,dialout,cdrom,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi kali
printf '%sudo ALL=(ALL:ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/010-sudo-nopasswd
chmod 440 /etc/sudoers.d/010-sudo-nopasswd

log "Install Go from /opt/artifacts"
GO_TGZ="$(ls -1 /opt/artifacts/go-*.linux-arm64.tar.gz | head -n1)"
test -f "$GO_TGZ"
rm -rf /usr/local/go
mkdir -p /usr/local
tar -C /usr/local -xzf "$GO_TGZ"
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt 2>/dev/null || true
cat >/etc/profile.d/go.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin
EOF
chmod 644 /etc/profile.d/go.sh

# Go env (inside image)
export PATH="/usr/local/go/bin:/usr/local/bin:/usr/sbin:/usr/bin:$PATH"
export GOPROXY="$GOPROXY_IMG"
export GOSUMDB="$GOSUMDB_IMG"
export GODEBUG="http2client=0"
export GIT_TERMINAL_PROMPT=0
export GOBIN="/usr/local/bin"
export GOCACHE="/tmp/go-build"
mkdir -p "$GOCACHE"
if [ -d /opt/artifacts/cache/gomod ]; then export GOMODCACHE="/opt/artifacts/cache/gomod"; fi

go_install_retry() {
  local desc="$1"; shift
  local i
  for i in 1 2 3; do
    log "go install (${desc}) attempt ${i}/3: $*"
    if timeout 45m go install -v "$@"; then return 0; fi
    sleep 5
  done
  return 1
}

# pipx canonical env + wrapper (so `pipx list` works under root/ssh)
export PIPX_HOME=/opt/pipx
export PIPX_BIN_DIR=/usr/local/bin
mkdir -p "$PIPX_HOME"
pipx ensurepath || true
cat >/etc/profile.d/pipx.sh <<'PX'
export PIPX_HOME=/opt/pipx
export PIPX_BIN_DIR=/usr/local/bin
PX
chmod 644 /etc/profile.d/pipx.sh
cat >/usr/local/bin/pipx <<'WRP'
#!/usr/bin/env bash
export PIPX_HOME=/opt/pipx
export PIPX_BIN_DIR=/usr/local/bin
exec /usr/bin/pipx "$@"
WRP
chmod 755 /usr/local/bin/pipx

# Responder/dirsearch/sqlmap symlinks
ln -sf /opt/Responder/Responder.py /usr/local/bin/responder || true
ln -sf /opt/dirsearch/dirsearch.py /usr/local/bin/dirsearch || true
ln -sf /opt/sqlmap/sqlmap.py /usr/local/bin/sqlmap || true
chmod +x /opt/Responder/Responder.py /opt/dirsearch/dirsearch.py /opt/sqlmap/sqlmap.py 2>/dev/null || true

# Optional: requirements for git tools
[ -f /opt/Responder/requirements.txt ] && pip_retry "Responder requirements" -r /opt/Responder/requirements.txt
[ -f /opt/dirsearch/requirements.txt ] && pip_retry "dirsearch requirements" -r /opt/dirsearch/requirements.txt

# nuclei templates env
cat >/etc/profile.d/nuclei.sh <<'NUC'
export NUCLEI_TEMPLATES=/opt/nuclei-templates
NUC
chmod 644 /etc/profile.d/nuclei.sh

# enable base services
log "Enable core units"
enable_unit tailscaled.service multi-user.target
enable_unit NetworkManager.service multi-user.target
enable_unit ssh.service multi-user.target

# Build CGO-required Go tools by markers
log "Build CGO-required Go tools (if needed)…"
[ -f /opt/artifacts/NEEDS_IN_IMAGE_NAABU ]     && { log "Build naabu (CGO=1)";     CGO_ENABLED=1 go_install_retry naabu github.com/projectdiscovery/naabu/v2/cmd/naabu@latest; }
[ -f /opt/artifacts/NEEDS_IN_IMAGE_BETTERCAP ] && { log "Build bettercap (CGO=1)"; CGO_ENABLED=1 go_install_retry bettercap github.com/bettercap/bettercap@latest; }
[ -f /opt/artifacts/NEEDS_IN_IMAGE_KATANA ]    && { log "Build katana (CGO=1)";    CGO_ENABLED=1 go_install_retry katana github.com/projectdiscovery/katana/cmd/katana@latest; }

# ligolo fallback
if [ ! -x /usr/local/bin/ligolo-agent ] || [ ! -x /usr/local/bin/ligolo-proxy ] || [ -f /opt/artifacts/NEEDS_IN_IMAGE_LIGOLO ]; then
  log "Build ligolo inside image"
  go_install_retry ligolo-agent github.com/nicocha30/ligolo-ng/cmd/agent@latest
  go_install_retry ligolo-proxy github.com/nicocha30/ligolo-ng/cmd/proxy@latest
  if command -v agent >/dev/null 2>&1; then install -m0755 "$(command -v agent)" /usr/local/bin/ligolo-agent; fi
  if command -v proxy >/dev/null 2>&1; then install -m0755 "$(command -v proxy)" /usr/local/bin/ligolo-proxy; fi
fi

# ttyd build
log "Build ttyd"
rm -rf /usr/local/src/ttyd
git clone --depth 1 https://github.com/tsl0922/ttyd.git /usr/local/src/ttyd
cd /usr/local/src/ttyd
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j"$(nproc)"
make install
cat >/etc/systemd/system/ttyd.service <<'UNIT'
[Unit]
Description=ttyd – share your terminal over the web
After=network.target
[Service]
User=kali
ExecStart=/usr/local/bin/ttyd -p 7681 -W /bin/bash -l
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
enable_unit ttyd.service multi-user.target

# ponysay
log "ponysay"
rm -rf /tmp/ponysay
git clone --depth 1 https://github.com/erkin/ponysay.git /tmp/ponysay
pushd /tmp/ponysay
python3 ./setup.py --freedom=partial install
popd
rm -rf /tmp/ponysay

# pipx tools
log "pipx tools"
pipx_install_retry impacket
pipx_install_retry mitmproxy
pipx_install_retry mitm6
pipx_install_retry certipy-ad

# Rust + uv + NetExec
log "Rustup + uv + NetExec"
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
curl_retry https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
export PATH="/opt/cargo/bin:$PATH"
rustc --version
cargo --version
ln -sf /opt/cargo/bin/rustc /usr/local/bin/rustc
ln -sf /opt/cargo/bin/cargo /usr/local/bin/cargo
ln -sf /opt/cargo/bin/rustup /usr/local/bin/rustup
cat >/etc/profile.d/rust.sh <<'RS'
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
export PATH=/opt/cargo/bin:$PATH
RS
chmod 644 /etc/profile.d/rust.sh

curl_retry https://astral.sh/uv/install.sh | sh
if [ -x /root/.local/bin/uv ]; then install -m0755 /root/.local/bin/uv /usr/local/bin/uv; fi

command -v rustc >/dev/null 2>&1
uv tool install --force "git+https://github.com/Pennyw0rth/NetExec"
install -m0755 /root/.local/bin/{NetExec,netexec,nxc,nxcdb} /usr/local/bin/ 2>/dev/null || true

# caps
setcap 'cap_net_raw+ep' /usr/bin/masscan 2>/dev/null || true
setcap 'cap_net_raw+ep' /usr/bin/tcpdump 2>/dev/null || true
[ -x /usr/local/bin/ligolo-agent ] && setcap 'cap_net_admin,cap_net_raw+ep' /usr/local/bin/ligolo-agent 2>/dev/null || true
[ -x /usr/local/bin/ligolo-proxy ] && setcap 'cap_net_admin,cap_net_raw+ep' /usr/local/bin/ligolo-proxy 2>/dev/null || true
[ -x /usr/local/bin/bettercap ] && setcap 'cap_net_admin,cap_net_raw+ep' /usr/local/bin/bettercap 2>/dev/null || true

# Zabbix 7.0 (используем bookworm repo, т.к. trixie repo не существует для arm64)
log "Zabbix agent2"
install -d -m0755 /etc/apt/keyrings
curl_retry https://repo.zabbix.com/zabbix-official-repo.key | gpg --dearmor -o /etc/apt/keyrings/zabbix.gpg
# NOTE: Zabbix не имеет официального repo для trixie arm64, используем bookworm (бинарная совместимость)
cat >/etc/apt/sources.list.d/zabbix.list <<'SRC'
# Zabbix 7.0 для debian-arm64 bookworm (работает на trixie благодаря бинарной совместимости)
deb [arch=arm64 signed-by=/etc/apt/keyrings/zabbix.gpg] https://repo.zabbix.com/zabbix/7.0/debian-arm64 bookworm main
SRC
apt-get update
apt-get -y install zabbix-agent2
enable_unit zabbix-agent2.service multi-user.target

# Metasploit (official installer)
log "Metasploit"
# Очистка apt cache перед установкой большого пакета
apt-get clean
curl_retry https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb -o /tmp/msfinstall
chmod 755 /tmp/msfinstall
DEBIAN_FRONTEND=noninteractive /tmp/msfinstall
enable_unit postgresql.service multi-user.target

# kubectl v1.30 (скачиваем бинарник напрямую, т.к. Kubernetes repo использует
# устаревшую подпись v3, которую sqv в trixie отклоняет с 2026-02-01)
log "kubectl v1.30"
KUBECTL_VERSION="v1.30.8"
curl_retry "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl
kubectl version --client || true


# -------------------- HUB AUTOSTART --------------------
log "Hub setup (venv + systemd)"
if [ -d /opt/hub ] && [ -f /opt/hub/app.py ]; then
  # Venv
  python3 -m venv /opt/hub/venv

  # install requirements into venv with retries
  hub_pip="/opt/hub/venv/bin/pip"
  hub_py="/opt/hub/venv/bin/python"
  "$hub_pip" install --no-cache-dir --upgrade pip setuptools wheel --retries "${PIP_RETRIES}" --timeout "${PIP_DEFAULT_TIMEOUT}" || true
  if [ -f /opt/hub/requirements.txt ]; then
    i=1
    while true; do
      log "hub requirements install attempt ${i}/3"
      # venv изолирован от системы, --ignore-installed НЕ нужен здесь
      if "$hub_pip" install --no-cache-dir --retries "${PIP_RETRIES}" --timeout "${PIP_DEFAULT_TIMEOUT}" -r /opt/hub/requirements.txt; then
        break
      fi
      if [ "$i" -ge 3 ]; then
        echo "[ERROR] hub requirements failed after 3 attempts" >&2
        exit 1
      fi
      i=$((i+1))
      sleep 15
    done
  fi

  # Верификация что Flask установлен
  if ! "$hub_py" -c "import flask" 2>/dev/null; then
    log "Flask not found, force reinstall..."
    "$hub_pip" install --no-cache-dir --force-reinstall flask requests || exit 1
  fi

  # ownership
  chown -R kali:kali /opt/hub || true

  # systemd unit: start as soon as possible after NM + tailscaled
  cat >/etc/systemd/system/hub.service <<'UNIT'
[Unit]
Description=Hub web UI (Flask)
After=network.target NetworkManager.service tailscaled.service
Wants=NetworkManager.service tailscaled.service

[Service]
Type=simple
User=kali
Group=kali
WorkingDirectory=/opt/hub
Environment=PYTHONUNBUFFERED=1
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PermissionsStartOnly=true
ExecStartPre=/usr/sbin/rfkill unblock wifi
ExecStartPre=/usr/bin/nmcli radio wifi on
ExecStartPre=/usr/sbin/ip link set wlan0 up
ExecStart=/opt/hub/venv/bin/python /opt/hub/app.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

  enable_unit hub.service multi-user.target
else
  log "Hub not present in /opt/hub -> skipping hub.service"
fi
# -------------------------------------------------------

# Restore prebuilt Go binaries to prevent collisions (python httpx etc.)
log "Restore prebuilt /opt/artifacts/bin/* → /usr/local/bin"
if [ -d /opt/artifacts/bin ]; then
  for f in /opt/artifacts/bin/*; do
    bn="$(basename "$f")"
    [[ "$bn" == "tailscale" || "$bn" == "tailscaled" ]] && continue
    install -m0755 "$f" "/usr/local/bin/$bn" || true
  done
fi

# Final symlinks (so go/rust always found)
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /opt/cargo/bin/rustc /usr/local/bin/rustc 2>/dev/null || true
ln -sf /opt/cargo/bin/cargo /usr/local/bin/cargo 2>/dev/null || true

# ---- FINAL MUST CHECK ----
log "Final verification (MUST)…"
must_bins=(
  python3 pip pipx
  go rustc cargo uv
  tailscale tailscaled ttyd zabbix_agent2
  psql vim ponysay
  nmap masscan naabu dig nslookup tcpdump bettercap macchanger
  mitmproxy mitm6 certipy nxc
  hydra msfconsole
  sqlmap responder dirsearch
  nuclei httpx katana ffuf dalfox
  kubectl
  ligolo-agent ligolo-proxy
  ldapsearch kinit klist
)
for b in "${must_bins[@]}"; do
  command -v "$b" >/dev/null 2>&1 || { echo "[ERROR] missing binary: $b" >&2; exit 1; }
done

for d in /usr/share/seclists /opt/Responder /opt/dirsearch /opt/sqlmap /opt/nuclei-templates; do
  [ -d "$d" ] || { echo "[ERROR] missing dir: $d" >&2; exit 1; }
done

# cleanup artifacts to reduce size
rm -rf /opt/artifacts/cache/gomod 2>/dev/null || true
rm -rf /opt/artifacts/bin 2>/dev/null || true
rm -f /opt/artifacts/go-*.linux-arm64.tar.gz 2>/dev/null || true
rm -f /opt/artifacts/NEEDS_IN_IMAGE_* 2>/dev/null || true
rm -f /usr/sbin/policy-rc.d 2>/dev/null || true

apt-get clean
log "Base image customisation finished"
EOS
)"

# NOTE: Hackberry display config removed - use standard HDMI by default
# For Hackberry with HyperPixel4 Square display, add manually to /boot/firmware/config.txt:
#   max_framebuffers=2
#   dtoverlay=vc4-kms-dpi-hyperpixel4sq

# userconf
info "Writing userconf.txt (kali:YOUR_PASSWORD)…"
PASSHASH="$(openssl passwd -6 YOUR_PASSWORD)"
echo "kali:$PASSHASH" | sudo tee "$WORK/boot/userconf.txt" >/dev/null
sudo touch "$WORK/boot/ssh" || true

# finalize
info "Finalising base image…"
sudo umount -l "$WORK/root/dev/pts" 2>/dev/null || true
for fs in proc sys dev; do sudo umount -lR "$WORK/root/$fs" 2>/dev/null || true; done
sudo umount -l "$WORK/root/boot/firmware" 2>/dev/null || true
sudo umount -l "$WORK/boot" "$WORK/root"
sudo losetup -d "$LOOP"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

info "✓ Base image ready: $BASE_IMG (size: $IMG_SIZE)"
echo "[INFO] Elapsed time: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
echo "[INFO] If something fails later, send: $ERR_FILE"
echo "Next: sudo bash 02-personalize-pi-image-trixie.sh $BASE_IMG"
