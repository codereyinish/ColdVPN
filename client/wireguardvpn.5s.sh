#!/bin/bash
# SwiftBar menu-bar plugin — WireGuard VPN toggle button.
# Filename "*.5s.sh" = SwiftBar refreshes it every 5 seconds.
# Needs: SwiftBar + /usr/local/bin/wireguardvpn-toggle.sh + the NOPASSWD sudoers rule
# (so `sudo -n` runs without a prompt).
TOGGLE="/usr/local/bin/wireguardvpn-toggle.sh"

STATE="$(sudo -n "$TOGGLE" status 2>/dev/null)"

if [ "$STATE" = "on" ]; then
    echo "🟢 VPN"
    echo "---"
    echo "Connected — exit via Oracle"
    echo "Turn OFF | bash=/usr/bin/sudo param1=-n param2=$TOGGLE param3=off terminal=false refresh=true"
else
    echo "🔴 VPN"
    echo "---"
    echo "Disconnected"
    echo "Turn ON | bash=/usr/bin/sudo param1=-n param2=$TOGGLE param3=on terminal=false refresh=true"
fi
