#!/bin/bash
# coldvpn-toggle.sh — manual on/off switch for the WireGuard VPN.
#   on     : bring the tunnel up now
#   off    : bring the tunnel down now
#   toggle : flip whichever state we're in
#   status : prints "on" or "off" (used by the menu-bar button)
#
# MANUAL BY DESIGN: there is no boot service, so the VPN is always OFF after a
# reboot until you turn it on — like an ordinary VPN. (No launchd, no RunAtLoad.)
#
# Runs as root via a scoped NOPASSWD sudoers rule. MUST be installed root:wheel
# 755 so no non-root user can edit it (that lock is what makes passwordless sudo
# safe).

WG_IF="wg0"
WG="/opt/homebrew/bin/wg"
WG_QUICK="/opt/homebrew/bin/wg-quick"

# macOS quirk: wg-quick maps wg0 → a utunN interface and records the real name in
# /var/run/wireguard/wg0.name. `wg show wg0` does NOT follow that mapping — it
# looks for a literal "wg0" interface and fails ("No such file or directory") —
# so resolve the real name first, then query that. Tunnel down = no .name file.
is_up() {
    local tun
    tun=$(cat "/var/run/wireguard/${WG_IF}.name" 2>/dev/null) || return 1
    [ -n "$tun" ] && "$WG" show "$tun" >/dev/null 2>&1
}

vpn_on()  { is_up || "$WG_QUICK" up   "$WG_IF"; }
vpn_off() { is_up && "$WG_QUICK" down "$WG_IF"; return 0; }

case "${1:-toggle}" in
    on)     vpn_on ;;
    off)    vpn_off ;;
    status) is_up && echo "on" || echo "off" ;;
    toggle) if is_up; then vpn_off; else vpn_on; fi ;;
    *) echo "usage: $0 [on|off|toggle|status]" >&2; exit 1 ;;
esac
