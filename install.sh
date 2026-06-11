#!/bin/bash
# =============================================================================
# install.sh — ColdVPN Installer (Mac)
# =============================================================================
# Sets up an always-on, self-hosted WireGuard VPN on your Mac. All Mac traffic
# is routed through your own WireGuard server (e.g. Oracle Cloud free tier).
# The tunnel comes up at boot on any network, and a menu-bar button lets you
# toggle it on/off.
#
# What it installs:
#   - Homebrew (if missing)
#   - wireguard-tools (via Homebrew)
#   - SwiftBar (menu-bar app)
#   - wireguardvpn-toggle.sh   → /usr/local/bin/   (on/off switch)
#   - com.wireguardvpn.plist   → /Library/LaunchDaemons/  (brings tunnel up at boot)
#   - wg0.conf                 → your WireGuard config dir
#   - sudoers rule             → /etc/sudoers.d/wireguardvpn  (toggle without password)
#   - coldvpn.5s.sh            → your SwiftBar plugins folder  (menu-bar button)
#
# You provide:
#   - Your server's IP and WireGuard public key
#
# Requirements:
#   - macOS (Apple Silicon or Intel)
#   - A running WireGuard server (see server/setup.sh)
#
# Usage:
#   ./install.sh
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
header() { echo ""; echo "${BLD}${BLU}── $1 ${RST}"; }
ok()     { echo "  ${GRN}✓${RST} $1"; }
info()   { echo "  ${YLW}→${RST} $1"; }
die()    { echo ""; echo "  ${RED}✗ Error: $1${RST}"; echo ""; exit 1; }

# Ask a question, store answer in a variable. Usage: ask VAR "Question" "default"
ask() {
    local var=$1 question=$2 default=$3
    echo ""
    if [ -n "$default" ]; then printf "  ${BLD}$question${RST} [${default}]: "
    else                       printf "  ${BLD}$question${RST}: "; fi
    read -r input
    if [ -z "$input" ] && [ -n "$default" ]; then eval "$var=\"$default\""
    else eval "$var=\"$input\""; fi
}

# =============================================================================
# STEP 0 — Welcome
# =============================================================================
clear
echo ""
echo "${BLD}  ColdVPN — Installer${RST}"
echo "  ────────────────────────────────────────"
echo "  An always-on, self-hosted WireGuard VPN"
echo "  for your Mac. Routes all traffic through"
echo "  your own server, on any network."
echo ""
echo "  You'll need your server's IP and public key."
echo ""
read -rp "  Press Enter to start..."

# =============================================================================
# STEP 1 — Check this is macOS
# =============================================================================
header "Step 1/13 — Checking system"

[ "$(uname)" != "Darwin" ] && die "This installer only supports macOS."
ok "macOS detected"

# Apple Silicon vs Intel — sets the Homebrew path everything else uses
if [ "$(uname -m)" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"; ok "Apple Silicon detected"
else
    BREW_PREFIX="/usr/local";    ok "Intel Mac detected"
fi

WG_BIN="$BREW_PREFIX/bin/wg"
WG_QUICK_BIN="$BREW_PREFIX/bin/wg-quick"
WG_CONF_DIR="$BREW_PREFIX/etc/wireguard"

# =============================================================================
# STEP 2 — Homebrew
# =============================================================================
header "Step 2/13 — Homebrew"

if command -v brew &>/dev/null; then
    ok "Homebrew already installed — skipping"
else
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ok "Homebrew installed"
fi

# =============================================================================
# STEP 3 — WireGuard tools
# =============================================================================
header "Step 3/13 — WireGuard tools"

if command -v wg &>/dev/null; then
    ok "wireguard-tools already installed — skipping"
else
    info "Installing wireguard-tools..."
    brew install wireguard-tools
    ok "wireguard-tools installed"
fi

# =============================================================================
# STEP 4 — SwiftBar (menu-bar app)
# =============================================================================
header "Step 4/13 — SwiftBar"

if [ -d "/Applications/SwiftBar.app" ]; then
    ok "SwiftBar already installed — skipping"
else
    info "Installing SwiftBar..."
    brew install --cask swiftbar
    ok "SwiftBar installed"
    info "Open SwiftBar once and choose a plugins folder before continuing"
    read -rp "  Press Enter once you've opened SwiftBar and set a plugins folder..."
fi

# =============================================================================
# STEP 5 — Generate your WireGuard keys
# =============================================================================
header "Step 5/13 — Generating your keys"

# Private key is generated here and only ever written into wg0.conf (root-only).
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

ok "Key pair generated"
echo ""
echo "  ${BLD}Your client public key:${RST}"
echo ""
echo "  ${BLU}${PUBLIC_KEY}${RST}"
echo ""

# =============================================================================
# STEP 6 — Add your key to the server
# =============================================================================
header "Step 6/13 — Add your key to the server"

echo "  Add the public key above to your server's wg0.conf."
echo ""
echo "  SSH into your server and run:"
echo "  ${YLW}sudo nano /etc/wireguard/wg0.conf${RST}"
echo ""
echo "  Add this at the bottom:"
echo "  ${YLW}[Peer]"
echo "  PublicKey = ${PUBLIC_KEY}"
echo "  AllowedIPs = 10.8.0.2/32${RST}"
echo ""
echo "  Then restart WireGuard on the server:"
echo "  ${YLW}sudo systemctl restart wg-quick@wg0${RST}"
echo ""
read -rp "  Press Enter once you've done this..."

# =============================================================================
# STEP 7 — Your server details
# =============================================================================
header "Step 7/13 — Your server details"

ask SERVER_IP     "Server IP address (e.g. 203.0.113.10)" ""
ask SERVER_PORT   "Server WireGuard port"                 "443"
ask SERVER_PUBKEY "Server public key"                     ""
ask CLIENT_ADDR   "Your VPN address (inside the tunnel)"  "10.8.0.2"
ask DNS_SERVER    "DNS server to use"                     "1.1.1.1"

[ -z "$SERVER_IP" ]     && die "Server IP cannot be empty"
[ -z "$SERVER_PUBKEY" ] && die "Server public key cannot be empty"

ok "Server details collected"

# =============================================================================
# STEP 8 — Create wg0.conf
# =============================================================================
header "Step 8/13 — Creating WireGuard config"

sudo mkdir -p "$WG_CONF_DIR"

# AllowedIPs 0.0.0.0/0 = send all traffic through the tunnel.
sudo tee "$WG_CONF_DIR/wg0.conf" > /dev/null << EOF
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address = ${CLIENT_ADDR}/32
DNS = ${DNS_SERVER}

[Peer]
PublicKey = ${SERVER_PUBKEY}
Endpoint = ${SERVER_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

sudo chmod 600 "$WG_CONF_DIR/wg0.conf"
ok "wg0.conf created at $WG_CONF_DIR/wg0.conf"

# =============================================================================
# STEP 9 — Install the toggle script
# =============================================================================
header "Step 9/13 — Installing the toggle script"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)/client"
TOGGLE=/usr/local/bin/wireguardvpn-toggle.sh

# Must be root-owned and not user-writable — that lock is what makes the
# passwordless sudoers rule (Step 11) safe.
sudo cp "$SCRIPT_DIR/wireguardvpn-toggle.sh" "$TOGGLE"
sudo chown root:wheel "$TOGGLE"
sudo chmod 755 "$TOGGLE"

ok "wireguardvpn-toggle.sh → $TOGGLE"

# =============================================================================
# STEP 10 — Install the LaunchDaemon (brings the tunnel up at boot)
# =============================================================================
header "Step 10/13 — Installing the boot service"

PLIST=/Library/LaunchDaemons/com.wireguardvpn.plist
sudo cp "$SCRIPT_DIR/com.wireguardvpn.plist" "$PLIST"
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"

# Load it now so the tunnel comes up; it will also start on every boot.
sudo launchctl bootstrap system "$PLIST" 2>/dev/null || true

ok "Boot service installed and loaded"
info "Tunnel will come up automatically at boot"

# =============================================================================
# STEP 11 — Configure sudoers (toggle without a password)
# =============================================================================
header "Step 11/13 — Configuring sudoers"

# Lets the menu-bar button run the toggle script without a password prompt.
# Scoped to ONLY that one script, for the current user.
SUDOERS_FILE=/etc/sudoers.d/wireguardvpn
echo "$(whoami) ALL=(root) NOPASSWD: $TOGGLE" | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chown root:wheel "$SUDOERS_FILE"
sudo chmod 440 "$SUDOERS_FILE"

ok "Sudoers rule added"

# =============================================================================
# STEP 12 — Menu-bar button
# =============================================================================
header "Step 12/13 — Menu-bar button"

DEFAULT_PLUGINS="$HOME/swiftbar-plugins"
ask PLUGINS_DIR "SwiftBar plugins folder path" "$DEFAULT_PLUGINS"

mkdir -p "$PLUGINS_DIR"
cp "$SCRIPT_DIR/coldvpn.5s.sh" "$PLUGINS_DIR/coldvpn.5s.sh"
chmod +x "$PLUGINS_DIR/coldvpn.5s.sh"

ok "Menu-bar button installed → $PLUGINS_DIR/coldvpn.5s.sh"

# =============================================================================
# STEP 13 — Done
# =============================================================================
header "Step 13/13 — All done"

echo ""
echo "${GRN}${BLD}  ✓ ColdVPN installed!${RST}"
echo ""
echo "  What you got:"
echo "  • WireGuard config → $WG_CONF_DIR/wg0.conf"
echo "  • Toggle script    → $TOGGLE"
echo "  • Boot service     → $PLIST"
echo "  • Menu-bar button  → $PLUGINS_DIR/coldvpn.5s.sh"
echo ""
echo "  The 🟢/🔴 ColdVPN button in your menu bar turns the VPN on/off."
echo "  The tunnel also comes up by itself at boot."
echo ""
