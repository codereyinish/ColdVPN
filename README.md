# WireGuard Hotspot Mac

Automatically connects your Mac to your own private VPN server the moment you tether from your iPhone — and disconnects when you switch back to WiFi. No manual toggling. A menu bar widget shows your live data usage in real time.

---

## Why you'd want this

**You work remotely and tether frequently**
Your Mac traffic goes through your own server — not exposed on the carrier network. No VPN app subscription needed.

**You want to know exactly how much data you're using**
The menu bar widget tracks usage per session, per day, and all time. You always know how much you've consumed before hitting your limit.

**You're tired of manually connecting your VPN every time you hotspot**
This does it automatically. iPhone hotspot on → VPN up. Hotspot off → VPN down. You don't touch anything.

**You travel and use cellular data on your Mac**
Keep all your traffic private through your own server instead of relying on carrier infrastructure or public WiFi.

---

## What it looks like

```
WG ●  ↓8.33 MB  ↑47.60 MB          ← menu bar (live)
─────────────────────────────
🟢  Live   ↓8.33 MB   ↑47.60 MB  ▶
─────────────────────────────
📅  Today
   Session 9   19:24:46   ↓2.73 MB   ↑2.81 MB
   Session 8   19:04:19   ↓171 KB    ↑258 KB
   ▸ 7 earlier session(s)            ▶
📊  Day total  ↓20 MB    ↑77 MB     ▶
─────────────────────────────
📅  Yesterday (2026-05-27)  ↓181 MB  ↑41 MB  ▶
─────────────────────────────
🌐  All time   ↓201 MB   ↑119 MB    ▶
```

---

## How it works

```
iPhone hotspot on
      ↓
Mac detects network change
      ↓
WireGuard tunnel connects to your server
      ↓
All traffic routes through your private server
      ↓
iPhone hotspot off → tunnel disconnects, session saved
```

Your server can be a **free** Oracle Cloud instance — free forever within their always-free tier.

---

## Prerequisites

- Mac (Apple Silicon or Intel)
- [Homebrew](https://brew.sh)
- [SwiftBar](https://swiftbar.app) — free menu bar app runner
- Your own WireGuard server (Oracle Cloud free tier works great)

---

## Server Setup (Oracle Cloud — Free Forever)

1. Create an [Oracle Cloud account](https://cloud.oracle.com)
2. Launch a free Ubuntu 22.04 instance (VM.Standard.A1.Flex — 1 OCPU, 1GB RAM)
3. Open port **51820 UDP** in the instance security list
4. SSH into your server and run:

```bash
# Install WireGuard
apt update && apt install -y wireguard

# Generate server keys
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
chmod 600 /etc/wireguard/server_private.key

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# Create server config
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/server_private.key)
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = YOUR_CLIENT_PUBLIC_KEY
AllowedIPs = 10.0.0.2/32
EOF

# Start WireGuard
systemctl enable --now wg-quick@wg0

echo "Server public key: $(cat /etc/wireguard/server_public.key)"
```

---

## Mac Client Setup

### 1. Install WireGuard tools

```bash
brew install wireguard-tools
```

### 2. Generate your client keys

```bash
wg genkey | tee ~/.wg-client-private.key | wg pubkey > ~/.wg-client-public.key
cat ~/.wg-client-public.key   # paste this into your server's [Peer] section
```

### 3. Create your WireGuard config

```bash
sudo cp client/wg0.conf.example /opt/homebrew/etc/wireguard/wg0.conf
sudo nano /opt/homebrew/etc/wireguard/wg0.conf
# Fill in: PrivateKey, server PublicKey, server IP
```

### 4. Install scripts

```bash
sudo cp client/wireguard-hotspot.sh /usr/local/bin/wireguard-hotspot.sh
sudo cp client/wg-stats /usr/local/bin/wg-stats
sudo chmod +x /usr/local/bin/wireguard-hotspot.sh /usr/local/bin/wg-stats
```

### 5. Install the LaunchDaemon

```bash
sudo cp client/com.wireguard.hotspot.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.wireguard.hotspot.plist
```

### 6. Create log file

```bash
sudo touch /var/log/wg-usage.log
sudo chmod 644 /var/log/wg-usage.log
```

### 7. Allow passwordless sudo for WireGuard

```bash
sudo visudo
# Add:
# %admin ALL=(ALL) NOPASSWD: /opt/homebrew/bin/wg, /opt/homebrew/bin/wg-quick
```

### 8. Set up SwiftBar widget

1. Install [SwiftBar](https://swiftbar.app) and choose a plugins folder
2. Copy the plugin:
```bash
cp client/wg-stats.10s.sh ~/path/to/swiftbar-plugins/
chmod +x ~/path/to/swiftbar-plugins/wg-stats.10s.sh
```

---

## Terminal stats

```bash
wg-stats
```

---

## File reference

| File | Purpose |
|------|---------|
| `/opt/homebrew/etc/wireguard/wg0.conf` | WireGuard client config |
| `/usr/local/bin/wireguard-hotspot.sh` | Auto-connect/disconnect script |
| `/usr/local/bin/wg-stats` | Usage stats script |
| `/Library/LaunchDaemons/com.wireguard.hotspot.plist` | launchd daemon |
| `/var/log/wg-usage.log` | Session usage log |
| `/var/log/wireguard-hotspot.log` | Daemon activity log |

---

## License

MIT
