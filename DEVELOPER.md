# Developer Guide

This guide is for developers who want to understand, modify, or contribute
to this project. Every step that `install.sh` and `server/setup.sh` automate
is documented here manually — so you can run each piece independently,
tweak it, and understand exactly what's happening.

---

## Project structure

```
wg-hotspot-mac/
├── install.sh                         ← Mac client installer (convenience wrapper)
├── client/
│   ├── wireguard-hotspot.sh           ← auto connect/disconnect script
│   ├── wg-stats                       ← stats script (terminal + SwiftBar)
│   ├── wg-stats.10s.sh                ← SwiftBar plugin entry point
│   ├── wg0.conf.example               ← Mac WireGuard config template
│   └── com.wireguard.hotspot.plist    ← launchd daemon config
└── server/
    ├── setup.sh                       ← VPS server installer (convenience wrapper)
    └── wg0.conf.example               ← server WireGuard config template
```

`install.sh` and `server/setup.sh` do nothing magical —
they just run the steps below in order. You can skip them entirely
and follow this guide step by step.

---

## Part 1 — Server setup (run on your Ubuntu VPS)

### Step 1 — Install WireGuard

```bash
apt update && apt install -y wireguard wireguard-tools iptables
```

### Step 2 — Generate server key pair

```bash
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
chmod 600 /etc/wireguard/server_private.key

cat /etc/wireguard/server_public.key   # you'll need this for the Mac setup
```

### Step 3 — Find your network interface

```bash
ip route | grep default | awk '{print $5}'
# usually: eth0, ens3, enp0s3
```

### Step 4 — Enable IP forwarding

```bash
echo "net.ipv4.ip_forward=1"          >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p
```

### Step 5 — Create server config

```bash
cp server/wg0.conf.example /etc/wireguard/wg0.conf
nano /etc/wireguard/wg0.conf
# Fill in:
#   PrivateKey  → contents of /etc/wireguard/server_private.key
#   eth0        → your actual network interface from Step 3
#   PublicKey   → your Mac client public key (generated in Mac Step 2)
```

### Step 6 — Start WireGuard

```bash
systemctl enable wg-quick@wg0
systemctl start  wg-quick@wg0
systemctl status wg-quick@wg0   # verify it's running
```

### Step 7 — Open firewall port

```bash
# If ufw is active:
ufw allow 51820/udp

# Oracle Cloud: also open UDP 51820 in the web console
# Networking → VCN → Security Lists → Add Ingress Rule
```

---

## Part 2 — Mac client setup (run on your Mac)

### Step 1 — Install WireGuard tools

```bash
brew install wireguard-tools
```

### Step 2 — Generate client key pair

```bash
wg genkey | tee ~/.wg-private.key | wg pubkey > ~/.wg-public.key
cat ~/.wg-public.key   # paste this into your server's wg0.conf [Peer] section
```

### Step 3 — Add your public key to the server

On your server, add a `[Peer]` block to `/etc/wireguard/wg0.conf`:

```ini
[Peer]
PublicKey  = YOUR_MAC_PUBLIC_KEY
AllowedIPs = 10.0.0.2/32
```

Then reload:

```bash
systemctl restart wg-quick@wg0
```

### Step 4 — Create Mac WireGuard config

```bash
sudo cp client/wg0.conf.example /opt/homebrew/etc/wireguard/wg0.conf
sudo nano /opt/homebrew/etc/wireguard/wg0.conf
# Fill in:
#   PrivateKey → contents of ~/.wg-private.key
#   PublicKey  → your server's public key
#   Endpoint   → your server IP:51820
```

### Step 5 — Install scripts

```bash
sudo cp client/wireguard-hotspot.sh /usr/local/bin/wireguard-hotspot.sh
sudo cp client/wg-stats             /usr/local/bin/wg-stats
sudo chmod +x /usr/local/bin/wireguard-hotspot.sh
sudo chmod +x /usr/local/bin/wg-stats
```

### Step 6 — Install LaunchDaemon

```bash
# LaunchDaemon watches for network changes and fires wireguard-hotspot.sh
sudo cp client/com.wireguard.hotspot.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.wireguard.hotspot.plist
```

### Step 7 — Create log file

```bash
sudo touch /var/log/wg-usage.log
sudo touch /var/log/wireguard-hotspot.log
sudo chmod 644 /var/log/wg-usage.log
sudo chmod 644 /var/log/wireguard-hotspot.log
```

### Step 8 — Configure sudoers

```bash
# Allows wg and wg-quick to run without password prompt
# Required for: live stats, auto connect/disconnect
echo "%admin ALL=(ALL) NOPASSWD: /opt/homebrew/bin/wg, /opt/homebrew/bin/wg-quick" \
    | sudo tee /etc/sudoers.d/wireguard
sudo chmod 440 /etc/sudoers.d/wireguard
```

### Step 9 — Install SwiftBar plugin

```bash
# Install SwiftBar if not already installed
brew install --cask swiftbar

# Copy plugin to your SwiftBar plugins folder
cp client/wg-stats.10s.sh ~/swiftbar-plugins/wg-stats.10s.sh
chmod +x ~/swiftbar-plugins/wg-stats.10s.sh
```

### Step 10 — Test

```bash
# Manually test the tunnel
sudo wg-quick up wg0
wg-stats                   # should show live session
sudo wg-quick down wg0

# Test auto-connect by connecting to iPhone hotspot
# Should auto-connect within ~10 seconds
```

---

## How each script works

### `client/wireguard-hotspot.sh`
Fired by launchd on every network change. Checks if the current
gateway is `172.20.10.1` (iPhone hotspot). If yes → brings wg0 up.
If no → saves session stats to log → brings wg0 down.

### `client/wg-stats`
Reads `/var/log/wg-usage.log` and live kernel stats from `wg show all dump`.
Two modes: `wg-stats` (terminal) and `wg-stats --bar` (SwiftBar format).

### `client/wg-stats.10s.sh`
Two lines. Just calls `wg-stats --bar`. SwiftBar reads this file
every 10 seconds and renders the output as a menu bar widget.

### `client/com.wireguard.hotspot.plist`
launchd configuration. Watches `/Library/Preferences/SystemConfiguration`
for changes (network events) and fires `wireguard-hotspot.sh`.

### `server/setup.sh`
Runs all Part 1 steps above automatically on the VPS.

---

## Contributing

1. Fork the repo
2. Make your changes to the scripts in `client/` or `server/`
3. Test manually using the steps above
4. Open a pull request with a description of what you changed and why

### Testing a change to wg-stats

```bash
# Edit the script
nano client/wg-stats

# Apply and test immediately
sudo cp client/wg-stats /usr/local/bin/wg-stats
wg-stats                   # test terminal mode
wg-stats --bar             # test SwiftBar mode
```

### Testing a change to wireguard-hotspot.sh

```bash
nano client/wireguard-hotspot.sh
sudo cp client/wireguard-hotspot.sh /usr/local/bin/wireguard-hotspot.sh

# Run manually to test (same as launchd would run it)
sudo /usr/local/bin/wireguard-hotspot.sh
```
