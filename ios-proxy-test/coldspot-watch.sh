#!/bin/bash
# coldspot-watch.sh — auto start/stop ColdSpot based on whether we're on the
# iPhone hotspot. Triggered by launchd (WatchPaths on SystemConfiguration) and
# at boot (RunAtLoad). Idempotent, modeled on the WireGuard hotspot script:
#   • lock file   → no overlapping runs (WatchPaths can fire many times)
#   • state check → only start/stop if not already in the right state
#   • sleep       → let the network settle before reading state

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
sleep 3

LOCKFILE="/tmp/coldspot.lock"
[ -f "$LOCKFILE" ] && exit 0
touch "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT

PROXY="/Users/inishbista/wg-hotspot-mac/ios-proxy-test/proxy.py"
LOG="/tmp/coldspot-proxy.log"
IPHONE_GATEWAY="172.20.10.1"
WIFI="Wi-Fi"

# is the SOCKS5 system proxy currently ON?  (used to avoid needless networksetup
# calls — networksetup writes SystemConfiguration, which would re-trigger us)
socks_is_on() {
    networksetup -getsocksfirewallproxy "$WIFI" 2>/dev/null | grep -q "Enabled: Yes"
}

current_gateway=$(netstat -rn | awk '/default/{print $2}' | head -1)
echo "$(date '+%F %T') gateway=$current_gateway"

if [ "$current_gateway" = "$IPHONE_GATEWAY" ]; then
    echo "→ on iPhone hotspot"
    if ! pgrep -f "proxy.py" >/dev/null; then
        echo "  starting proxy.py"
        # NO nohup (fails under launchd: no console). AbandonProcessGroup=true in
        # the plist keeps this alive after the watcher exits.
        python3 "$PROXY" >"$LOG" 2>&1 &
    else
        echo "  proxy.py already running — skip"
    fi
    # enable SOCKS5 ONLY if not already on (avoids re-triggering WatchPaths)
    if ! socks_is_on; then
        echo "  enabling SOCKS5"
        networksetup -setsocksfirewallproxy "$WIFI" 127.0.0.1 1080 2>/dev/null
        networksetup -setsocksfirewallproxystate "$WIFI" on 2>/dev/null
    fi
else
    echo "→ off hotspot"
    if pgrep -f "proxy.py" >/dev/null; then
        echo "  stopping proxy.py + leak monitor"
        pkill -f "proxy.py"
        pkill -f "tcpdump -i en0"
    fi
    if socks_is_on; then
        echo "  disabling SOCKS5"
        networksetup -setsocksfirewallproxystate "$WIFI" off 2>/dev/null
    fi
fi
