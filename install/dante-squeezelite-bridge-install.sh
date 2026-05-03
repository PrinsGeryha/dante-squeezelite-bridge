#!/usr/bin/env bash

# Copyright (c) 2026 Marcus Isdahl
# Author: Marcus Isdahl
# License: MIT
# Source: https://github.com/PrinsGeryha/dante-squeezelite-bridge

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

APP="Dante-Squeezelite-Bridge"
APP_DIR="/opt/dante-squeezelite-bridge"
ZONE_NAME="${HOSTNAME:-DanteZone}"
ZONE_NAME="${ZONE_NAME// /}"
SERVICE_NAME="squeezelite-${ZONE_NAME,,}.service"
ALSA_PLUGIN_DIR="/usr/lib/x86_64-linux-gnu/alsa-lib"

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
  squeezelite
msg_ok "Installed Dependencies"

msg_info "Installing Rust"
if ! command -v cargo &>/dev/null; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y
fi

source "$HOME/.cargo/env"

if ! rustup show active-toolchain &>/dev/null; then
  $STD rustup default stable
fi
msg_ok "Installed Rust"

msg_info "Building Statime"
if [[ ! -d /opt/statime ]]; then
  $STD git clone --recurse-submodules -b inferno-dev https://github.com/teodly/statime.git /opt/statime
fi

cd /opt/statime
$STD cargo build --release

if [[ ! -x /opt/statime/target/release/statime ]]; then
  msg_error "Statime build failed"
  exit 1
fi

sed -i "s/^interface = .*$/interface = \"$IFACE\"/" /opt/statime/inferno-ptpv1.toml
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
RANDOM_MAC="$(printf '02:%02X:%02X:%02X:%02X:%02X\n' \
  $((RANDOM % 256)) \
  $((RANDOM % 256)) \
  $((RANDOM % 256)) \
  $((RANDOM % 256)) \
  $((RANDOM % 256)))"

cat <<EOF >"/etc/systemd/system/$SERVICE_NAME"
[Unit]
Description=Squeezelite Dante Player - $ZONE_NAME
After=statime.service network-online.target
Wants=network-online.target
Requires=statime.service

[Service]
Type=simple
Environment=INFERNO_NAME=$ZONE_NAME
ExecStart=/usr/bin/squeezelite \\
  -n $ZONE_NAME \\
  -o inferno \\
  -r 48000 \\
  -b 4096:1024 \\
  -u h:48000 \\
  -a 256:4::0 \\
  -m $RANDOM_MAC
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

msg_info "Writing Version Info"
mkdir -p "$APP_DIR"

cat <<EOF >"$APP_DIR/info.txt"
Application: Dante Squeezelite Bridge
Zone: $ZONE_NAME
Interface: $IFACE
Squeezelite service: $SERVICE_NAME
MAC: $RANDOM_MAC
Sample rate: 48000 Hz
Music Assistant recommendation: WAV output at 48 kHz
Installed: $(date -Iseconds)
EOF

cat <<EOF >/opt/dante-squeezelite-bridge_version.txt
Version: 1.0.0
Zone: $ZONE_NAME
Interface: $IFACE
Service: $SERVICE_NAME
Installed: $(date -Iseconds)
EOF
msg_ok "Wrote Version Info"

msg_info "Cleaning Up"
$STD apt -y autoremove
$STD apt -y autoclean
msg_ok "Cleaned Up"

motd_ssh
customize

msg_ok "Installed $APP"
cleanup_lxc
