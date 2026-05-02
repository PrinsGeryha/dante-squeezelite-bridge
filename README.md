# Dante Audio Bridge with Inferno and Squeezelite for Debian on Proxmox.

A working Debian-based setup for creating Dante audio transmitters from a Proxmox LXC container or Debian install using [`inferno`](https://github.com/teodly/inferno) and `squeezelite`.

This project is intended for homelab and whole-home audio setups where you want software-based audio players to appear as Dante transmitters on the network.

## What this does

This setup creates one or more virtual audio zones, for example:

* `Bathroom`
* `Dining room`
* `Kitchen`
* `Guest room`

Each zone runs its own `squeezelite` instance. Audio from `squeezelite` is sent to an ALSA device named `inferno`, which is then transmitted onto the Dante network using Inferno.

The Dante transmitters can then be routed in Dante Controller to a DSP, amplifier, or other Dante receiver.

Example target setup:

```text
Music Assistant / LMS / Squeezebox source
        ↓
Squeezelite
        ↓
ALSA virtual output: inferno
        ↓
Inferno Dante transmitter
        ↓
Dante Controller routing
        ↓
DSP / amplifier / speaker zone
```

## Tested environment

This was tested with:

* Proxmox VE
* Debian 12 container / install
* Inferno from: [https://github.com/teodly/inferno](https://github.com/teodly/inferno)
* Squeezelite
* Dante Controller
* Bose EX-1280 DSP / Dante receiver
* Music Assistant using Squeezelite players

## Requirements

### System packages

Install the basic build and audio requirements:

```bash
apt update
apt install -y \
  git \
  build-essential \
  cmake \
  pkg-config \
  alsa-utils \
  libasound2-dev \
  squeezelite
```

Depending on your Debian install, Inferno may require additional Rust/build dependencies. Install them as needed according to the Inferno repository.

## Network requirements

Dante is sensitive to multicast, timing, and network discovery.

Recommended:

* Use wired Ethernet.
* Keep Dante devices on the same VLAN if possible.
* Avoid Wi-Fi for Dante audio.
* Make sure multicast is allowed between the Dante sender and receiver.
* Use Dante Controller to confirm that transmitters appear correctly.

If running inside Proxmox, make sure the container or VM has direct access to the correct network bridge/VLAN.

## One-command installer

The recommended way is to use the installer script below as `install.sh`.

It installs:

* Required Debian packages
* Rust toolchain
* Statime PTP clock daemon
* Inferno ALSA plugin
* Squeezelite
* A zone-specific systemd service
* Real-time audio permissions

Create the file:

```bash
nano install.sh
```

Paste:

```bash
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
```

Make it executable and run it:

```bash
chmod +x install.sh
./install.sh
```

## ALSA configuration

Create or edit the ALSA configuration for the zone.

Example for a zone named `Bathroom`:

```bash
nano /root/.asoundrc
```

Example `.asoundrc`:

```conf
pcm.inferno {
    type plug
    slave {
        pcm "bathroom"
        format S32_LE
        rate 48000
        channels 2
    }
}

ctl.inferno {
    type hw
    card 0
}
```

The important part is that `squeezelite` outputs to the ALSA device named `inferno`.

## Squeezelite service

Create a dedicated systemd service for each zone.

Example:

```bash
nano /etc/systemd/system/squeezelite-bathroom.service
```

```ini
[Unit]
Description=Squeezelite Dante Player - Bathroom
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
Environment=INFERNO_NAME=Bathroom
ExecStart=/usr/bin/squeezelite \
  -n Baderom \
  -o inferno \
  -r 48000 \
  -b 4096:1024 \
  -u h:48000 \
  -a 256:4::0 \
  -m 00:11:22:33:44:b1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Enable and start it:

```bash
systemctl daemon-reload
systemctl enable --now squeezelite-bathroom.service
systemctl status squeezelite-bathroom.service
```

## Important Squeezelite options

The working example uses:

```bash
-o inferno
-r 48000
-b 4096:1024
-u h:48000
-a 256:4::0
```

Explanation:

| Option         | Purpose                                          |
| -------------- | ------------------------------------------------ |
| `-o inferno`   | Sends audio to the ALSA `inferno` output         |
| `-r 48000`     | Forces 48 kHz sample rate, suitable for Dante    |
| `-b 4096:1024` | Sets stream/output buffer sizes                  |
| `-u h:48000`   | Enables high-quality resampling to 48 kHz        |
| `-a 256:4::0`  | ALSA output tuning                               |
| `-m`           | Sets a stable unique MAC address for each player |
| `-n`           | Sets the Squeezelite player name                 |

Each zone must have a unique MAC address when using `-m`.

Example MAC scheme:

```text
Baderom    00:11:22:33:44:b1
Kjokken    00:11:22:33:44:b2
Spisestue  00:11:22:33:44:b3
Gjesterom  00:11:22:33:44:b4
```

## Multiple zones

For multiple zones, create one service per zone and give each one:

* A unique service name
* A unique `INFERNO_NAME`
* A unique Squeezelite player name using `-n`
* A unique MAC address using `-m`
* A matching ALSA/Inferno device configuration

Example service names:

```text
squeezelite-bathroom.service
squeezelite-kitchen.service
squeezelite-livingroom.service
squeezelite-guestroom.service
```

## Dante Controller

After starting the services:

1. Open Dante Controller.
2. Wait for the transmitters to appear.
3. Look for the names defined by `INFERNO_NAME`, for example `Bathroom`.
4. Route the transmitter channels to your receiver/DSP/amplifier.
5. Confirm clocking and sample rate are correct.

## Troubleshooting

### Dante transmitter does not appear

Check:

```bash
systemctl status squeezelite-bathroom.service
journalctl -u squeezelite-bathroom.service -f
```

Also verify:

* The container/VM is on the correct VLAN.
* Multicast is allowed.
* Dante Controller is on the same reachable network.
* The Inferno binary exists and is executable.
* The zone name is valid.

### Squeezelite starts but no audio

Check available ALSA devices:

```bash
aplay -L
```

Confirm that `inferno` appears as an output.

Test Squeezelite manually:

```bash
/usr/bin/squeezelite -n TestZone -o inferno -r 48000 -b 4096:1024 -u h:48000 -a 256:4::0 -m 00:11:22:33:44:99
```

### Wrong name appears in Dante Controller

Make sure the service includes:

```ini
Environment=INFERNO_NAME=Bathroom
```

Then restart the service:

```bash
systemctl daemon-reload
systemctl restart squeezelite-bathroom.service
```

### Multiple players conflict

Make sure every Squeezelite instance has a unique MAC address:

```bash
-m 00:11:22:33:44:b1
```

Do not reuse the same MAC address across multiple zones.

## Example complete zone: Baderom

`.asoundrc`:

```conf
pcm.inferno {
    type plug
    slave {
        pcm "bathroom"
        format S32_LE
        rate 48000
        channels 2
    }
}

ctl.inferno {
    type hw
    card 0
}
```

Systemd service:

```ini
[Unit]
Description=Squeezelite Dante Player - Bathroom
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
Environment=INFERNO_NAME=Bathroom
ExecStart=/usr/bin/squeezelite \
  -n Baderom \
  -o inferno \
  -r 48000 \
  -b 4096:1024 \
  -u h:48000 \
  -a 256:4::0 \
  -m 00:11:22:33:44:b1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Commands:

```bash
systemctl daemon-reload
systemctl enable --now squeezelite-bathroom.service
journalctl -u squeezelite-bathroom.service -f
```

## Notes

This setup is based on a working homelab installation. It may require adjustment depending on your network, Dante hardware, Proxmox configuration, and Inferno build path.

Use Dante Controller to confirm routing, device names, clock status, and sample rate.

## Disclaimer

This is not an official Dante, Audinate, Bose, Proxmox, or Squeezelite guide. Use at your own risk.
