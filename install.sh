#!/bin/bash
# =============================================================================
# install.sh — ColdVPN Installer (Mac)
# =============================================================================
# Sets up a manual, self-hosted WireGuard VPN on your Mac. All Mac traffic is
# routed through your own WireGuard server (e.g. Oracle Cloud free tier) while
# the tunnel is on. A menu-bar button toggles it on/off — and like an ordinary
# VPN it is always OFF after a reboot (no boot service) until you turn it on.
#
# What it installs:
#   - Homebrew (if missing)
#   - wireguard-tools (via Homebrew)
#   - SwiftBar (menu-bar app)
#   - coldvpn-toggle.sh   → /usr/local/bin/   (on/off switch)
#   - wg0.conf                 → your WireGuard config dir
#   - sudoers rule             → /etc/sudoers.d/coldvpn  (toggle without password)
#   - coldvpn.5s.sh            → your SwiftBar plugins folder  (menu-bar button)
#
# You provide:
#   - Your server's IP address (the installer SSHes in to discover the rest)
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
# CLIENT CONFIG DEFAULTS  (not prompted for)
# =============================================================================
# SERVER_PORT and CLIENT_ADDR are READ from the server over SSH in Step 7 — the
# values below are just the fallback if that detection fails. DNS is a purely
# client-side choice the server has no say in; change it here if you prefer a
# different resolver (e.g. 9.9.9.9 for Quad9).
DNS_SERVER="1.1.1.1"     # resolver the Mac uses inside the tunnel
SERVER_PORT="443"        # WireGuard port — auto-read from the server in Step 7
CLIENT_ADDR="10.8.0.2"   # this Mac's address inside the tunnel — auto-derived in Step 7

# SERVER_IP / SSH_USER may be pre-set in the environment — provision.sh exports
# them after it builds the server, so the chained run skips the Step 6 prompts.
# Run install.sh on its own and they're empty, so it asks as usual.
SERVER_IP="${SERVER_IP:-}"
SSH_USER="${SSH_USER:-}"

# =============================================================================
# STEP 0 — Welcome
# =============================================================================
clear
echo ""
echo "${BLD}  ColdVPN — Installer${RST}"
echo "  ────────────────────────────────────────"
echo "  A self-hosted WireGuard VPN for your Mac."
echo "  Routes all traffic through your own server."
echo "  Toggle it from the menu bar; after a reboot"
echo "  it's off until you turn it on."
echo ""
echo "  You'll need your server's IP (and SSH access)."
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

echo "  The installer SSHes into the server to finish setup automatically — it"
echo "  reads the WireGuard port and your tunnel address straight from the server,"
echo "  so all you need to give it is how to reach the box."
echo ""
echo "  ${DIM}Where to find these:${RST}"
echo "  ${DIM}• Server IP → Oracle console → Compute → Instances → your instance →${RST}"
echo "  ${DIM}             'Public IP address'  (or the line setup.sh printed at the end)${RST}"
echo "  ${DIM}• SSH user  → 'ubuntu' on Oracle's Ubuntu image — just press Enter${RST}"
echo ""

# If provision.sh already handed us a valid IP, use it and skip the prompt;
# otherwise reprompt until the IP is a valid IPv4 address.
if valid_ipv4 "$SERVER_IP"; then
    ok "Server IP provided: ${BLU}${SERVER_IP}${RST}"
else
    while :; do
        ask SERVER_IP "Server IP address (e.g. 203.0.113.10)" ""
        if [ -z "$SERVER_IP" ]; then info "Server IP can't be empty — try again."; continue; fi
        if valid_ipv4 "$SERVER_IP"; then break; fi
        info "'$SERVER_IP' isn't a valid IPv4 address (like 203.0.113.10) — try again."
    done
fi

# Same for the SSH user: honour a pre-set value, else ask (default "ubuntu").
if [ -n "$SSH_USER" ]; then
    ok "SSH username: ${BLU}${SSH_USER}${RST}"
else
    ask SSH_USER "SSH username on the server" "ubuntu"
fi

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

# Address lists default to IPv4-only; the SSH branch below upgrades them to
# dual-stack when the server has an IPv6 address on wg0. Defined here so the
# manual-fallback branch (no SSH) still has them.
CLIENT_ADDR6=""
PEER_ALLOWED="${CLIENT_ADDR}/32"   # server-side peer AllowedIPs (this Mac)
IFACE_ADDR="${CLIENT_ADDR}/32"     # Mac [Interface] Address
TUNNEL_ALLOWED="0.0.0.0/0"         # Mac [Peer] AllowedIPs (what to route in)

echo "  ${BLD}┌─ over SSH ─────────────────────────────────────────${RST}"
narrate "ssh ${SSH_DEST}  — connecting to your server..."
if ssh $SSH_OPTS "$SSH_DEST" 'true'; then
    ok "you're on the server"

    # Fresh server? Bootstrap WireGuard over this same SSH connection — but ONLY
    # if it isn't set up yet. An existing wg0 is left untouched (never re-keyed),
    # so running this against a live server is safe.
    if ssh $SSH_OPTS "$SSH_DEST" 'sudo wg show wg0' >/dev/null 2>&1; then
        ok "server already set up — keeping its key (skipping setup.sh); its peer is updated below"
    else
        narrate "fresh server — installing WireGuard (one-time setup.sh over SSH)..."
        ssh $SSH_OPTS "$SSH_DEST" 'curl -fsSL https://raw.githubusercontent.com/codereyinish/ColdVPN/main/server/setup.sh | sudo bash'
        ok "server WireGuard installed"
    fi

    narrate "reading the server's identity (its public key)..."
    SERVER_PUBKEY=$(ssh $SSH_OPTS "$SSH_DEST" 'sudo wg show wg0 public-key' 2>/dev/null | tr -d '[:space:]')
    [ -z "$SERVER_PUBKEY" ] && die "Couldn't read the server's public key (is WireGuard running there?)."
    echo "       server key   ${GRN}<--${RST} ${BLU}${SERVER_PUBKEY}${RST}"

    narrate "reading the server's WireGuard port + tunnel subnet..."
    # Pipes END in tr, so the assignment's status is always 0 — safe under set -e
    # even when ssh fails. Empty results just fall back to the defaults up top.
    DETECTED_PORT=$(ssh $SSH_OPTS "$SSH_DEST" 'sudo wg show wg0 listen-port' 2>/dev/null | tr -d '[:space:]')
    if [ -n "$DETECTED_PORT" ]; then SERVER_PORT="$DETECTED_PORT"; fi
    SERVER_WG_ADDR=$(ssh $SSH_OPTS "$SSH_DEST" "ip -o -4 addr show wg0 2>/dev/null | awk '{print \$4}'" | cut -d/ -f1 | tr -d '[:space:]')
    if [ -n "$SERVER_WG_ADDR" ]; then CLIENT_ADDR=$(echo "$SERVER_WG_ADDR" | awk -F. '{print $1"."$2"."$3".2"}'); fi
    echo "       wg port      ${GRN}<--${RST} ${BLU}${SERVER_PORT}${RST}"
    echo "       this Mac IP  ${GRN} =${RST}  ${BLU}${CLIENT_ADDR}${RST}"

    # Rebuild the IPv4 address lists from the value Step 7 actually detected
    # (the pre-SSH defaults above used the fallback CLIENT_ADDR).
    PEER_ALLOWED="${CLIENT_ADDR}/32"
    IFACE_ADDR="${CLIENT_ADDR}/32"

    # IPv6: if the server has a global IPv6 on wg0 (e.g. fd86:…::1), mirror the
    # IPv4 ".2" choice → fd86:…::2 and route ::/0 too, so IPv6 doesn't leak
    # around the tunnel. Servers without IPv6 simply stay IPv4-only.
    SERVER_WG_ADDR6=$(ssh $SSH_OPTS "$SSH_DEST" "ip -o -6 addr show wg0 scope global 2>/dev/null | awk '{print \$4}'" | cut -d/ -f1 | tr -d '[:space:]')
    if [ -n "$SERVER_WG_ADDR6" ]; then
        CLIENT_ADDR6="${SERVER_WG_ADDR6%::*}::2"
        PEER_ALLOWED="${PEER_ALLOWED}, ${CLIENT_ADDR6}/128"
        IFACE_ADDR="${IFACE_ADDR}, ${CLIENT_ADDR6}/128"
        TUNNEL_ALLOWED="${TUNNEL_ALLOWED}, ::/0"
        echo "       this Mac v6  ${GRN} =${RST}  ${BLU}${CLIENT_ADDR6}${RST}"
    fi

    narrate "handing the server THIS Mac's public key..."
    echo "       your key     ${GRN}-->${RST} ${BLU}${PUBLIC_KEY}${RST}"

    narrate "updating /etc/wireguard/wg0.conf on the server..."
    ssh $SSH_OPTS "$SSH_DEST" "sudo bash -s" <<REMOTE
set -e
# keep the [Interface] section (everything before the first [Peer]), drop old
# peers, then append this Mac as the single peer. Built in a .new file and moved
# into place atomically — under set -e a failure aborts before the mv, so the
# live wg0.conf is never left half-written (no .bak needed).
awk '/^\[Peer\]/{exit} {print}' /etc/wireguard/wg0.conf | grep -v '^[[:space:]]*\$' > /etc/wireguard/wg0.conf.new
printf '\n[Peer]\nPublicKey = %s\nAllowedIPs = %s\n' '$PUBLIC_KEY' '$PEER_ALLOWED' >> /etc/wireguard/wg0.conf.new
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
    echo "       AllowedIPs = ${PEER_ALLOWED}${RST}"
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

# AllowedIPs send all traffic through the tunnel — 0.0.0.0/0 for IPv4, plus ::/0
# for IPv6 when the server supports it (so IPv6 can't leak around the tunnel).
sudo tee "$WG_CONF_DIR/wg0.conf" > /dev/null << EOF
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address = ${IFACE_ADDR}
DNS = ${DNS_SERVER}

[Peer]
PublicKey = ${SERVER_PUBKEY}
Endpoint = ${SERVER_IP}:${SERVER_PORT}
AllowedIPs = ${TUNNEL_ALLOWED}
PersistentKeepalive = 25
EOF

sudo chmod 600 "$WG_CONF_DIR/wg0.conf"
ok "wg0.conf written"

# Show what was written (private key hidden).
echo "       ${YLW}|${RST} [Interface]"
echo "       ${YLW}|${RST} PrivateKey = ${BLD}(hidden)${RST}"
echo "       ${YLW}|${RST} Address    = ${IFACE_ADDR}"
echo "       ${YLW}|${RST} DNS        = ${DNS_SERVER}"
echo "       ${YLW}|${RST} [Peer]"
echo "       ${YLW}|${RST} PublicKey  = ${SERVER_PUBKEY}"
echo "       ${YLW}|${RST} Endpoint   = ${SERVER_IP}:${SERVER_PORT}"
echo "       ${YLW}|${RST} AllowedIPs = ${TUNNEL_ALLOWED}"

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
# STEP 10 — Bring the tunnel up (manual — no boot service)
# =============================================================================
# ColdVPN is MANUAL, like an ordinary VPN: there is NO LaunchDaemon, so the
# tunnel never starts by itself at boot. We bring it up once here so you can
# verify it works; after a reboot it stays OFF until you turn it on from the
# menu-bar button. (Step 1.5 already removed any old always-on boot daemon.)
header "Step 10/13 — Starting the tunnel"

sudo "$WG_QUICK_BIN" down wg0 2>/dev/null || true   # clear any half-up state
sudo "$WG_QUICK_BIN" up wg0

ok "Tunnel up"
info "Won't start on its own — off after a reboot until you turn it on"

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

# Not prompted — SwiftBar's default plugins location under your home folder.
PLUGINS_DIR="$HOME/swiftbar-plugins"

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
echo "  • Menu-bar button  → $PLUGINS_DIR/coldvpn.5s.sh"
echo ""
echo "  The 🟢/🔴 ColdVPN button in your menu bar turns the VPN on/off."
echo "  After a reboot it's off until you turn it on from the menu bar."
echo ""
