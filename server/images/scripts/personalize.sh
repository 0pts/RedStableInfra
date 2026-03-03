#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# personalize.sh
# Серверная версия персонализации образа.
# Вызывается из Flask приложения.
#
# Аргументы:
#   $1 - путь к базовому образу
#   $2 - путь к output директории
#
# Environment:
#   HEADSCALE_SERVER, HEADSCALE_USER, HEADSCALE_PASSWORD
#
# Выход:
#   Печатает имя готового файла в stdout (image.ponyname.img)
# -----------------------------------------------------------------------------

set -euo pipefail

BASE_IMG="${1:-}"
OUTPUT_DIR="${2:-}"

[[ -n "$BASE_IMG" && -f "$BASE_IMG" ]] || { echo "ERROR: Base image not found: $BASE_IMG" >&2; exit 1; }
[[ -n "$OUTPUT_DIR" && -d "$OUTPUT_DIR" ]] || { echo "ERROR: Output dir not found: $OUTPUT_DIR" >&2; exit 1; }

ZBX_SERVER_IP="${ZBX_SERVER_IP:-YOUR_TAILSCALE_IP}"
ZBX_SERVER_PORT="${ZBX_SERVER_PORT:-10051}"
ZBX_ENABLE_PSK="${ZBX_ENABLE_PSK:-no}"

HEADSCALE_SERVER="${HEADSCALE_SERVER:-}"
HEADSCALE_USER="${HEADSCALE_USER:-}"
HEADSCALE_PASSWORD="${HEADSCALE_PASSWORD:-}"
HEADSCALE_CMD_JSON="${HEADSCALE_CMD_JSON:-headscale preauthkeys create --user 1 --expiration 6h -o json}"
HEADSCALE_CMD_TEXT="${HEADSCALE_CMD_TEXT:-headscale preauthkeys create --user 1 --expiration 6h}"

[[ -n "$HEADSCALE_SERVER" && -n "$HEADSCALE_USER" && -n "$HEADSCALE_PASSWORD" ]] || {
  echo "ERROR: Set HEADSCALE_SERVER/HEADSCALE_USER/HEADSCALE_PASSWORD env vars" >&2; exit 1;
}

need(){ command -v "$1" >/dev/null 2>&1; }
info(){ echo "[INFO] $*" >&2; }

# Check deps
for cmd in losetup qemu-aarch64-static jq openssl sshpass find shuf mountpoint; do
  need "$cmd" || { echo "ERROR: Missing command: $cmd" >&2; exit 1; }
done

info "Requesting headscale preauth key…"
RAW=$(
  sshpass -p "$HEADSCALE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$HEADSCALE_USER@$HEADSCALE_SERVER" "$HEADSCALE_CMD_JSON" 2>/dev/null \
  || sshpass -p "$HEADSCALE_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$HEADSCALE_USER@$HEADSCALE_SERVER" "$HEADSCALE_CMD_TEXT"
) || true

HEADSCALE_KEY="$(printf '%s' "$RAW" | jq -r '.key // .Key // empty' 2>/dev/null || true)"
[[ -z "$HEADSCALE_KEY" ]] && HEADSCALE_KEY="$(printf '%s' "$RAW" | grep -oE 'tskey-[A-Za-z0-9_-]+' | head -n1 || true)"
[[ -n "$HEADSCALE_KEY" ]] || { echo "ERROR: Failed to obtain headscale key" >&2; exit 1; }
export HEADSCALE_KEY

WORK="$(mktemp -d)"
TMP_IMG="$WORK/personalize.$.img"
READY_IMG=""
LOOP=""

cleanup(){
  set +e
  if [[ -n "$WORK" ]]; then
    if mountpoint -q "$WORK/root/dev/pts" 2>/dev/null; then umount -l "$WORK/root/dev/pts"; fi
    for fs in proc sys dev; do
      if mountpoint -q "$WORK/root/$fs" 2>/dev/null; then umount -lR "$WORK/root/$fs"; fi
    done
    if mountpoint -q "$WORK/root/boot/firmware" 2>/dev/null; then umount -l "$WORK/root/boot/firmware"; fi
    if mountpoint -q "$WORK/boot" 2>/dev/null; then umount -l "$WORK/boot"; fi
    if mountpoint -q "$WORK/root" 2>/dev/null; then umount -l "$WORK/root"; fi
  fi
  if [[ -n "${LOOP:-}" ]]; then losetup -d "$LOOP" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

info "Copying base image…"
cp --reflink=auto "$BASE_IMG" "$TMP_IMG"

info "Mounting…"
LOOP="$(losetup -f --show -P "$TMP_IMG")"
mkdir -p "$WORK/root" "$WORK/boot"
mount "${LOOP}p2" "$WORK/root"
mount "${LOOP}p1" "$WORK/boot"
mkdir -p "$WORK/root/boot/firmware"
mount --bind "$WORK/boot" "$WORK/root/boot/firmware"

cp /etc/resolv.conf "$WORK/root/etc/resolv.conf"
install -m 0755 /usr/bin/qemu-aarch64-static "$WORK/root/usr/bin/qemu-aarch64-static"
for fs in proc sys dev; do mount --bind "/$fs" "$WORK/root/$fs"; done
mount -t devpts devpts "$WORK/root/dev/pts" 2>/dev/null || true

# Choose pony name
choose_pony(){ local dir="$1"
  find "$dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sed 's/\.[^.]*$//' | shuf -n1
}
PONY=""
for d in "$WORK/root/usr/share/ponysay/ponies" "$WORK/root/usr/local/share/ponysay/ponies"; do
  PONY="$(choose_pony "$d")"; [[ -n "$PONY" ]] && break
done
[[ -n "$PONY" ]] || PONY="twilight_sparkle"
READY_IMG="image.${PONY}.img"
info "PONY=$PONY"

info "Entering chroot…"
export PONY ZBX_SERVER_IP ZBX_SERVER_PORT ZBX_ENABLE_PSK

chroot "$WORK/root" /bin/bash -euo pipefail -s <<'EOS'
export DEBIAN_FRONTEND=noninteractive

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

# Hostname
echo "${PONY}" > /etc/hostname
HN="$(cat /etc/hostname)"
grep -qE '^127\.0\.0\.1\s+localhost' /etc/hosts || echo '127.0.0.1 localhost' >> /etc/hosts
sed -i -E '/^127\.0\.1\.1[[:space:]]+/d' /etc/hosts
echo "127.0.1.1 ${HN}" >> /etc/hosts

# Zabbix config
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

# tailscale-firstboot
LOGIN_SERVER="https://headscale.example.com"
KEY="${HEADSCALE_KEY:-}"

cat >/usr/local/sbin/tailscale-firstboot.sh <<'SCRIPT'
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
SCRIPT
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

# NetworkManager: ignore eth0
install -d -m 0755 /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/10-eth0-unmanaged.conf <<'CNF'
[keyfile]
unmanaged-devices=interface-name:eth0
CNF

# eth0-guard
install -d -m 0755 /etc/default
cat >/etc/default/eth0-guard <<'CONF'
GPIOCHIP=gpiochip0
GPIOLINE=17
ALLOW_LEVEL=0
CONF

cat >/usr/local/sbin/eth0-guard.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
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
Description=Disable eth0 at boot
DefaultDependencies=no
Before=network-pre.target network.target NetworkManager.service
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
Description=Watch GPIO for eth0 unlock
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
EOS

# userconf
info "Writing userconf.txt…"
PASSHASH="$(openssl passwd -6 YOUR_PASSWORD)"
echo "kali:$PASSHASH" > "$WORK/boot/userconf.txt"
touch "$WORK/boot/ssh" || true

info "Unmounting…"
umount -l "$WORK/root/dev/pts" 2>/dev/null || true
for fs in proc sys dev; do umount -lR "$WORK/root/$fs" 2>/dev/null || true; done
umount -l "$WORK/root/boot/firmware" 2>/dev/null || true
umount -l "$WORK/boot" "$WORK/root"
losetup -d "$LOOP"
LOOP=""

# Move to output
mv -f "$TMP_IMG" "$OUTPUT_DIR/$READY_IMG"

# Compress image for faster download
info "Compressing image (this may take 2-3 minutes)…"
if command -v pigz >/dev/null 2>&1; then
  # Use pigz for parallel compression (faster)
  pigz -9 "$OUTPUT_DIR/$READY_IMG"
else
  # Fallback to gzip
  gzip -9 "$OUTPUT_DIR/$READY_IMG"
fi
READY_IMG="${READY_IMG}.gz"

# Print filename to stdout (for Flask to capture)
echo "$READY_IMG"
