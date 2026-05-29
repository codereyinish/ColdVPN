# WireGuard Hotspot Bypass for Mac

Automatically routes all traffic through your own WireGuard VPN whenever your Mac connects to an iPhone hotspot — bypassing AT&T's hotspot data detection.

## How it works

AT&T detects hotspot usage by checking the TTL (Time To Live) value of outgoing packets:
- iPhone traffic: TTL = 64
- Hotspot traffic: TTL = 63 (iPhone decrements it by 1)

This tool sets your Mac's TTL to **65** before traffic leaves. The iPhone decrements it to **64** — AT&T sees it as regular phone traffic.

The same fix is applied to IPv6 Hop Limit.

```
iPhone Hotspot → Mac (TTL=65) → WireGuard Tunnel → Oracle VPS → Internet
                                 AT&T sees TTL=64 ✓ (looks like phone)
```

## Features

- ✅ Auto-connects WireGuard when iPhone hotspot is detected
- ✅ Auto-disconnects when hotspot is gone
- ✅ Fixes both IPv4 TTL and IPv6 Hop Limit
- ✅ SwiftBar menu bar widget with live stats
- ✅ Per-session usage tracking
- ✅ Daily and all-time totals

## Prerequisites

- Mac with Apple Silicon or Intel
- [Homebrew](https://brew.sh)
- [SwiftBar](https://swiftbar.app) (for the menu bar widget)
- Your own WireGuard server (see Server Setup below)

## Server Setup (Oracle Cloud Free Tier)

Oracle Cloud offers a **free forever** VPS — no charges if you stay within limits.

1. Create an [Oracle Cloud account](https://cloud.oracle.com)
2. Create a free Ubuntu 22.04 instance (VM.Standard.A1.Flex — ARM, 1 OCPU, 1GB RAM)
3. Open port **51820 UDP** in the instance's security list
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

# Show your server public key (you'll need this for the Mac setup)
echo "Server public key: $(cat /etc/wireguard/server_public.key)"
```

## Mac Client Setup

### 1. Install dependencies

```bash
brew install wireguard-tools
```

### 2. Generate your client keys

```bash
wg genkey | tee ~/.wg-client-private.key | wg pubkey > ~/.wg-client-public.key
cat ~/.wg-client-public.key   # add this to your server's wg0.conf [Peer] section
```

### 3. Add your client to the server

On your server, add to `/etc/wireguard/wg0.conf`:
```ini
[Peer]
PublicKey = YOUR_CLIENT_PUBLIC_KEY
AllowedIPs = 10.0.0.2/32
```
Then reload: `wg addconf wg0 <(wg-quick strip wg0)` or restart the service.

### 4. Create client WireGuard config

```bash
sudo cp client/wg0.conf.example /opt/homebrew/etc/wireguard/wg0.conf
sudo nano /opt/homebrew/etc/wireguard/wg0.conf
# Fill in: PrivateKey, server PublicKey, server IP
```

### 5. Install the scripts

```bash
sudo cp client/wireguard-hotspot.sh /usr/local/bin/wireguard-hotspot.sh
sudo cp client/wg-stats /usr/local/bin/wg-stats
sudo chmod +x /usr/local/bin/wireguard-hotspot.sh /usr/local/bin/wg-stats
```

### 6. Set up the LaunchDaemon (auto-start on network change)

```bash
sudo cp client/com.wireguard.hotspot.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.wireguard.hotspot.plist
```

### 7. Set up log file

```bash
sudo touch /var/log/wg-usage.log
sudo chmod 644 /var/log/wg-usage.log
```

### 8. Allow passwordless sudo for WireGuard commands

```bash
sudo visudo
# Add this line:
# %admin ALL=(ALL) NOPASSWD: /opt/homebrew/bin/wg, /opt/homebrew/bin/wg-quick
```

### 9. Install the SwiftBar widget

1. Download and install [SwiftBar](https://swiftbar.app)
2. Set your plugins folder when SwiftBar asks
3. Copy the plugin:
```bash
cp client/wg-stats.10s.sh ~/path/to/your/swiftbar-plugins/
chmod +x ~/path/to/your/swiftbar-plugins/wg-stats.10s.sh
```

## Usage

Once installed, it works automatically:
- Connect to iPhone hotspot → tunnel comes up in ~5–10 seconds
- Disconnect → session stats are saved, tunnel goes down
- Click the menu bar widget to see live usage, per-session stats, and totals

## Terminal stats

```bash
wg-stats
```

## File locations

| File | Purpose |
|------|---------|
| `/opt/homebrew/etc/wireguard/wg0.conf` | WireGuard client config |
| `/usr/local/bin/wireguard-hotspot.sh` | Auto-connect script |
| `/usr/local/bin/wg-stats` | Stats script |
| `/Library/LaunchDaemons/com.wireguard.hotspot.plist` | launchd daemon |
| `/var/log/wg-usage.log` | Session usage log |
| `/var/log/wireguard-hotspot.log` | Daemon activity log |

## How the auto-connect works

```
Network change detected
        ↓
launchd fires wireguard-hotspot.sh
        ↓
Is gateway 172.20.10.1? (iPhone hotspot)
   YES → wg-quick up wg0
   NO  → save session stats → wg-quick down wg0
```

## License

MIT
