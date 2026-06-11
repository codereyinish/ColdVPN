#!/bin/bash
# SwiftBar menu-bar plugin — ColdVPN toggle button (refreshes every 5s).
# Wraps /usr/local/bin/coldvpn-toggle.sh, called passwordless via the sudoers rule.
TOGGLE="/usr/local/bin/coldvpn-toggle.sh"

STATE="$(sudo -n "$TOGGLE" status 2>/dev/null)"

if [ "$STATE" = "on" ]; then
    echo "🟢 ColdVPN"
    echo "---"
    echo "Connected — via Oracle"
    echo "Turn OFF | bash=/usr/bin/sudo param1=-n param2=$TOGGLE param3=off terminal=false refresh=true"
else
    echo "🔴 ColdVPN"
    echo "---"
    echo "Disconnected"
    echo "Turn ON | bash=/usr/bin/sudo param1=-n param2=$TOGGLE param3=on terminal=false refresh=true"
fi
