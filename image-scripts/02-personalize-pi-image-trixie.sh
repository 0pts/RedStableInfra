#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 02-personalize-pi-image-trixie.sh
# Только персонализация: hostname/pony + zabbix config + tailscale-firstboot key.
# Требует env:
#   HEADSCALE_SERVER, HEADSCALE_USER, HEADSCALE_PASSWORD
# -----------------------------------------------------------------------------

set -euo pipefail
[[ ${DEBUG:-0} -eq 1 ]] && set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/02-personalize.${RUN_ID}.log"
ERR_FILE="$LOG_DIR/02-personalize.${RUN_ID}.err"
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$ERR_FILE" >&2)
trap 'rc=$?; echo "----" >>"$ERR_FILE"; echo "[FATAL] rc=$rc line=${BASH_LINENO[0]} cmd=${BASH_COMMAND}" >>"$ERR_FILE"; echo "----" >>"$ERR_FILE"; exit $rc' ERR

echo "[INFO] Logs: $LOG_FILE"
echo "[INFO] Errs: $ERR_FILE"

START_TIME=$(date +%s)

BASE_IMG="${1:-}"
[[ -n "$BASE_IMG" && -f "$BASE_IMG" ]] || { echo "Usage: sudo $0 <base.img>" >&2; exit 1; }

ZBX_SERVER_IP="${ZBX_SERVER_IP:-YOUR_TAILSCALE_IP}"
ZBX_SERVER_PORT="${ZBX_SERVER_PORT:-10051}"
ZBX_ENABLE_PSK="${ZBX_ENABLE_PSK:-no}"

HEADSCALE_SERVER="${HEADSCALE_SERVER:-}"
HEADSCALE_USER="${HEADSCALE_USER:-}"
HEADSCALE_PASSWORD="${HEADSCALE_PASSWORD:-}"
HEADSCALE_CMD_JSON="${HEADSCALE_CMD_JSON:-headscale preauthkeys create --user 1 --expiration 3h -o json}"
HEADSCALE_CMD_TEXT="${HEADSCALE_CMD_TEXT:-headscale preauthkeys create --user 1 --expiration 3h}"

[[ -n "$HEADSCALE_SERVER" && -n "$HEADSCALE_USER" && -n "$HEADSCALE_PASSWORD" ]] || {
  echo "[ERROR] Set HEADSCALE_SERVER/HEADSCALE_USER/HEADSCALE_PASSWORD env vars" >&2; exit 1;
}

need(){ command -v "$1" >/dev/null 2>&1; }
info(){ echo -e "\e[1;34m[INFO]\e[0m $*"; }

HOST_DEPS=(curl losetup qemu-aarch64-static jq openssl sshpass find shuf mountpoint)
MISS=(); for b in "${HOST_DEPS[@]}"; do need "$b" || MISS+=("$b"); done
if ((${#MISS[@]})); then
  info "Installing host deps: ${MISS[*]} …"
  sudo apt-get update -qq
  sudo apt-get install -y -qq curl qemu-user-static jq openssl sshpass findutils coreutils util-linux
fi

info "Requesting headscale preauth key…"
RAW=$(
  sshpass -p "$HEADSCALE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$HEADSCALE_USER@$HEADSCALE_SERVER" "$HEADSCALE_CMD_JSON" 2>/dev/null \
  || sshpass -p "$HEADSCALE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$HEADSCALE_USER@$HEADSCALE_SERVER" "$HEADSCALE_CMD_TEXT"
) || true

HEADSCALE_KEY="$(printf '%s' "$RAW" | jq -r '.key // .Key // empty' 2>/dev/null || true)"
[[ -z "$HEADSCALE_KEY" ]] && HEADSCALE_KEY="$(printf '%s' "$RAW" | grep -oE 'tskey-[A-Za-z0-9_-]+' | head -n1 || true)"
[[ -n "$HEADSCALE_KEY" ]] || { echo "[ERROR] Failed to obtain headscale key" >&2; exit 1; }
export HEADSCALE_KEY

HOST_PWD="$(pwd)"
WORK="$(mktemp -d)"
TMP_IMG="personalize.$(date +%s).$.img"
READY_IMG=""

cleanup(){
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

info "Copy base image → temp"
cp --reflink=auto "$BASE_IMG" "$TMP_IMG"

info "Mounting…"
LOOP="$(sudo losetup -f --show -P "$TMP_IMG")"
sudo mkdir -p "$WORK/root" "$WORK/boot"
sudo mount "${LOOP}p2" "$WORK/root"
sudo mount "${LOOP}p1" "$WORK/boot"
sudo mkdir -p "$WORK/root/boot/firmware"
sudo mount --bind "$WORK/boot" "$WORK/root/boot/firmware"

sudo cp /etc/resolv.conf "$WORK/root/etc/resolv.conf"
sudo install -m 0755 /usr/bin/qemu-aarch64-static "$WORK/root/usr/bin/qemu-aarch64-static"
for fs in proc sys dev; do sudo mount --bind "/$fs" "$WORK/root/$fs"; done
sudo mount -t devpts devpts "$WORK/root/dev/pts" 2>/dev/null || true

choose_pony(){ local dir="$1"
  find "$dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sed 's/\.[^.]*$//' | shuf -n1
}
PONY=""
for d in "$WORK/root/usr/share/ponysay/ponies" "$WORK/root/usr/local/share/ponysay/ponies"; do
  PONY="$(choose_pony "$d")"; [[ -n "$PONY" ]] && break
done
[[ -n "$PONY" ]] || PONY="twilight_sparkle"
READY_IMG="image.${PONY}.img"
info "PONY=$PONY → $READY_IMG"

info "Entering chroot (config only)…"
export PONY ZBX_SERVER_IP ZBX_SERVER_PORT ZBX_ENABLE_PSK
sudo --preserve-env=PONY,HEADSCALE_KEY,ZBX_SERVER_IP,ZBX_SERVER_PORT,ZBX_ENABLE_PSK \
  chroot "$WORK/root" /bin/bash -euxo pipefail -s <<'EOS'
export DEBIAN_FRONTEND=noninteractive
log(){ echo -e "\e[32m[CHROOT]\e[0m $*"; }

ZBX_SERVER_IP="${ZBX_SERVER_IP:-YOUR_TAILSCALE_IP}"
ZBX_SERVER_PORT="${ZBX_SERVER_PORT:-10051}"
ZBX_ENABLE_PSK="${ZBX_ENABLE_PSK:-no}"

enable_unit() {
  local unit="$1" target="${2:-multi-user.target}"
  mkdir -p "/etc/systemd/system/${target}.wants"
  local src=""
  if [[ -f "/etc/systemd/system/${unit}" ]]; then
    src="/etc/systemd/system/${unit}"
  elif [[ -f "/lib/systemd/system/${unit}" ]]; then
    src="/lib/systemd/system/${unit}"
  else
    return 0
  fi
  ln -sf "${src}" "/etc/systemd/system/${target}.wants/${unit}"
}
mask_unit(){ ln -sf /dev/null "/etc/systemd/system/$1" || true; }

log "Hostname"
echo "${PONY}" > /etc/hostname
HN="$(cat /etc/hostname)"
grep -qE '^127\.0\.0\.1\s+localhost' /etc/hosts || echo '127.0.0.1 localhost' >> /etc/hosts
sed -i -E '/^127\.0\.1\.1[[:space:]]+/d' /etc/hosts
echo "127.0.1.1 ${HN}" >> /etc/hosts

log "Zabbix config"
CONF="/etc/zabbix/zabbix_agent2.conf"
install -d -m 0755 /etc/zabbix
if [ ! -s "$CONF" ]; then
  cat >"$CONF" <<'EOF'
PidFile=/run/zabbix/zabbix_agent2.pid
LogType=file
LogFile=/var/log/zabbix/zabbix_agent2.log
Include=/etc/zabbix/zabbix_agent2.d/*.conf
EOF
fi
sed -i -E '/^(Hostname|Server|ServerActive|HostMetadata|TLS(Connect|Accept|PSKIdentity|PSKFile)|PidFile)=/d' "$CONF"
cat >>"$CONF" <<EOF
PidFile=/run/zabbix/zabbix_agent2.pid
Hostname=${HN}
Server=${ZBX_SERVER_IP}
ServerActive=${ZBX_SERVER_IP}:${ZBX_SERVER_PORT}
HostMetadata=${ZBX_HOST_METADATA:-autoreg-rpi}
EOF

if [ "${ZBX_ENABLE_PSK}" = "yes" ]; then
  PSK_FILE="/etc/zabbix/agent2.psk"
  [ -f "${PSK_FILE}" ] || { umask 077; openssl rand -hex 32 > "${PSK_FILE}"; }
  {
    echo 'TLSConnect=psk'
    echo 'TLSAccept=psk'
    echo "TLSPSKIdentity=agent-${HN}"
    echo "TLSPSKFile=${PSK_FILE}"
  } >> "$CONF"
fi
enable_unit zabbix-agent2.service multi-user.target

log "tailscale-firstboot"
LOGIN_SERVER="https://headscale.example.com"
KEY="${HEADSCALE_KEY:-}"

cat >/usr/local/sbin/tailscale-firstboot.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOGIN_SERVER="__LOGIN_SERVER__"
KEY="__KEY__"
HOSTNAME="$(cat /etc/hostname)"
DH_PID=/run/dhclient-eth0.pid

cleanup_eth0() {
  if [ -f "$DH_PID" ]; then kill "$(cat "$DH_PID")" 2>/dev/null || true; fi
  dhclient -r eth0 2>/dev/null || true
  ip addr flush dev eth0 2>/dev/null || true
  ip link set eth0 down 2>/dev/null || true
}

in_tailnet() {
  tailscale status --json 2>/dev/null | jq -e -r '.CurrentTailnet.Name? // ""' | grep -q .
}

try_up() {
  tailscale up --login-server "${LOGIN_SERVER}" --authkey "${KEY}" --hostname "${HOSTNAME}" \
    --advertise-tags=tag:hub --accept-dns=true --reset
}

trap 'cleanup_eth0' EXIT

if in_tailnet; then
  rm -f /usr/local/sbin/tailscale-firstboot.sh || true
  rm -f /etc/systemd/system/multi-user.target.wants/tailscale-firstboot.service || true
  exit 0
fi

if try_up; then
  rm -f /usr/local/sbin/tailscale-firstboot.sh || true
  rm -f /etc/systemd/system/multi-user.target.wants/tailscale-firstboot.service || true
  exit 0
fi

ip link set eth0 up 2>/dev/null || true
timeout 25 dhclient -1 -pf "$DH_PID" -lf /var/lib/dhcp/dhclient.eth0.leases eth0 2>/dev/null || true
try_up || true
exit 0
EOF
sed -i "s|__LOGIN_SERVER__|${LOGIN_SERVER}|g" /usr/local/sbin/tailscale-firstboot.sh
sed -i "s|__KEY__|${KEY}|g" /usr/local/sbin/tailscale-firstboot.sh
chmod +x /usr/local/sbin/tailscale-firstboot.sh

cat >/etc/systemd/system/tailscale-firstboot.service <<'UNIT'
[Unit]
Description=Run "tailscale up" once on first boot
After=network.target tailscaled.service
Wants=network.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tailscale-firstboot.sh
RemainAfterExit=no
[Install]
WantedBy=multi-user.target
UNIT
enable_unit tailscale-firstboot.service multi-user.target

mask_unit apt-daily.service
mask_unit apt-daily-upgrade.service
mask_unit apt-daily.timer
mask_unit apt-daily-upgrade.timer

# NetworkManager drop-in: игнорировать eth0
log "Configuring NetworkManager to ignore eth0 …"
install -d -m 0755 /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/10-eth0-unmanaged.conf <<'CNF'
# NM will ignore eth0 entirely; management is done by custom scripts.
[keyfile]
unmanaged-devices=interface-name:eth0
CNF
chmod 644 /etc/NetworkManager/conf.d/10-eth0-unmanaged.conf

# eth0-guard (только close, без авто-unlock)
log "Deploying eth0-guard (scripts + services, nm-independent) …"
install -d -m 0755 /etc/default
cat >/etc/default/eth0-guard <<'CONF'
GPIOCHIP=gpiochip0
GPIOLINE=17
ALLOW_LEVEL=0   # 0 = пин притянут к GND -> разрешить eth0 (используется только watch/ручной unlock)
CONF

cat >/usr/local/sbin/eth0-guard.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# Жёстко закрыть eth0 и убрать DHCP/адреса. НИЧЕГО не поднимаем!
DH_PID=/run/dhclient-eth0.pid
if [ -f "$DH_PID" ]; then kill "$(cat "$DH_PID")" 2>/dev/null || true; fi
dhclient -r eth0 2>/dev/null || true
ip addr flush dev eth0 2>/dev/null || true
ip link set eth0 down 2>/dev/null || true
SH
chmod +x /usr/local/sbin/eth0-guard.sh

cat >/usr/local/sbin/eth0-unlock.sh <<'UNL'
#!/usr/bin/env bash
set -euo pipefail
ip link set eth0 up 2>/dev/null || true
timeout 25 dhclient eth0
UNL
chmod +x /usr/local/sbin/eth0-unlock.sh

cat >/usr/local/sbin/eth0-guard-watch.sh <<'WAT'
#!/usr/bin/env bash
set -euo pipefail
[ -f /etc/default/eth0-guard ] && . /etc/default/eth0-guard || :
GPIOCHIP="${GPIOCHIP:-gpiochip0}"
GPIOLINE="${GPIOLINE:-17}"
ALLOW_LEVEL="${ALLOW_LEVEL:-0}"
while true; do
  # libgpiod v2 syntax (Debian 13 trixie)
  gpiomon -c "${GPIOCHIP}" -e falling -b pull-up -n 1 "${GPIOLINE}" >/dev/null 2>&1 || sleep 1
  VAL="$(gpioget -c "${GPIOCHIP}" --numeric "${GPIOLINE}" 2>/dev/null || echo 1)"
  if [ "${VAL}" = "${ALLOW_LEVEL}" ]; then
    /usr/local/sbin/eth0-unlock.sh || true
  fi
done
WAT
chmod +x /usr/local/sbin/eth0-guard-watch.sh

cat >/etc/systemd/system/eth0-guard.service <<'UNIT'
[Unit]
Description=Disable eth0 at boot unless overridden (no-NM)
DefaultDependencies=no
# Срабатываем до любой сети:
Before=network-pre.target network.target NetworkManager.service systemd-networkd.service
After=local-fs.target systemd-udevd.service
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/eth0-guard.sh
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
UNIT

cat >/etc/systemd/system/eth0-guard-watch.service <<'UNIT'
[Unit]
Description=Watch GPIO and enable eth0 when pin is shorted (no-NM)
After=multi-user.target
PartOf=eth0-guard.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/eth0-guard-watch.sh
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
UNIT

enable_unit eth0-guard.service sysinit.target
enable_unit eth0-guard-watch.service multi-user.target

log "Personalization finished"
EOS

info "Writing userconf.txt (kali:YOUR_PASSWORD)…"
PASSHASH="$(openssl passwd -6 YOUR_PASSWORD)"
echo "kali:$PASSHASH" | sudo tee "$WORK/boot/userconf.txt" >/dev/null
sudo touch "$WORK/boot/ssh" || true

info "Finalising…"
sudo umount -l "$WORK/root/dev/pts" 2>/dev/null || true
for fs in proc sys dev; do sudo umount -lR "$WORK/root/$fs" 2>/dev/null || true; done
sudo umount -l "$WORK/root/boot/firmware" 2>/dev/null || true
sudo umount -l "$WORK/boot" "$WORK/root"
sudo losetup -d "$LOOP"

mv -f "$TMP_IMG" "$READY_IMG"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

info "✓ Personalized image ready: $READY_IMG"
echo "[INFO] Elapsed time: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
echo "[INFO] If something fails, send: $ERR_FILE"
