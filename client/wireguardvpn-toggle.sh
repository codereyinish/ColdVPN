#!/bin/bash
# wireguardvpn-toggle.sh — one switch for the always-on WireGuard VPN.
#   on     : enable + bootstrap the daemon (RunAtLoad brings the tunnel up), boot-persist
#   off    : wg-quick down + bootout + disable (tunnel down now, won't return at boot)
#   toggle : flip whichever state we're in
#   status : prints "on" or "off" (used by the menu-bar button)
# Runs as root via a scoped NOPASSWD sudoers rule. MUST be installed root:wheel 755
# so no non-root user can edit it (that lock is what makes passwordless sudo safe).

WG_IF="wg0"
LABEL="com.wireguardvpn"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
WG="/opt/homebrew/bin/wg"
WG_QUICK="/opt/homebrew/bin/wg-quick"

is_up() { "$WG" show "$WG_IF" >/dev/null 2>&1; }

vpn_on() {
    /bin/launchctl enable "system/${LABEL}" 2>/dev/null
    if ! /bin/launchctl bootstrap system "$PLIST" 2>/dev/null; then
        # daemon already loaded → just make sure the tunnel itself is up
        is_up || "$WG_QUICK" up "$WG_IF"
    fi
}

vpn_off() {
    is_up && "$WG_QUICK" down "$WG_IF"
    /bin/launchctl bootout  system "$PLIST" 2>/dev/null
    /bin/launchctl disable "system/${LABEL}" 2>/dev/null
    return 0
}

case "${1:-toggle}" in
    on)     vpn_on ;;
    off)    vpn_off ;;
    status) is_up && echo "on" || echo "off" ;;
    toggle) if is_up; then vpn_off; else vpn_on; fi ;;
    *) echo "usage: $0 [on|off|toggle|status]" >&2; exit 1 ;;
esac
