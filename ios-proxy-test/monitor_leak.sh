#!/bin/bash
# monitor_leak.sh — LIVE continuous leak monitor. Runs until Ctrl+C.
# Prints a running cumulative tally of PHONE APN vs HOTSPOT (leak) every few seconds.
#
# Usage:  sudo bash monitor_leak.sh [interval_seconds]   (default 5)
#
# Classifies each packet on en0 by its NON-Mac endpoint (handles send + receive):
#   other end = iPhone (172.20.10.1)  → PHONE APN  (tunnel)
#   other end = internet IP            → HOTSPOT    (leak)
#
# Live processing works here (unlike the one-shot timeout version) because:
#   • tcpdump -l  → line-buffers stdout (flushes each packet immediately)
#   • no `timeout` killing it mid-buffer
#   • awk fflush() → prints updates immediately

IFACE=en0
IPHONE=172.20.10.1
INTERVAL=${1:-5}

MAC=$(ifconfig "$IFACE" 2>/dev/null | awk '/inet 172\.20\.10/{print $2; exit}')
[ -z "$MAC" ] && MAC="172.20.10.2"

echo "LIVE leak monitor on $IFACE  (Mac=$MAC, iPhone=$IPHONE, update=${INTERVAL}s)"
echo "Running totals since start. Ctrl+C to stop."
echo "──────────────────────────────────────────────────────────────"

sudo tcpdump -i "$IFACE" -nn -q -l 2>/dev/null | awk -v mac="$MAC" -v iphone="$IPHONE" -v interval="$INTERVAL" '
{
    len = $NF
    if (len !~ /^[0-9]+$/) next

    if ($2 == "IP") {
        src = $3; dst = $5
        sub(/:$/, "", dst); sub(/\.[0-9]+$/, "", src); sub(/\.[0-9]+$/, "", dst)
        if (src == mac)      other = dst
        else if (dst == mac) other = src
        else                 other = dst
        if (other == iphone)                                        phone   += len
        else if (other ~ /^172\.20\.10\./ || other ~ /^(224|239|255)\./ || other ~ /\.255$/) loc += len
        else                                                        hotspot += len
    } else if ($2 == "IP6") {
        if ($0 ~ /fe80/ || $0 ~ /ff0/) loc += len; else hotspot += len
    } else {
        loc += len
    }

    # periodic print using the packet timestamp ($1 = HH:MM:SS.ffffff)
    split($1, t, ":")
    now = t[1]*3600 + t[2]*60 + t[3]
    if (last == 0) last = now
    if (now - last >= interval) {
        mb = 1048576
        leak = (phone+hotspot > 0) ? 100*hotspot/(phone+hotspot) : 0
        printf "PHONE APN: %8.2f MB │ HOTSPOT(leak): %8.2f MB │ leak %5.1f%%\n", \
               phone/mb, hotspot/mb, leak
        fflush()
        last = now
    }
}'
