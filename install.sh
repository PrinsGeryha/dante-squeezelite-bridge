#!/bin/bash

set -e

SCRIPT_NAME="Inferno + Statime + Squeezelite Installer"

echo "$SCRIPT_NAME"
echo "teodly/inferno compliant Debian / Proxmox installer"
echo

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# User prompt for zone name
read -p "Enter Inferno/Dante Zone Name (no spaces, lowercase recommended): " ZONE_NAME

if [[ -z "$ZONE_NAME" ]]; then
    echo "Zone name cannot be empty."
    exit 1
fi

if [[ "$ZONE_NAME" =~ [[:space:]] ]]; then
    echo "Zone name cannot contain spaces."
    exit 1
fi

SERVICE_NAME="squeezelite-${ZONE_NAME}.service"

# Detect default network interface
IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)

if [[ -z "$IFACE" ]]; then
    echo "Could not detect default network interface."
    exit 1
fi

echo "Using network interface: $IFACE"

# Update system and install prerequisites
apt update
apt install -y \
  git \
  curl \
  build-essential \
  libasound2-dev \
  pkg-config \
  libavahi-client-dev \
  libjack-jackd2-dev \
  alsa-utils \
  libcap2-bin \
  squeezelite

# Install Rust via rustup if not installed
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust via rustup..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "Rust already installed."
fi

# Ensure cargo environment is loaded
if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

# Ensure default Rust toolchain is set
if ! rustup show active-toolchain &>/dev/null; then
    echo "Setting default Rust toolchain to stable..."
    rustup default stable
fi

# Clone and build Statime
if [[ -d "/opt/statime" ]]; then
    read -p "Statime already cloned. Remove and re-clone? (y/n): " REMOVE_STATIME
    if [[ "$REMOVE_STATIME" == "y" || "$REMOVE_STATIME" == "Y" ]]; then
        rm -rf /opt/statime
        git clone --recurse-submodules -b inferno-dev https://github.com/teodly/statime.git /opt/statime
    else
        echo "Keeping existing /opt/statime."
    fi
else
    git clone --recurse-submodules -b inferno-dev https://github.com/teodly/statime.git /opt/statime
fi

cd /opt/statime
cargo build --release

# Configure Statime interface
if [[ -f "/opt/statime/inferno-ptpv1.toml" ]]; then
    sed -i "s/^interface = .*$/interface = \"$IFACE\"/" /opt/statime/inferno-ptpv1.toml
else
    echo "Warning: /opt/statime/inferno-ptpv1.toml was not found."
fi

# Disable conflicting time sync services if present
systemctl stop chronyd.service systemd-timesyncd.service ntpd.service 2>/dev/null || true
systemctl disable chronyd.service systemd-timesyncd.service ntpd.service 2>/dev/null || true

# Create Statime systemd service
cat <<EOF > /etc/systemd/system/statime.service
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

systemctl daemon-reload
systemctl enable --now statime.service

# Clone and build Inferno
if [[ -d "/opt/inferno" ]]; then
    read -p "Inferno already cloned. Remove and re-clone? (y/n): " REMOVE_INFERNO
    if [[ "$REMOVE_INFERNO" == "y" || "$REMOVE_INFERNO" == "Y" ]]; then
        rm -rf /opt/inferno
        git clone --recursive https://github.com/teodly/inferno.git /opt/inferno
    else
        echo "Keeping existing /opt/inferno."
    fi
else
    git clone --recursive https://github.com/teodly/inferno.git /opt/inferno
fi

cd /opt/inferno/alsa_pcm_inferno
cargo build --release

# Install ALSA Inferno module
ALSA_PLUGIN_DIR="/usr/lib/x86_64-linux-gnu/alsa-lib"
mkdir -p "$ALSA_PLUGIN_DIR"

if [[ -f "/opt/inferno/target/release/libasound_module_pcm_inferno.so" ]]; then
    cp /opt/inferno/target/release/libasound_module_pcm_inferno.so "$ALSA_PLUGIN_DIR/"
elif [[ -f "/opt/inferno/alsa_pcm_inferno/target/release/libasound_module_pcm_inferno.so" ]]; then
    cp /opt/inferno/alsa_pcm_inferno/target/release/libasound_module_pcm_inferno.so "$ALSA_PLUGIN_DIR/"
else
    echo "Could not find libasound_module_pcm_inferno.so after build."
    exit 1
fi

# Configure ALSA for Inferno
cat <<EOF > /root/.asoundrc
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

# Real-time permissions
setcap 'cap_sys_nice=eip' /usr/bin/squeezelite || true
cat <<EOF > /etc/security/limits.d/audio.conf
@audio   -  rtprio     95
@audio   -  memlock    unlimited
EOF
usermod -aG audio root

# Generate locally administered random MAC address
RANDOM_MAC=$(printf '02:%02X:%02X:%02X:%02X:%02X
' \
  $((RANDOM%256)) \
  $((RANDOM%256)) \
  $((RANDOM%256)) \
  $((RANDOM%256)) \
  $((RANDOM%256)))

# Create zone-specific Squeezelite systemd service
cat <<EOF > /etc/systemd/system/$SERVICE_NAME
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
  -o inferno \
  -r 48000 \
  -b 4096:1024 \
  -u h:48000 \
  -a 256:4::0 \
  -m $RANDOM_MAC
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo
echo "Installation complete."
echo "Zone name: $ZONE_NAME"
echo "Service: $SERVICE_NAME"
echo "Generated MAC: $RANDOM_MAC"
echo
echo "Check status with:"
echo "  systemctl status statime.service"
echo "  systemctl status $SERVICE_NAME"
echo
echo "Follow logs with:"
echo "  journalctl -u statime.service -f"
echo "  journalctl -u $SERVICE_NAME -f"
echo
echo "Reboot recommended."