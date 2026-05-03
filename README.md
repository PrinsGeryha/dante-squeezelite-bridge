# Squeezelite Dante Bridge

Create software-based Dante transmitters from Squeezelite players on Debian/Proxmox using [`inferno`](https://github.com/teodly/inferno), [`statime`](https://github.com/pendulum-project/statime), and [`squeezelite`](https://github.com/ralph-irving/squeezelite).

This project is intended for homelab and whole-home audio setups where you want software-based audio players to appear as Dante transmitters on the network, without needing a dedicated hardware Dante endpoint for every zone.

## ✨ Features

- Software-based Dante transmitter using Inferno
- Squeezelite player per audio zone
- Proxmox LXC installer with a Proxmox Helper Scripts inspired interface
- Debian 12 based setup
- Statime PTP clock service
- ALSA Inferno output device
- Music Assistant / LMS compatible
- 48 kHz Dante-friendly audio path
- Optional fixed Music Assistant/LMS server address
- Optional fixed Squeezelite MAC address
- Persistent configuration file
- Health checks after installation

---

## 🧭 What this does

This setup creates a Debian LXC container on Proxmox and installs:

- Statime
- Inferno ALSA plugin
- Squeezelite
- A systemd service for the Squeezelite player
- ALSA configuration for the Inferno output

The result is a Squeezelite player that appears as a Dante transmitter on your network.

Example zones:

- `Bathroom`
- `Kitchen`
- `Diningroom`
- `Guestroom`

The zone name is used for:

- Dante transmitter name
- Squeezelite player name
- Music Assistant player name
- systemd service name

Example flow:

```text
Music Assistant / LMS / Squeezebox source
        ↓
Squeezelite
        ↓
ALSA output: inferno
        ↓
Inferno Dante transmitter
        ↓
Dante Controller routing
        ↓
DSP / amplifier / speaker zone
```

## ⚠️ Safety notice

Never run scripts from the internet without reviewing them first.

Before running the installer, inspect the script and make sure you understand what it does. This installer creates and configures an LXC container on your Proxmox host, installs packages, builds software from source, creates systemd services, and enables those services.

Review the script first:

```bash
wget -qLO proxmox-install.sh https://raw.githubusercontent.com/marcusisdahl/squeezelite-dante-bridge/main/proxmox-install.sh
nano proxmox-install.sh
```

Then run it only if you are comfortable with the contents:

```bash
bash proxmox-install.sh
```

---

## 🚀 Quick install on Proxmox

Run this on the Proxmox host:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/marcusisdahl/squeezelite-dante-bridge/main/proxmox-install.sh)"
```

For testing from the `dev` branch:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/marcusisdahl/squeezelite-dante-bridge/dev/proxmox-install.sh)"
```

Verbose mode:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/marcusisdahl/squeezelite-dante-bridge/main/proxmox-install.sh)" -- --verbose
```

---

## ⚙️ Installation options

The installer runs on the Proxmox host and creates a Debian 12 LXC container.

By default, it uses:

```text
Operating System: Debian 12
Container Type: Privileged
Disk Size: 8 GB
CPU Cores: 2
RAM: 1024 MiB
Storage: local-lvm
Template Storage: local
Network Bridge: vmbr0
```

During installation, the script asks for the important application settings:

```text
Zone name [SqueezelitePlayer]:
Music Assistant/LMS server IP or hostname [blank = auto-discovery]:
Fixed Squeezelite MAC address [blank = random generated]:
```

Leave the Music Assistant/LMS server blank to use Squeezelite auto-discovery.

Leave the fixed MAC address blank to generate a random locally administered MAC address.

Use a fixed MAC address if you want the Music Assistant/Squeezelite player identity to survive reinstalling or rebuilding the container.

---

## 🛠️ Advanced install

Run advanced mode if you want to change CTID, hostname, storage, bridge, memory, CPU, disk size, or container type:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/marcusisdahl/squeezelite-dante-bridge/main/proxmox-install.sh)" -- --advanced
```

You can also pass options directly:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/marcusisdahl/squeezelite-dante-bridge/main/proxmox-install.sh)" -- \
  --ctid 151 \
  --hostname dante-kitchen \
  --zone Kitchen \
  --server 10.10.4.30 \
  --mac 02:11:22:33:44:55
```

Common options:

```text
--ctid ID              Container ID
--hostname NAME        LXC hostname
--zone NAME            Dante/Squeezelite/Music Assistant player name
--server ADDRESS       Music Assistant/LMS server IP or hostname
--mac MAC              Fixed Squeezelite MAC address
--storage NAME         Container storage
--template-storage NAME Template storage
--bridge NAME          Network bridge
--memory MB            RAM in MiB
--cores N              CPU cores
--disk GB              Disk size in GB
--unprivileged         Create unprivileged LXC
--force-recreate       Destroy existing CTID before creating
--advanced             Ask for all settings interactively
--verbose              Show full command output
```

---

## 🎵 Music Assistant integration

This setup works well with Music Assistant.

Each Squeezelite instance appears as a player in Music Assistant.

Recommended Music Assistant settings:

```text
Output format: WAV
Sample rate: 48 kHz
```

This matches the Dante environment and avoids unnecessary resampling.

Typical flow:

```text
Music Assistant
        ↓
Squeezelite player
        ↓
Inferno ALSA output
        ↓
Dante network
```

If Music Assistant or LMS is on another VLAN and discovery does not work, enter the Music Assistant/LMS server IP or hostname during install.

This adds the `-s` option to the Squeezelite service.

---

## ✅ Tested environment

Tested with:

- Proxmox VE 8.4
- Debian 12 LXC
- Privileged container
- Inferno from: <https://github.com/teodly/inferno>
- Statime from: <https://github.com/teodly/statime>
- Squeezelite
- Dante Controller
- Bose EX-1280 DSP / Dante receiver
- Music Assistant using Squeezelite players

---

## 📁 Repository layout

Recommended repository structure:

```text
squeezelite-dante-bridge/
├── README.md
├── LICENSE
├── proxmox-install.sh
├── install.sh
├── config/
│   ├── asoundrc.example
│   └── squeezelite-dante-bridge.conf.example
└── services/
    └── squeezelite.service.example
```

### File overview

| File | Purpose |
|---|---|
| `proxmox-install.sh` | Main installer. Run this on the Proxmox host. |
| `install.sh` | Manual installer for an existing Debian LXC/VM. |
| `config/asoundrc.example` | Example ALSA Inferno configuration. |
| `config/squeezelite-dante-bridge.conf.example` | Example persistent configuration file. |
| `services/squeezelite.service.example` | Example Squeezelite systemd service. |

---

## ⚙️ Configuration

The installer writes persistent configuration to:

```text
/etc/squeezelite-dante-bridge.conf
```

Example:

```bash
ZONE_NAME="Kitchen"
SERVER_ADDRESS="10.10.4.30"
SQUEEZELITE_MAC="02:11:22:33:44:55"
SERVICE_NAME="squeezelite-kitchen.service"
SAMPLE_RATE="48000"
AUDIO_FORMAT="WAV"
CONSOLE_AUTO_LOGIN="true"
```

A template is available at:

```text
config/squeezelite-dante-bridge.conf.example
```

Installation information is written to:

```text
/opt/squeezelite-dante-bridge/info.txt
```

---

## 🔊 ALSA configuration

The installer writes this to `/root/.asoundrc` inside the LXC:

```conf
pcm.inferno {
    type inferno
    device "SqueezelitePlayer"
    format S32_LE
    rate 48000
    channels 2
}

ctl.inferno {
    type inferno
}
```

The `device` value is set to the zone name chosen during installation.

---

## 🧩 Squeezelite service

The installer creates a zone-specific systemd service:

```text
/etc/systemd/system/squeezelite-<zone>.service
```

Example:

```ini
[Unit]
Description=Squeezelite Dante Player - Kitchen
After=statime.service network-online.target
Wants=network-online.target
Requires=statime.service

[Service]
Type=simple
Environment=INFERNO_NAME=Kitchen
ExecStart=/usr/bin/squeezelite -n Kitchen -o inferno -r 48000 -b 4096:1024 -u h:48000 -a 256:4::0 -m 02:11:22:33:44:55
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
```

If a Music Assistant/LMS server address is configured, the service also includes:

```text
-s <server-address>
```

---

## 🎚️ Important Squeezelite options

The working setup uses:

```bash
-o inferno
-r 48000
-b 4096:1024
-u h:48000
-a 256:4::0
```

| Option | Purpose |
|---|---|
| `-o inferno` | Sends audio to the ALSA `inferno` output |
| `-r 48000` | Forces 48 kHz sample rate for Dante |
| `-b 4096:1024` | Sets stream/output buffer sizes |
| `-u h:48000` | Enables high-quality resampling to 48 kHz |
| `-a 256:4::0` | ALSA output tuning |
| `-m` | Sets a stable unique MAC address for the player |
| `-n` | Sets the Squeezelite player name |
| `-s` | Optional Music Assistant/LMS server address |

---

## 🏠 Multiple zones

Recommended setup is one LXC container per zone.

Example:

```text
CT 151: Kitchen
CT 152: Bathroom
CT 153: Diningroom
CT 154: Guestroom
```

Each zone should have:

- Unique CTID
- Unique hostname
- Unique zone name
- Unique Squeezelite MAC address

Example install commands:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/marcusisdahl/squeezelite-dante-bridge/main/proxmox-install.sh)" -- \
  --ctid 151 \
  --hostname dante-kitchen \
  --zone Kitchen
```

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/marcusisdahl/squeezelite-dante-bridge/main/proxmox-install.sh)" -- \
  --ctid 152 \
  --hostname dante-bathroom \
  --zone Bathroom
```

---

## 🌐 Dante Controller

After installation:

1. Open Dante Controller.
2. Wait for the transmitter to appear.
3. Look for the zone name chosen during installation, for example `Kitchen`.
4. Route the transmitter channels to your receiver, DSP, or amplifier.
5. Confirm clocking and sample rate.

---

## 🔌 Network requirements

Dante is sensitive to multicast, timing, and network discovery.

Recommended:

- Use wired Ethernet.
- Keep Dante devices on the same VLAN if possible.
- Avoid Wi-Fi for Dante audio.
- Make sure multicast is allowed between the Dante sender and receiver.
- Use Dante Controller to confirm that transmitters appear correctly.

If running across VLANs, make sure your network allows the required Dante discovery, timing, and audio traffic.

If Music Assistant discovery fails across VLANs, rerun the installer with a fixed server address or edit the config/service manually.

---

## ✅ Verification

Inside the LXC, useful checks are:

```bash
systemctl status statime.service
systemctl status squeezelite-*.service
aplay -L | grep -A5 inferno
cat /etc/squeezelite-dante-bridge.conf
cat /opt/squeezelite-dante-bridge/info.txt
```

The installer also performs basic health checks after installation.

---

## 🧯 Troubleshooting

### Dante transmitter does not appear

Check that the services are running:

```bash
systemctl status statime.service
systemctl status squeezelite-*.service
```

Also verify:

- The LXC is on the correct VLAN/network.
- Dante Controller can reach the LXC network.
- Multicast is allowed.
- The Dante receiver is online.
- The ALSA Inferno device exists.

### Squeezelite starts but no audio

Check available ALSA devices:

```bash
aplay -L
```

Confirm that `inferno` appears as an output.

Check the Squeezelite service:

```bash
cat /etc/systemd/system/squeezelite-*.service
journalctl -u squeezelite-*.service -f
```

### Music Assistant does not find the player

If auto-discovery does not work, use a fixed server address:

```bash
--server 10.10.4.30
```

Or edit the Squeezelite service manually and add:

```text
-s <music-assistant-or-lms-address>
```

Then reload and restart:

```bash
systemctl daemon-reload
systemctl restart squeezelite-*.service
```

### Wrong player name

The player name comes from the zone name.

Check:

```bash
cat /etc/squeezelite-dante-bridge.conf
cat /root/.asoundrc
cat /etc/systemd/system/squeezelite-*.service
```

---

## 🐧 Manual Debian install

For an existing Debian LXC/VM, use:

```bash
wget https://raw.githubusercontent.com/marcusisdahl/squeezelite-dante-bridge/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

The Proxmox installer is recommended for new deployments.

---

## 📝 Notes

This setup is based on a working homelab installation.

It may require adjustment depending on your network, Dante hardware, Proxmox configuration, and Inferno build path.

Use Dante Controller to confirm routing, device names, clock status, and sample rate.

---

## ⚖️ Disclaimer

This is not an official Dante, Audinate, Bose, Proxmox, Music Assistant, or Squeezelite guide. Use at your own risk.
