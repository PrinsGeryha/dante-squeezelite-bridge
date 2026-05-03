#!/usr/bin/env bash

# Copyright (c) 2026 Marcus Isdahl
# Author: Marcus Isdahl
# License: MIT
# Source: https://github.com/marcusisdahl/squeezelite-dante-bridge

set -Eeuo pipefail

APP="Squeezelite-Dante-Bridge"
VERSION="1.0.0"

DEFAULT_CTID=""
DEFAULT_HOSTNAME=""
DEFAULT_ZONE="SqueezelitePlayer"
DEFAULT_STORAGE="local-lvm"
DEFAULT_TEMPLATE_STORAGE="local"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_MEMORY="1024"
DEFAULT_CORES="2"
DEFAULT_DISK="8"
DEFAULT_TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
DEFAULT_UNPRIVILEGED="0"

CTID="${CTID:-$DEFAULT_CTID}"
CT_HOSTNAME="${CT_HOSTNAME:-$DEFAULT_HOSTNAME}"
ZONE_NAME="$DEFAULT_ZONE"
SERVER_ADDRESS=""
SQUEEZELITE_MAC=""
STORAGE="$DEFAULT_STORAGE"
TEMPLATE_STORAGE="$DEFAULT_TEMPLATE_STORAGE"
BRIDGE="$DEFAULT_BRIDGE"
MEMORY="$DEFAULT_MEMORY"
CORES="$DEFAULT_CORES"
DISK="$DEFAULT_DISK"
TEMPLATE="$DEFAULT_TEMPLATE"
UNPRIVILEGED="$DEFAULT_UNPRIVILEGED"
VERBOSE="${VERBOSE:-0}"
ADVANCED="0"
FORCE_RECREATE="0"

YW='\033[33m'
GN='\033[1;92m'
RD='\033[01;31m'
BL='\033[36m'
CL='\033[m'

CM="${GN}✔️${CL}"
CROSS="${RD}✖️${CL}"
INFO="${BL}💡${CL}"
GEAR="⚙️"
ROCKET="🚀"
ID_ICON="🆔"
CPU_ICON="🧠"
DISK_ICON="💾"
RAM_ICON="🛠️"
OS_ICON="🖥️"
PKG_ICON="📦"
NET_ICON="🌐"

header_info() {
  clear
  cat <<'EOF'
   _____                               _ _ _                 _             _              _          _     _            
  / ____|                             | (_) |               | |           | |            | |        (_)   | |           
 | (___   __ _ _   _  ___  ___ _______| |_| |_ ___ ______ __| | __ _ _ __ | |_ ___ ______| |__  _ __ _  __| | __ _  ___ 
  \___ \ / _` | | | |/ _ \/ _ \_  / _ \ | | __/ _ \______/ _` |/ _` | '_ \| __/ _ \______| '_ \| '__| |/ _` |/ _` |/ _ \
  ____) | (_| | |_| |  __/  __// /  __/ | | ||  __/     | (_| | (_| | | | | ||  __/      | |_) | |  | | (_| | (_| |  __/
 |_____/ \__, |\__,_|\___|\___/___\___|_|_|\__\___|      \__,_|\__,_|_| |_|\__\___|      |_.__/|_|  |_|\__,_|\__, |\___|
            | |                                                                                               __/ |     
            |_|                                                                                              |___/      
            
					Squeezelite Dante Bridge
EOF
}

msg_info() {
  echo -e "${INFO} ${YW}$1${CL}"
}

msg_ok() {
  echo -e "${CM} ${GN}$1${CL}"
}

msg_error() {
  echo -e "${CROSS} ${RD}$1${CL}"
}

die() {
  msg_error "$1"
  exit 1
}

run_cmd() {
  if [[ "$VERBOSE" == "1" ]]; then
    "$@"
  else
    "$@" &>/dev/null
  fi
}

usage() {
  cat <<EOF
$APP standalone Proxmox installer

Usage:
  bash proxmox-install.sh
  bash proxmox-install.sh --advanced
  bash proxmox-install.sh --verbose
  bash proxmox-install.sh --ctid 151 --zone Kitchen

Options:
  --ctid ID                 Container ID. Default: next available ID
  --hostname NAME           LXC hostname. Default: squeezelite-dante-<zone>
  --zone NAME               Dante/Squeezelite/Music Assistant player name. Default: $DEFAULT_ZONE
  --server ADDRESS          Music Assistant/LMS server IP or hostname. Blank/default = auto-discovery
  --mac MAC                 Fixed Squeezelite MAC. Blank/default = random generated
  --storage NAME            Container storage. Default: $DEFAULT_STORAGE
  --template-storage NAME   Template storage. Default: $DEFAULT_TEMPLATE_STORAGE
  --bridge NAME             Network bridge. Default: $DEFAULT_BRIDGE
  --memory MB               RAM in MiB. Default: $DEFAULT_MEMORY
  --cores N                 CPU cores. Default: $DEFAULT_CORES
  --disk GB                 Disk size in GB. Default: $DEFAULT_DISK
  --template FILE           Debian LXC template. Default: $DEFAULT_TEMPLATE
  --unprivileged            Create unprivileged LXC
  --force-recreate          Destroy existing CTID before creating
  --advanced                Ask for all settings interactively
  --verbose                 Show full command output
  -h, --help                Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ctid)
      CTID="${2:-}"
      shift 2
      ;;
    --hostname)
      CT_HOSTNAME="${2:-}"
      shift 2
      ;;
    --zone)
      ZONE_NAME="${2:-}"
      shift 2
      ;;
    --server)
      SERVER_ADDRESS="${2:-}"
      shift 2
      ;;
    --mac)
      SQUEEZELITE_MAC="${2:-}"
      shift 2
      ;;
    --storage)
      STORAGE="${2:-}"
      shift 2
      ;;
    --template-storage)
      TEMPLATE_STORAGE="${2:-}"
      shift 2
      ;;
    --bridge)
      BRIDGE="${2:-}"
      shift 2
      ;;
    --memory)
      MEMORY="${2:-}"
      shift 2
      ;;
    --cores)
      CORES="${2:-}"
      shift 2
      ;;
    --disk)
      DISK="${2:-}"
      shift 2
      ;;
    --template)
      TEMPLATE="${2:-}"
      shift 2
      ;;
    --unprivileged)
      UNPRIVILEGED="1"
      shift
      ;;
    --force-recreate)
      FORCE_RECREATE="1"
      shift
      ;;
    --advanced)
      ADVANCED="1"
      shift
      ;;
    --verbose)
      VERBOSE="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

sanitize_name() {
  local value="$1"
  value="${value// /}"
  echo "$value"
}

generate_hostname_from_zone() {
  local zone="$1"

  zone="$(echo "$zone" | tr '[:upper:]' '[:lower:]')"
  zone="$(echo "$zone" | sed 's/[^a-z0-9-]/-/g')"
  zone="$(echo "$zone" | sed 's/--*/-/g; s/^-//; s/-$//')"

  if [[ -z "$zone" ]]; then
    zone="squeezeliteplayer"
  fi

  echo "squeezelite-dante-${zone}"
}

get_next_ctid() {
  if command -v pvesh >/dev/null 2>&1; then
    pvesh get /cluster/nextid
  else
    echo "150"
  fi
}

ask_default_or_advanced() {
  if [[ "$ADVANCED" == "1" ]]; then
    return
  fi

  echo -e "${GEAR}  Using Default Settings on node $(hostname)"
  echo -e "${INFO}  PVE Version $(pveversion 2>/dev/null | awk -F'/' '{print $2}' || echo unknown) (Kernel: $(uname -r))"
  echo -e "${ID_ICON}  Container ID: ${CTID}"
  echo -e "${OS_ICON}  Operating System: debian (12)"
  echo -e "${PKG_ICON}  Container Type: $([[ "$UNPRIVILEGED" == "1" ]] && echo "Unprivileged" || echo "Privileged")"
  echo -e "${DISK_ICON}  Disk Size: ${DISK} GB"
  echo -e "${CPU_ICON}  CPU Cores: ${CORES}"
  echo -e "${RAM_ICON}  RAM Size: ${MEMORY} MiB"
  echo -e "${ROCKET}  Creating a ${APP} LXC using the above default settings"
  echo ""
  echo "[1] Install using default settings"
  echo "[2] Advanced settings"
  echo "[3] Cancel"
  echo ""
  read -rp "Select option [1/2/3]: " opt
  opt="${opt:-1}"

  case "$opt" in
    1)
      ADVANCED="0"
      ;;
    2)
      ADVANCED="1"
      ;;
    3)
      exit 0
      ;;
    *)
      die "Invalid option"
      ;;
  esac
}

advanced_settings() {
  [[ "$ADVANCED" != "1" ]] && return

  echo ""
  read -rp "Container ID [${CTID}]: " input
  CTID="${input:-$CTID}"

  read -rp "Hostname [auto: squeezelite-dante-<zone>]: " input
  CT_HOSTNAME="${input:-$CT_HOSTNAME}"

  read -rp "Zone name [${ZONE_NAME}]: " input
  ZONE_NAME="${input:-$ZONE_NAME}"

  read -rp "Music Assistant/LMS server IP or hostname [blank = auto-discovery]: " input
  SERVER_ADDRESS="${input:-$SERVER_ADDRESS}"

  read -rp "Fixed Squeezelite MAC address [blank = random generated]: " input
  SQUEEZELITE_MAC="${input:-$SQUEEZELITE_MAC}"

  read -rp "Container storage [${STORAGE}]: " input
  STORAGE="${input:-$STORAGE}"

  read -rp "Template storage [${TEMPLATE_STORAGE}]: " input
  TEMPLATE_STORAGE="${input:-$TEMPLATE_STORAGE}"

  read -rp "Network bridge [${BRIDGE}]: " input
  BRIDGE="${input:-$BRIDGE}"

  read -rp "CPU cores [${CORES}]: " input
  CORES="${input:-$CORES}"

  read -rp "RAM in MiB [${MEMORY}]: " input
  MEMORY="${input:-$MEMORY}"

  read -rp "Disk size in GB [${DISK}]: " input
  DISK="${input:-$DISK}"

  read -rp "Debian template [${TEMPLATE}]: " input
  TEMPLATE="${input:-$TEMPLATE}"

  echo ""
  echo "Container type:"
  echo "[1] Privileged (recommended for this audio/Dante setup)"
  echo "[2] Unprivileged"
  read -rp "Select option [1/2]: " input
  input="${input:-1}"

  case "$input" in
    1)
      UNPRIVILEGED="0"
      ;;
    2)
      UNPRIVILEGED="1"
      ;;
    *)
      die "Invalid container type"
      ;;
  esac
}

app_settings() {
  [[ "$ADVANCED" == "1" ]] && return

  echo ""
  echo -e "${GEAR}  Application Settings"
  echo -e "${INFO}  Zone name is used for Dante, Squeezelite, and Music Assistant"
  echo ""

  read -rp "Zone name [${ZONE_NAME}]: " input
  ZONE_NAME="${input:-$ZONE_NAME}"

  read -rp "Music Assistant/LMS server IP or hostname [blank = auto-discovery]: " input
  SERVER_ADDRESS="${input:-$SERVER_ADDRESS}"

  read -rp "Fixed Squeezelite MAC address [blank = random generated]: " input
  SQUEEZELITE_MAC="${input:-$SQUEEZELITE_MAC}"
}

validate_settings() {
  CTID="$(sanitize_name "$CTID")"
  ZONE_NAME="$(sanitize_name "$ZONE_NAME")"

  if [[ -z "$CT_HOSTNAME" ]]; then
    CT_HOSTNAME="$(generate_hostname_from_zone "$ZONE_NAME")"
  else
    CT_HOSTNAME="$(sanitize_name "$CT_HOSTNAME")"
  fi

  [[ -z "$CTID" ]] && die "Container ID cannot be empty"
  [[ -z "$CT_HOSTNAME" ]] && die "Hostname cannot be empty"
  [[ -z "$ZONE_NAME" ]] && die "Zone name cannot be empty"

  [[ ! "$CTID" =~ ^[0-9]+$ ]] && die "Container ID must be numeric"
  [[ ! "$CORES" =~ ^[0-9]+$ ]] && die "CPU cores must be numeric"
  [[ ! "$MEMORY" =~ ^[0-9]+$ ]] && die "Memory must be numeric"
  [[ ! "$DISK" =~ ^[0-9]+$ ]] && die "Disk size must be numeric"
  [[ ! "$ZONE_NAME" =~ ^[A-Za-z0-9_-]+$ ]] && die "Zone name can only contain letters, numbers, dash and underscore"
  [[ ! "$CT_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]] && die "Hostname contains invalid characters"

  if [[ -n "$SQUEEZELITE_MAC" && ! "$SQUEEZELITE_MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    die "Invalid MAC format. Example: 00:11:22:33:44:b1"
  fi
}

validate_host() {
  [[ $EUID -ne 0 ]] && die "Run this script as root on the Proxmox host"
  command -v pct >/dev/null 2>&1 || die "pct was not found. This must run on a Proxmox host"
  command -v pveam >/dev/null 2>&1 || die "pveam was not found. This must run on a Proxmox host"
  command -v pvesh >/dev/null 2>&1 || die "pvesh was not found. This must run on a Proxmox host"
}

download_template() {
  msg_info "Checking Template"

  if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
    run_cmd pveam update
    run_cmd pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
  fi

  msg_ok "Template ${TEMPLATE} [${TEMPLATE_STORAGE}]"
}

create_lxc() {
  if pct status "$CTID" >/dev/null 2>&1; then
    if [[ "$FORCE_RECREATE" == "1" ]]; then
      msg_info "Removing Existing LXC ${CTID}"
      pct stop "$CTID" &>/dev/null || true
      run_cmd pct destroy "$CTID" --purge 1
      msg_ok "Removed Existing LXC ${CTID}"
    else
      die "LXC ${CTID} already exists. Use --force-recreate to replace it"
    fi
  fi

  msg_info "Creating LXC Container"

  run_cmd pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
    --hostname "$CT_HOSTNAME" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --rootfs "${STORAGE}:${DISK}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
    --features nesting=1,keyctl=1 \
    --unprivileged "$UNPRIVILEGED" \
    --onboot 1

  msg_ok "LXC Container ${CTID} was successfully created"

  msg_info "Starting LXC Container"
  run_cmd pct start "$CTID"
  msg_ok "Started LXC Container"
}

wait_for_network() {
  msg_info "Checking Network in LXC"

  sleep 5

  for _ in {1..30}; do
    if pct exec "$CTID" -- ping -c1 -W1 deb.debian.org &>/dev/null; then
      msg_ok "Network in LXC is reachable (ping)"
      return
    fi

    sleep 2
  done

  die "Network in LXC is not reachable. Check bridge, DHCP, DNS, or VLAN"
}

install_inside_lxc() {
  msg_info "Installing ${APP}"
  echo -e "${INFO}  ${YW}This can take a long time. Statime and Inferno are built from source inside the LXC.${CL}"
  echo -e "${INFO}  ${YW}On slower systems, the build step may take several minutes.${CL}"

  pct exec "$CTID" -- env \
    ZONE_NAME="$ZONE_NAME" \
    SERVER_ADDRESS="$SERVER_ADDRESS" \
    SQUEEZELITE_MAC="$SQUEEZELITE_MAC" \
    VERBOSE="$VERBOSE" \
    bash -s <<'LXC_INSTALL'
set -Eeuo pipefail

APP="Squeezelite-Dante-Bridge"
APP_DIR="/opt/squeezelite-dante-bridge"
CONFIG_FILE="/etc/squeezelite-dante-bridge.conf"
INFO_FILE="$APP_DIR/info.txt"
VERSION_FILE="/opt/squeezelite-dante-bridge_version.txt"
ALSA_PLUGIN_DIR="/usr/lib/x86_64-linux-gnu/alsa-lib"
STATIME_BRANCH="inferno-dev"
VERSION="1.0.0"

ZONE_NAME="${ZONE_NAME:-SqueezelitePlayer}"
SERVER_ADDRESS="${SERVER_ADDRESS:-}"
SQUEEZELITE_MAC="${SQUEEZELITE_MAC:-}"
VERBOSE="${VERBOSE:-0}"

lxc_msg() {
  echo "    $*"
}

lxc_die() {
  echo "ERROR: $*" >&2
  exit 1
}

lxc_run() {
  if [[ "$VERBOSE" == "1" ]]; then
    "$@"
  else
    "$@" &>/dev/null
  fi
}

generate_random_mac() {
  printf '02:%02X:%02X:%02X:%02X:%02X\n' \
    $((RANDOM % 256)) \
    $((RANDOM % 256)) \
    $((RANDOM % 256)) \
    $((RANDOM % 256)) \
    $((RANDOM % 256))
}

ZONE_NAME="${ZONE_NAME// /}"

[[ -z "$ZONE_NAME" ]] && lxc_die "Zone name cannot be empty"
[[ ! "$ZONE_NAME" =~ ^[A-Za-z0-9_-]+$ ]] && lxc_die "Invalid zone name"

if [[ -n "$SQUEEZELITE_MAC" && ! "$SQUEEZELITE_MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
  lxc_die "Invalid MAC address"
fi

SERVICE_NAME="squeezelite-${ZONE_NAME,,}.service"

SERVER_OPTION=""
[[ -n "$SERVER_ADDRESS" ]] && SERVER_OPTION="-s $SERVER_ADDRESS"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

if [[ -z "${SQUEEZELITE_MAC:-}" && -f "$INFO_FILE" ]]; then
  EXISTING_MAC="$(awk -F': ' '/^MAC:/ {print $2}' "$INFO_FILE" | head -n1 || true)"
  [[ -n "$EXISTING_MAC" ]] && SQUEEZELITE_MAC="$EXISTING_MAC"
fi

PLAYER_MAC="${SQUEEZELITE_MAC:-$(generate_random_mac)}"

IFACE="$(ip -o -4 route show to default | awk '{print $5}' | head -n1)"
[[ -z "$IFACE" ]] && lxc_die "Could not detect default network interface"

lxc_msg "Installing dependencies"
apt update
lxc_run apt install -y \
  git \
  curl \
  build-essential \
  libasound2-dev \
  pkg-config \
  libavahi-client-dev \
  libjack-jackd2-dev \
  alsa-utils \
  libcap2-bin \
  squeezelite \
  ca-certificates

lxc_msg "Installing Rust"
if ! command -v cargo &>/dev/null; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y
fi

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

command -v cargo &>/dev/null || lxc_die "cargo was not found"
command -v rustup &>/dev/null || lxc_die "rustup was not found"

if ! rustup show active-toolchain &>/dev/null; then
  lxc_run rustup default stable
fi

lxc_msg "Building Statime"
if [[ ! -d /opt/statime ]]; then
  lxc_run git clone --recurse-submodules -b "$STATIME_BRANCH" https://github.com/teodly/statime.git /opt/statime
else
  cd /opt/statime
  lxc_run git pull || true
fi

cd /opt/statime
lxc_run cargo build --release

[[ -x /opt/statime/target/release/statime ]] || lxc_die "Statime build failed"
[[ -f /opt/statime/inferno-ptpv1.toml ]] || lxc_die "Missing inferno-ptpv1.toml"

sed -i "s/^interface = .*$/interface = \"$IFACE\"/" /opt/statime/inferno-ptpv1.toml

lxc_msg "Creating Statime service"
systemctl stop chronyd.service systemd-timesyncd.service ntpd.service 2>/dev/null || true
systemctl disable chronyd.service systemd-timesyncd.service ntpd.service 2>/dev/null || true

cat >/etc/systemd/system/statime.service <<EOF
[Unit]
Description=Statime PTP clock for Inferno
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/statime/target/release/statime -c /opt/statime/inferno-ptpv1.toml
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

lxc_msg "Building Inferno ALSA plugin"
if [[ ! -d /opt/inferno ]]; then
  lxc_run git clone --recursive https://github.com/teodly/inferno.git /opt/inferno
else
  cd /opt/inferno
  lxc_run git pull || true
fi

cd /opt/inferno/alsa_pcm_inferno
lxc_run cargo build --release

mkdir -p "$ALSA_PLUGIN_DIR"

if [[ -f /opt/inferno/target/release/libasound_module_pcm_inferno.so ]]; then
  cp /opt/inferno/target/release/libasound_module_pcm_inferno.so "$ALSA_PLUGIN_DIR/"
elif [[ -f /opt/inferno/alsa_pcm_inferno/target/release/libasound_module_pcm_inferno.so ]]; then
  cp /opt/inferno/alsa_pcm_inferno/target/release/libasound_module_pcm_inferno.so "$ALSA_PLUGIN_DIR/"
else
  lxc_die "Could not find libasound_module_pcm_inferno.so"
fi

lxc_msg "Configuring ALSA"
if [[ -f /root/.asoundrc ]]; then
  cp /root/.asoundrc "/root/.asoundrc.backup.$(date +%Y%m%d-%H%M%S)"
fi

cat >/root/.asoundrc <<EOF
pcm.inferno {
    type inferno
    device "$ZONE_NAME"
    format S32_LE
    rate 48000
    channels 2
}

ctl.inferno {
    type inferno
}
EOF

lxc_msg "Configuring Squeezelite"
setcap 'cap_sys_nice=eip' /usr/bin/squeezelite || true

cat >/etc/security/limits.d/audio.conf <<EOF
@audio   -  rtprio     95
@audio   -  memlock    unlimited
EOF

usermod -aG audio root

cat >"/etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=Squeezelite Dante Player - $ZONE_NAME
After=statime.service network-online.target
Wants=network-online.target
Requires=statime.service

[Service]
Type=simple
Environment=INFERNO_NAME=$ZONE_NAME
ExecStart=/usr/bin/squeezelite -n $ZONE_NAME $SERVER_OPTION -o inferno -r 48000 -b 4096:1024 -u h:48000 -a 256:4::0 -m $PLAYER_MAC
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

lxc_msg "Configuring console auto-login"
if systemctl list-unit-files | grep -q '^container-getty@.service'; then
  mkdir -p /etc/systemd/system/container-getty@1.service.d
  cat >/etc/systemd/system/container-getty@1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud pts/%I 115200,38400,9600 \$TERM
EOF
elif systemctl list-unit-files | grep -q '^getty@.service'; then
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat >/etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF
fi

lxc_msg "Enabling services"
systemctl daemon-reload
systemctl enable --now statime.service
systemctl enable --now "$SERVICE_NAME"

mkdir -p "$APP_DIR"

cat >"$CONFIG_FILE" <<EOF
ZONE_NAME="$ZONE_NAME"
SERVER_ADDRESS="$SERVER_ADDRESS"
SQUEEZELITE_MAC="$PLAYER_MAC"
SERVICE_NAME="$SERVICE_NAME"
SAMPLE_RATE="48000"
AUDIO_FORMAT="WAV"
CONSOLE_AUTO_LOGIN="true"
EOF

cat >"$INFO_FILE" <<EOF
Application: Squeezelite Dante Bridge
Version: $VERSION
Zone: $ZONE_NAME
Interface: $IFACE
Squeezelite service: $SERVICE_NAME
MAC: $PLAYER_MAC
Sample rate: 48000 Hz
Music Assistant/LMS server: ${SERVER_ADDRESS:-auto-discovery}
Console auto-login: true
Music Assistant recommendation: WAV output at 48 kHz
Installed: $(date -Iseconds)
EOF

cat >"$VERSION_FILE" <<EOF
Version: $VERSION
Zone: $ZONE_NAME
Interface: $IFACE
Service: $SERVICE_NAME
Installed: $(date -Iseconds)
EOF

lxc_msg "Running health checks"
systemctl is-active --quiet statime.service || lxc_die "statime.service is not running"
systemctl is-active --quiet "$SERVICE_NAME" || lxc_die "$SERVICE_NAME is not running"
aplay -L | grep -q '^inferno' || lxc_die "ALSA inferno device was not found"

lxc_msg "Cleaning up"
lxc_run apt -y autoremove
lxc_run apt -y autoclean

cat <<EOF

Installation summary:
  Zone name: $ZONE_NAME
  Dante transmitter: $ZONE_NAME
  Music Assistant/LMS server: ${SERVER_ADDRESS:-auto-discovery}
  Squeezelite MAC: $PLAYER_MAC
  Service: $SERVICE_NAME
  Sample rate: 48000 Hz
  Music Assistant setting: WAV at 48 kHz
  Config: $CONFIG_FILE
  Info: $INFO_FILE
EOF
LXC_INSTALL

  msg_ok "Installed ${APP}"
}

header_info
validate_host

if [[ -z "$CTID" ]]; then
  CTID="$(get_next_ctid)"
fi

ask_default_or_advanced
advanced_settings
app_settings
validate_settings

header_info
echo -e "${GEAR}  Using $([[ "$ADVANCED" == "1" ]] && echo "Advanced" || echo "Default") Settings on node $(hostname)"
echo -e "${INFO}  PVE Version $(pveversion 2>/dev/null | awk -F'/' '{print $2}' || echo unknown) (Kernel: $(uname -r))"
echo -e "${ID_ICON}  Container ID: ${CTID}"
echo -e "${OS_ICON}  Operating System: debian (12)"
echo -e "${PKG_ICON}  Container Type: $([[ "$UNPRIVILEGED" == "1" ]] && echo "Unprivileged" || echo "Privileged")"
echo -e "${DISK_ICON}  Disk Size: ${DISK} GB"
echo -e "${CPU_ICON}  CPU Cores: ${CORES}"
echo -e "${RAM_ICON}  RAM Size: ${MEMORY} MiB"
echo -e "${INFO}  Hostname: ${CT_HOSTNAME}"
echo -e "${INFO}  Zone Name: ${ZONE_NAME}"
echo -e "${INFO}  Music Assistant/LMS Server: ${SERVER_ADDRESS:-auto-discovery}"
echo -e "${INFO}  Squeezelite MAC: ${SQUEEZELITE_MAC:-random generated}"
echo -e "${ROCKET}  Creating a ${APP} LXC using the above settings"
echo ""

read -rp "Continue? [Y/n]: " confirm
confirm="${confirm:-Y}"
[[ ! "$confirm" =~ ^[Yy]$ ]] && exit 0

download_template
create_lxc
wait_for_network
install_inside_lxc

IP="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}' || true)"

msg_ok "Completed successfully!"
echo -e "${ROCKET}  ${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}  ${YW}Dante transmitter should appear in Dante Controller as: ${ZONE_NAME}${CL}"
echo -e "${INFO}  ${YW}Add the Squeezelite player in Music Assistant and use WAV at 48 kHz.${CL}"
echo -e "${NET_ICON}  Container IP: ${IP:-unknown}"
