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
#   - coldvpn-toggle.sh   → /usr/local/bin/   (on/off switch)
#   - com.coldvpn.plist   → /Library/LaunchDaemons/  (brings tunnel up at boot)
#   - wg0.conf                 → your WireGuard config dir
#   - sudoers rule             → /etc/sudoers.d/coldvpn  (toggle without password)
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
DIM=$'\033[90m'   # gray — for "where to find this" hints
RST=$'\033[0m'

# =============================================================================
# HELPERS
# =============================================================================
header() { echo ""; echo "${BLD}${BLU}── $1 ${RST}"; }
ok()     { echo "  ${GRN}✓${RST} $1"; }
info()   { echo "  ${YLW}→${RST} $1"; }
die()    { echo ""; echo "  ${RED}✗ Error: $1${RST}"; echo ""; exit 1; }

# ask() — interactive prompt with a grey ghost-default. It's long and hand-rolled
# for bash 3.2, so it lives in its own file. See
# client/decisions/07-bash-3.2-not-homebrew.md for why we target stock bash
# instead of requiring Homebrew bash.
source "$(cd "$(dirname "$0")" && pwd)/client/lib/prompt.sh"

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
# STEP 1.5 — Clear any previous install (always start clean)
# =============================================================================
# This installer always runs the full flow from the top — it regenerates keys
# and re-asks for your server details every time. So first we wipe any prior
# install, under BOTH the current name (com.coldvpn) and the OLD name
# (com.wireguardvpn) used before the rename. Without this, a previous daemon
# would linger and fight the freshly-installed one over the wg0 interface.
header "Step 1.5/13 — Clearing any previous install"

sudo "$WG_QUICK_BIN" down wg0 2>/dev/null || true   # drop any live tunnel first

for LABEL in com.coldvpn com.wireguardvpn; do
    PLIST="/Library/LaunchDaemons/${LABEL}.plist"
    if [ -f "$PLIST" ]; then
        info "Removing previous '$LABEL' daemon"
        sudo launchctl bootout  system "$PLIST"      2>/dev/null || true
        sudo launchctl disable "system/${LABEL}"     2>/dev/null || true
        sudo rm -f "$PLIST"
    fi
done

# Old-named toggle + sudoers (the new-named ones get overwritten in Steps 9/11).
sudo rm -f /usr/local/bin/wireguardvpn-toggle.sh /etc/sudoers.d/wireguardvpn

ok "Previous install cleared (if any)"

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
# STEP 6 — Your server details
# =============================================================================
# Collected up front; the installer then SSHes into the server itself (Step 7)
# to finish the key exchange — no manual copy/paste. The server's public key is
# NOT asked here: it's fetched over that SSH connection.
header "Step 6/13 — Your server details"

echo "  The installer will SSH into the server to finish setup automatically."
echo ""
echo "  ${DIM}Where to find these:${RST}"
echo "  ${DIM}• Server IP → Oracle console → Compute → Instances → your instance →${RST}"
echo "  ${DIM}             'Public IP address'  (or the line setup.sh printed at the end)${RST}"
echo "  ${DIM}• SSH user  → 'ubuntu' on Oracle's Ubuntu image — just press Enter${RST}"
echo "  ${DIM}• Port / VPN address / DNS → defaults are correct, just press Enter${RST}"
echo ""

ask SERVER_IP   "Server IP address (e.g. 203.0.113.10)" ""
ask SSH_USER    "SSH username on the server"            "ubuntu"
ask SERVER_PORT "Server WireGuard port"                 "443"
ask CLIENT_ADDR "Your VPN address (inside the tunnel)"  "10.8.0.2"
ask DNS_SERVER  "DNS server to use"                     "1.1.1.1"

[ -z "$SERVER_IP" ] && die "Server IP cannot be empty"

ok "Server details collected"

# =============================================================================
# STEP 7 — Register this Mac on the server (over SSH)
# =============================================================================
# Decision 06: automate the key handoff in ONE step. SSH in with YOUR key,
# fetch the server's public key, register this Mac as a peer (REPLACING any old
# peer so re-runs are idempotent — single-client design).
#
# SECURITY (decisions 05 & 06): we deliberately DO NOT pass
# StrictHostKeyChecking=no. Host-key verification stays ON — a first-ever
# connect prompts here (fine, the installer is interactive); a known host
# verifies silently.
header "Step 7/13 — Registering this Mac on the server"

SSH_DEST="${SSH_USER}@${SERVER_IP}"
SSH_OPTS="-o ConnectTimeout=10"

# narration helper — prints an arrow line and pauses briefly so the flow is
# followable rather than a wall of instant text.
narrate() { echo "  ${BLU}→${RST} $1"; sleep 0.4; }

echo "  ${BLD}┌─ over SSH ─────────────────────────────────────────${RST}"
narrate "ssh ${SSH_DEST}  — connecting to your server..."
if ssh $SSH_OPTS "$SSH_DEST" 'true'; then
    ok "you're on the server"

    narrate "reading the server's identity (its public key)..."
    SERVER_PUBKEY=$(ssh $SSH_OPTS "$SSH_DEST" 'sudo wg show wg0 public-key' 2>/dev/null | tr -d '[:space:]')
    [ -z "$SERVER_PUBKEY" ] && die "Couldn't read the server's public key (is WireGuard running there?)."
    echo "       server key   ${GRN}<--${RST} ${BLU}${SERVER_PUBKEY}${RST}"

    narrate "handing the server THIS Mac's public key..."
    echo "       your key     ${GRN}-->${RST} ${BLU}${PUBLIC_KEY}${RST}"

    narrate "updating /etc/wireguard/wg0.conf on the server..."
    ssh $SSH_OPTS "$SSH_DEST" "sudo bash -s" <<REMOTE
set -e
cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.bak
# keep the [Interface] section (everything before the first [Peer]), drop old peers
awk '/^\[Peer\]/{exit} {print}' /etc/wireguard/wg0.conf.bak | grep -v '^[[:space:]]*\$' > /etc/wireguard/wg0.conf.new
printf '\n[Peer]\nPublicKey = %s\nAllowedIPs = %s/32\n' '$PUBLIC_KEY' '$CLIENT_ADDR' >> /etc/wireguard/wg0.conf.new
mv /etc/wireguard/wg0.conf.new /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf
systemctl restart wg-quick@wg0
REMOTE

    narrate "server's [Peer] block is now:"
    ssh $SSH_OPTS "$SSH_DEST" 'sudo awk "/\[Peer\]/{p=1} p" /etc/wireguard/wg0.conf' 2>/dev/null | sed "s/^/       ${YLW}|${RST} /"
    ok "server updated + WireGuard restarted"
    echo "  ${BLD}└────────────────────────────────────────────────────${RST}"
else
    echo "  ${BLD}└─ couldn't SSH in — manual fallback ────────────────${RST}"
    info "Do it by hand instead:"
    echo "  ${BLD}1.${RST} ${YLW}ssh ${SSH_DEST}${RST}"
    echo "  ${BLD}2.${RST} ${YLW}sudo nano /etc/wireguard/wg0.conf${RST}"
    echo "  ${BLD}3.${RST} Replace the existing [Peer] (or add one) with:"
    echo "       ${YLW}[Peer]"
    echo "       PublicKey = ${PUBLIC_KEY}"
    echo "       AllowedIPs = ${CLIENT_ADDR}/32${RST}"
    echo "  ${BLD}4.${RST} Save, then ${YLW}sudo systemctl restart wg-quick@wg0${RST}"
    echo ""
    ask SERVER_PUBKEY "Now paste the server's public key (sudo wg show wg0 public-key)" ""
    [ -z "$SERVER_PUBKEY" ] && die "Server public key cannot be empty"
    read -rp "  Done on the server? Press Enter to finish..."
fi

# =============================================================================
# STEP 8 — Write your Mac's WireGuard config
# =============================================================================
header "Step 8/13 — Writing your Mac's WireGuard config"

echo "  ${BLU}→${RST} back on your Mac — writing ${WG_CONF_DIR}/wg0.conf"

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
ok "wg0.conf written"

# Show what was written (private key hidden).
echo "       ${YLW}|${RST} [Interface]"
echo "       ${YLW}|${RST} PrivateKey = ${BLD}(hidden)${RST}"
echo "       ${YLW}|${RST} Address    = ${CLIENT_ADDR}/32"
echo "       ${YLW}|${RST} DNS        = ${DNS_SERVER}"
echo "       ${YLW}|${RST} [Peer]"
echo "       ${YLW}|${RST} PublicKey  = ${SERVER_PUBKEY}"
echo "       ${YLW}|${RST} Endpoint   = ${SERVER_IP}:${SERVER_PORT}"
echo "       ${YLW}|${RST} AllowedIPs = 0.0.0.0/0"

# =============================================================================
# STEP 9 — Install the toggle script
# =============================================================================
header "Step 9/13 — Installing the toggle script"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)/client"
TOGGLE=/usr/local/bin/coldvpn-toggle.sh

# Must be root-owned and not user-writable — that lock is what makes the
# passwordless sudoers rule (Step 11) safe.
sudo cp "$SCRIPT_DIR/coldvpn-toggle.sh" "$TOGGLE"
sudo chown root:wheel "$TOGGLE"
sudo chmod 755 "$TOGGLE"

ok "coldvpn-toggle.sh → $TOGGLE"

# =============================================================================
# STEP 10 — Install the LaunchDaemon (brings the tunnel up at boot)
# =============================================================================
header "Step 10/13 — Installing the boot service"

PLIST=/Library/LaunchDaemons/com.coldvpn.plist
sudo cp "$SCRIPT_DIR/com.coldvpn.plist" "$PLIST"
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"

# Reload-safe: bootstrap is a NO-OP if the label is already loaded, so on a
# re-run an updated plist would never take effect. Unload any existing instance
# first, then load fresh — this also cleanly re-ups the tunnel on a re-run.
sudo launchctl bootout    system "$PLIST" 2>/dev/null || true
sudo launchctl bootstrap  system "$PLIST" 2>/dev/null || true

ok "Boot service installed and (re)loaded"
info "Tunnel will come up automatically at boot"

# =============================================================================
# STEP 11 — Configure sudoers (toggle without a password)
# =============================================================================
header "Step 11/13 — Configuring sudoers"

# Lets the menu-bar button run the toggle script without a password prompt.
# Scoped to ONLY that one script, for the current user.
SUDOERS_FILE=/etc/sudoers.d/coldvpn
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
