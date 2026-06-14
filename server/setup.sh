#!/bin/bash
# =============================================================================
# server/setup.sh — WireGuard Server Setup
# =============================================================================
# What this script does:
#   Sets up a WireGuard VPN server on a Linux VPS (Ubuntu 20.04/22.04).
#   Designed for Oracle Cloud Free Tier but works on any Ubuntu VPS.
#
# What it installs/configures:
#   - wireguard + wireguard-tools (via apt)
#   - Server key pair (private key stays on server, never leaves)
#   - /etc/wireguard/wg0.conf (server config)
#   - IP forwarding (lets server route traffic for VPN clients)
#   - iptables NAT rules (routes client traffic to the internet)
#   - wg-quick@wg0 systemd service (auto-starts on reboot)
#
# What the user needs to provide:
#   - Nothing. Runs unattended with fixed defaults. The Mac client peer is NOT
#     added here — the Mac's install.sh registers it over SSH after this runs.
#
# What the user gets at the end:
#   - A dual-stack (IPv4 + IPv6) wg0 interface, up and enabled at boot.
#
# Requirements:
#   - Ubuntu 20.04 or 22.04
#   - Root or sudo access
#   - Port 443 UDP open in your cloud firewall (Oracle security list)
#
# Usage:
#   bash setup.sh
#   or:
#   curl -fsSL https://raw.githubusercontent.com/codereyinish/ColdVPN/main/server/setup.sh | bash
#
# Author: github.com/codereyinish
# =============================================================================

set -e  # exit immediately if any command fails

# =============================================================================
# COLORS
# =============================================================================
RED=$'\033[91m'
GRN=$'\033[92m'
YLW=$'\033[93m'
BLU=$'\033[96m'
BLD=$'\033[1m'
RST=$'\033[0m'

# =============================================================================
# HELPERS
# =============================================================================

header() {
    echo ""
    echo "${BLD}${BLU}── $1 ${RST}"
}

ok() {
    echo "  ${GRN}✓${RST} $1"
}

info() {
    echo "  ${YLW}→${RST} $1"
}

die() {
    echo ""
    echo "  ${RED}✗ Error: $1${RST}"
    echo ""
    exit 1
}

ask() {
    local var=$1
    local question=$2
    local default=$3
    echo ""
    if [ -n "$default" ]; then
        printf "  ${BLD}$question${RST} [${default}]: "
    else
        printf "  ${BLD}$question${RST}: "
    fi
    read -r input
    if [ -z "$input" ] && [ -n "$default" ]; then
        eval "$var=\"$default\""
    else
        eval "$var=\"$input\""
    fi
}

# =============================================================================
# STEP 0 — Welcome
# =============================================================================
echo ""
echo "${BLD}  ColdVPN — Server Setup${RST}"
echo "  ────────────────────────────────────────"
echo "  Sets up WireGuard on this Ubuntu server. Runs unattended — no prompts."
echo "  (Your Mac's install.sh runs this for you on a fresh server; you can also"
echo "   run it by hand.)"

# =============================================================================
# STEP 1 — Check this is Linux and running as root
# =============================================================================
header "Step 1/10 — Checking system"

if [ "$(uname)" != "Linux" ]; then
    die "This script must run on Linux (Ubuntu). Run it on your VPS, not your Mac."
fi
ok "Linux detected"

# Check running as root — required for apt, wg, systemctl
if [ "$EUID" -ne 0 ]; then
    die "Please run as root: sudo bash setup.sh"
fi
ok "Running as root"

# Detect Ubuntu version
if ! command -v apt &>/dev/null; then
    die "This script requires apt (Ubuntu/Debian). Other distros not supported yet."
fi

UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
ok "Ubuntu $UBUNTU_VERSION detected"

# =============================================================================
# STEP 2 — Update packages and install WireGuard
# =============================================================================
header "Step 2/10 — Installing WireGuard"

# noninteractive so apt never stops for a dialog when run unattended over SSH
export DEBIAN_FRONTEND=noninteractive

info "Updating package list..."
apt update -qq

info "Installing wireguard..."
apt install -y wireguard wireguard-tools iptables

ok "WireGuard installed"

# =============================================================================
# STEP 3 — Generate server key pair
# =============================================================================
header "Step 3/10 — Generating server keys"

# The server private key is the ANCHOR: if it ever changes, every client's
# [Peer] goes stale and the handshake breaks. So reuse an existing key, and only
# generate one when the box is truly fresh — this keeps re-runs domino-proof.
mkdir -p /etc/wireguard
if [ -f /etc/wireguard/server.key ]; then
    SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server.key)
    ok "Reusing existing server key (kept intact)"
elif [ -f /etc/wireguard/wg0.conf ] && grep -q '^PrivateKey' /etc/wireguard/wg0.conf; then
    # older install without server.key — recover the key from the live config
    SERVER_PRIVATE_KEY=$(grep '^PrivateKey' /etc/wireguard/wg0.conf | awk '{print $3}')
    ok "Recovered existing server key from wg0.conf (kept intact)"
else
    SERVER_PRIVATE_KEY=$(wg genkey)
    ok "Server key pair generated (fresh server)"
fi
# Persist the key on its own so future runs always find it.
echo "$SERVER_PRIVATE_KEY" > /etc/wireguard/server.key
chmod 600 /etc/wireguard/server.key
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
info "Private key stays on this server — never share it"

# =============================================================================
# STEP 4 — Detect network interface
# =============================================================================
header "Step 4/10 — Detecting network interface"

# Auto-detect the main outbound network interface
# On Oracle Cloud this is usually ens3 or enp0s3 (not eth0)
# This is needed for iptables NAT rules — routes VPN traffic to internet
NET_IF=$(ip route | grep '^default' | awk '{print $5}' | head -1)

if [ -z "$NET_IF" ]; then
    die "Could not detect network interface. Check: ip route"
fi

ok "Network interface: $NET_IF"

# =============================================================================
# STEP 5 — Enable IP forwarding
# =============================================================================
header "Step 5/10 — Enabling IP forwarding"

# IP forwarding allows the server to route packets from VPN clients
# to the internet — without this, clients can connect but can't browse
echo "net.ipv4.ip_forward=1"            >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1"   >> /etc/sysctl.conf
sysctl -p &>/dev/null

ok "IPv4 and IPv6 forwarding enabled"

# =============================================================================
# STEP 6 — Collect config from user
# =============================================================================
header "Step 6/10 — Server configuration"

# Non-interactive: fixed defaults, no prompts. The Mac client peer is NOT added
# here — the Mac's install.sh registers it over SSH after this runs. So wg0 is
# created with the [Interface] only.
LISTEN_PORT="443"
SERVER_ADDR="10.8.0.1"             # server's IPv4 inside the tunnel
SERVER_ADDR6="fd86:ea04:1115::1"   # server's IPv6 (private ULA) inside the tunnel

ok "port ${LISTEN_PORT}, tunnel ${SERVER_ADDR} / ${SERVER_ADDR6}"

# =============================================================================
# STEP 7 — Create /etc/wireguard/wg0.conf
# =============================================================================
header "Step 7/10 — Creating server config"

# PostUp/PostDown: the OS firewall rules a NAT gateway needs (IPv4 + IPv6).
# Oracle's Ubuntu image ships a restrictive default firewall — BOTH the INPUT and
# FORWARD chains end in "REJECT ... icmp-host-prohibited". So we open three things,
# inserting with -I ... 1 (at the TOP), NOT -A (append), so each ACCEPT sits
# ABOVE those REJECTs:
#   1. INPUT, udp dport = listen port — accept WireGuard's own port, or the
#      handshake is REJECTed before WireGuard ever sees it. (The cloud Security
#      List opening 443 is NOT enough — the OS firewall blocks it too.)
#   2. FORWARD -i wg0            — client → internet.
#   3. FORWARD -o wg0 ESTABLISHED,RELATED — the RETURN traffic back to clients;
#      without it, replies hit the REJECT and clients get no internet.
#   + MASQUERADE — rewrite the source IP so the internet sees the server.
# (Both #1 and #3 were found missing during a fresh-server test — they're required
#  on a stock Oracle image; without them the tunnel handshakes but passes nothing.)
#
# No [Peer] block — install.sh on the Mac adds the client peer over SSH.
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${SERVER_ADDR}/24, ${SERVER_ADDR6}/64
ListenPort = ${LISTEN_PORT}
PostUp   = iptables -I INPUT 1 -p udp --dport ${LISTEN_PORT} -j ACCEPT; iptables -I FORWARD 1 -i wg0 -j ACCEPT; iptables -I FORWARD 1 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o ${NET_IF} -j MASQUERADE; ip6tables -I FORWARD 1 -i wg0 -j ACCEPT; ip6tables -I FORWARD 1 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT; ip6tables -t nat -A POSTROUTING -o ${NET_IF} -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport ${LISTEN_PORT} -j ACCEPT; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o ${NET_IF} -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -D FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT; ip6tables -t nat -D POSTROUTING -o ${NET_IF} -j MASQUERADE
EOF

chmod 600 /etc/wireguard/wg0.conf
ok "Server config created at /etc/wireguard/wg0.conf"

# =============================================================================
# STEP 8 — Enable and start WireGuard
# =============================================================================
header "Step 8/10 — Starting WireGuard"

# Enable: auto-starts on every reboot
# Start: brings the tunnel up right now
systemctl enable wg-quick@wg0
systemctl start  wg-quick@wg0

ok "WireGuard service started"
ok "Auto-starts on reboot"

# Verify it's running
if systemctl is-active --quiet wg-quick@wg0; then
    ok "WireGuard is running ✓"
else
    die "WireGuard failed to start. Check: journalctl -u wg-quick@wg0"
fi

# =============================================================================
# STEP 9 — Open firewall (if ufw is active)
# =============================================================================
header "Step 9/10 — Firewall"

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow "$LISTEN_PORT"/udp
    ok "ufw: port $LISTEN_PORT UDP opened"
else
    info "ufw not active — skipping"
fi

# Oracle Cloud / AWS users: you MUST also open the port in your
# cloud provider's security list/security group (web console)
# Oracle: Networking → VCN → Security Lists → Add Ingress Rule
#   Protocol: UDP, Port: 443
echo ""
echo "  ${YLW}⚠️  Cloud firewall reminder:${RST}"
echo "  If you're on Oracle Cloud, you must also open UDP $LISTEN_PORT"
echo "  in the Oracle web console:"
echo "  Networking → VCN → Security Lists → Add Ingress Rule"
echo "  Protocol: UDP  |  Port: $LISTEN_PORT"

# =============================================================================
# STEP 10 — Done — show server public key
# =============================================================================
header "Step 10/10 — Setup complete"

echo ""
echo "${GRN}${BLD}  ✓ Server setup complete!${RST}"
echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │  Your server public key (copy this):        │"
echo "  │                                             │"
echo "  │  ${BLU}${SERVER_PUBLIC_KEY}${RST}"
echo "  │                                             │"
echo "  │  You'll need this when running install.sh   │"
echo "  │  on your Mac.                               │"
echo "  └─────────────────────────────────────────────┘"
echo ""
echo "  Server details for your Mac install:"
echo "  ${YLW}  Server IP:   $(curl -s ifconfig.me 2>/dev/null || echo 'check your VPS IP')${RST}"
echo "  ${YLW}  Server port: $LISTEN_PORT${RST}"
echo "  ${YLW}  Public key:  $SERVER_PUBLIC_KEY${RST}"
echo ""
echo "  Now run install.sh on your Mac."
echo ""
