#!/usr/bin/env bash

# Copyright (c) 2026 Marcus Isdahl
# Author: Marcus Isdahl
# License: MIT
# Source: https://github.com/PrinsGeryha/squeezelite-dante-bridge

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP="Squeezelite-Dante-Bridge"
APP_DIR="/opt/squeezelite-dante-bridge"
CONFIG_FILE="/etc/squeezelite-dante-bridge.conf"
INFO_FILE="$APP_DIR/info.txt"
VERSION_FILE="/opt/squeezelite-dante-bridge_version.txt"
ALSA_PLUGIN_DIR="/usr/lib/x86_64-linux-gnu/alsa-lib"
DEFAULT_ZONE="SqueezelitePlayer"
STATIME_BRANCH="inferno-dev"
VERSION="1.0.0"

# Load previous config if it exists. This allows updates/re-runs to reuse values.
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

function sanitize_zone_name() {
  local zone="$1"
  zone="${zone// /}"
  echo "$zone"
}

function get_zone_name() {
  if [[ -n "${ZONE_NAME:-}" ]]; then
    ZONE_NAME="$(sanitize_zone_name "$ZONE_NAME")"
    return
  fi

  echo ""
  echo -e "${YW}Dante / Squeezelite Zone Setup${CL}"
  echo -e "${INFO} This name will be used for:"
  echo "  - Inferno Dante transmitter name"
  echo "  - Squeezelite player name"
  echo "  - Music Assistant player name"
  echo ""

  read -rp "Enter zone name [${DEFAULT_ZONE}]: " ZONE_INPUT
  ZONE_INPUT="${ZONE_INPUT:-$DEFAULT_ZONE}"

  ZONE_NAME="$(sanitize_zone_name "$ZONE_INPUT")"
}

function get_server_address() {
  if [[ -n "${SERVER_ADDRESS:-}" ]]; then
    return
  fi

  echo ""
  echo -e "${YW}Music Assistant / LMS Server Setup${CL}"
  echo -e "${INFO} Leave blank to use Squeezelite auto-discovery. This is the default."
  echo ""

  read -rp "Enter Music Assistant/LMS server IP or hostname [blank = auto-discovery]: " SERVER_ADDRESS
}

function get_squeezelite_mac() {
  if [[ -n "${SQUEEZELITE_MAC:-}" ]]; then
    return
  fi

  if [[ -f "$INFO_FILE" ]]; then
    EXISTING_MAC="$(awk -F': ' '/^MAC:/ {print $2}' "$INFO_FILE" | head -n1 || true)"
    if [[ -n "$EXISTING_MAC" ]]; then
      SQUEEZELITE_MAC="$EXISTING_MAC"
      return
    fi
  fi

  echo ""
  echo -e "${YW}Squeezelite MAC Setup${CL}"
  echo -e "${INFO} Leave blank to generate a random MAC address. This is the default."
  echo -e "${INFO} Use a fixed MAC if you want the player identity to survive reinstall/rebuild."
  echo ""

  read -rp "Enter fixed Squeezelite MAC address [blank = random generated]: " SQUEEZELITE_MAC
}

function generate_random_mac() {
  printf '02:%02X:%02X:%02X:%02X:%02X
' \
    $((RANDOM % 256)) \
    $((RANDOM % 256)) \
    $((RANDOM % 256)) \
    $((RANDOM % 256)) \
    $((RANDOM % 256))
}

function validate_config() {
  if [[ -z "$ZONE_NAME" ]]; then
    msg_error "Zone name cannot be empty"
    exit 1
  fi

  if [[ "$ZONE_NAME" =~ [[:space:]] ]]; then
    msg_error "Zone name cannot contain spaces"
    exit 1
  fi

  if [[ ! "$ZONE_NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
    msg_error "Zone name can only contain letters, numbers, dash and underscore"
    exit 1
  fi

  if [[ -n "${SQUEEZELITE_MAC:-}" ]]; then
    if [[ ! "$SQUEEZELITE_MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
      msg_error "Invalid MAC address format. Example: 00:11:22:33:44:b1"
      exit 1
    fi
  fi
}

function write_persistent_config() {
  cat <<EOF >"$CONFIG_FILE"
ZONE_NAME="$ZONE_NAME"
SERVER_ADDRESS="$SERVER_ADDRESS"
SQUEEZELITE_MAC="$PLAYER_MAC"
SERVICE_NAME="$SERVICE_NAME"
SAMPLE_RATE="48000"
AUDIO_FORMAT="WAV"
CONSOLE_AUTO_LOGIN="true"
EOF
}

function health_check() {
  msg_info "Running Health Checks"

  if systemctl is-active --quiet statime.service; then
    msg_ok "Statime is running"
  else
    msg_error "Statime is not running. Check: journalctl -u statime.service -f"
  fi

  if systemctl is-active --quiet "$SERVICE_NAME"; then
    msg_ok "Squeezelite is running"
  else
    msg_error "Squeezelite is not running. Check: journalctl -u $SERVICE_NAME -f"
  fi

  if aplay -L | grep -q '^inferno'; then
    msg_ok "ALSA Inferno device found"
  else
    msg_error "ALSA Inferno device was not found. Check /root/.asoundrc and the Inferno ALSA plugin."
  fi
}

get_zone_name
get_server_address
get_squeezelite_mac
ENABLE_AUTO_LOGIN="true"
validate_config

SERVICE_NAME="squeezelite-${ZONE_NAME,,}.service"
SERVER_OPTION=""
if [[ -n "${SERVER_ADDRESS:-}" ]]; then
  SERVER_OPTION="-s $SERVER_ADDRESS"
fi

if [[ -n "${SQUEEZELITE_MAC:-}" ]]; then
  PLAYER_MAC="$SQUEEZELITE_MAC"
else
  PLAYER_MAC="$(generate_random_mac)"
fi

IFACE="$(ip -o -4 route show to default | awk '{print $5}' | head -n1)"

if [[ -z "$IFACE" ]]; then
  msg_error "Could not detect default network interface"
  exit 1
fi

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  libasound2-dev \
  pkg-config \
  libavahi-client-dev \
  libjack-jackd2-dev \
  alsa-utils \
  libcap2-bin \
  squeezelite \
  curl \
  git
msg_ok "Installed Dependencies"

msg_info "Installing Rust"
if ! command -v cargo &>/dev/null; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y
fi

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

if ! command -v cargo &>/dev/null; then
  msg_error "Cargo was not found after Rust installation"
  exit 1
fi

if ! command -v rustup &>/dev/null; then
  msg_error "rustup was not found after Rust installation"
  exit 1
fi

if ! rustup show active-toolchain &>/dev/null; then
  $STD rustup default stable
fi
msg_ok "Installed Rust"

msg_info "Building Statime"
if [[ ! -d /opt/statime ]]; then
  $STD git clone --recurse-submodules -b "$STATIME_BRANCH" https://github.com/teodly/statime.git /opt/statime
else
  cd /opt/statime
  $STD git pull || true
fi

cd /opt/statime
$STD cargo build --release

if [[ ! -x /opt/statime/target/release/statime ]]; then
  msg_error "Statime build failed"
  exit 1
fi

if [[ -f /opt/statime/inferno-ptpv1.toml ]]; then
  sed -i "s/^interface = .*$/interface = \"$IFACE\"/" /opt/statime/inferno-ptpv1.toml
else
  msg_error "Missing /opt/statime/inferno-ptpv1.toml"
  exit 1
fi
msg_ok "Built Statime"

msg_info "Creating Statime Service"
systemctl stop chronyd.service systemd-timesyncd.service ntpd.service 2>/dev/null || true
systemctl disable chronyd.service systemd-timesyncd.service ntpd.service 2>/dev/null || true

cat <<EOF >/etc/systemd/system/statime.service
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
msg_ok "Created Statime Service"

msg_info "Building Inferno ALSA Plugin"
if [[ ! -d /opt/inferno ]]; then
  $STD git clone --recursive https://github.com/teodly/inferno.git /opt/inferno
else
  cd /opt/inferno
  $STD git pull || true
fi

cd /opt/inferno/alsa_pcm_inferno
$STD cargo build --release

mkdir -p "$ALSA_PLUGIN_DIR"

if [[ -f /opt/inferno/target/release/libasound_module_pcm_inferno.so ]]; then
  cp /opt/inferno/target/release/libasound_module_pcm_inferno.so "$ALSA_PLUGIN_DIR/"
elif [[ -f /opt/inferno/alsa_pcm_inferno/target/release/libasound_module_pcm_inferno.so ]]; then
  cp /opt/inferno/alsa_pcm_inferno/target/release/libasound_module_pcm_inferno.so "$ALSA_PLUGIN_DIR/"
else
  msg_error "Could not find libasound_module_pcm_inferno.so"
  exit 1
fi
msg_ok "Built Inferno ALSA Plugin"

msg_info "Configuring ALSA"
if [[ -f /root/.asoundrc ]]; then
  cp /root/.asoundrc "/root/.asoundrc.backup.$(date +%Y%m%d-%H%M%S)"
fi

cat <<EOF >/root/.asoundrc
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
msg_ok "Configured ALSA"

msg_info "Configuring Real-Time Audio"
setcap 'cap_sys_nice=eip' /usr/bin/squeezelite || true

cat <<EOF >/etc/security/limits.d/audio.conf
@audio   -  rtprio     95
@audio   -  memlock    unlimited
EOF

usermod -aG audio root
msg_ok "Configured Real-Time Audio"

msg_info "Creating Squeezelite Service"
cat <<EOF >"/etc/systemd/system/$SERVICE_NAME"
[Unit]
Description=Squeezelite Dante Player - $ZONE_NAME
After=statime.service network-online.target
Wants=network-online.target
Requires=statime.service

[Service]
Type=simple
Environment=INFERNO_NAME=$ZONE_NAME
ExecStart=/usr/bin/squeezelite \
  -n $ZONE_NAME \
  $SERVER_OPTION \
  -o inferno \
  -r 48000 \
  -b 4096:1024 \
  -u h:48000 \
  -a 256:4::0 \
  -m $PLAYER_MAC
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Squeezelite Service"

msg_info "Enabling Services"
systemctl daemon-reload
systemctl enable -q --now statime.service
systemctl enable -q --now "$SERVICE_NAME"
msg_ok "Enabled Services"

msg_info "Configuring Console Auto-Login"
if systemctl list-unit-files | grep -q '^container-getty@.service'; then
  mkdir -p /etc/systemd/system/container-getty@1.service.d
  cat <<EOF >/etc/systemd/system/container-getty@1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud pts/%I 115200,38400,9600 \$TERM
EOF
  systemctl daemon-reload
  systemctl restart container-getty@1.service 2>/dev/null || true
elif systemctl list-unit-files | grep -q '^getty@.service'; then
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat <<EOF >/etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF
  systemctl daemon-reload
  systemctl restart getty@tty1.service 2>/dev/null || true
else
  msg_error "Could not find a compatible getty service for console auto-login"
  exit 1
fi
msg_ok "Configured Console Auto-Login"

msg_info "Writing Configuration and Installation Info"
mkdir -p "$APP_DIR"
write_persistent_config

cat <<EOF >"$INFO_FILE"
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

cat <<EOF >"$VERSION_FILE"
Version: $VERSION
Zone: $ZONE_NAME
Interface: $IFACE
Service: $SERVICE_NAME
Installed: $(date -Iseconds)
EOF
msg_ok "Wrote Configuration and Installation Info"

health_check

msg_info "Cleaning Up"
$STD apt -y autoremove
$STD apt -y autoclean
msg_ok "Cleaned Up"

motd_ssh
customize

msg_ok "Installed $APP"

echo ""
echo -e "${INFO} Installation summary:"
echo -e "${INFO} Zone name: ${ZONE_NAME}"
echo -e "${INFO} Dante Controller transmitter name: ${ZONE_NAME}"
echo -e "${INFO} Music Assistant/LMS server: ${SERVER_ADDRESS:-auto-discovery}"
echo -e "${INFO} Squeezelite MAC: ${PLAYER_MAC}"
echo -e "${INFO} Service: ${SERVICE_NAME}"
echo -e "${INFO} Dante sample rate: 48000 Hz"
echo -e "${INFO} Music Assistant setting: WAV at 48 kHz"
echo -e "${INFO} Config file: ${CONFIG_FILE}"
echo -e "${INFO} Info file: ${INFO_FILE}"
echo ""
echo -e "${INFO} Useful commands:"
echo "  systemctl status statime.service"
echo "  systemctl status ${SERVICE_NAME}"
echo "  journalctl -u statime.service -f"
echo "  journalctl -u ${SERVICE_NAME} -f"
echo "  aplay -L | grep -A5 inferno"

cleanup_lxc
