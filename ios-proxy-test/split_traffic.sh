#!/bin/bash
# split_traffic.sh — capture en0 and split traffic (BOTH send + receive) into:
#   PHONE APN = traffic whose OTHER end is the iPhone app (tunnel, 172.20.10.1)
#   HOTSPOT   = traffic whose OTHER end is the internet (tethered) = the LEAK
#   LOCAL     = other local/broadcast/multicast noise
#
# Usage:  sudo bash split_traffic.sh [seconds]      (default 30)
#
# Key idea: every packet on en0 has the Mac (172.20.10.2) on one end. We classify
#   by the OTHER end — so it counts send (Mac->X) AND receive (X->Mac) the same way.
#
# Method: capture to a temp pcap FILE, then analyze (piping live loses data on kill).

IFACE=en0
IPHONE=172.20.10.1
DUR=${1:-30}
CAP=/tmp/coldspot_cap.pcap

# auto-detect the Mac's own hotspot IP (e.g. 172.20.10.2)
MAC=$(ifconfig "$IFACE" 2>/dev/null | awk '/inet 172\.20\.10/{print $2; exit}')
[ -z "$MAC" ] && MAC="172.20.10.2"

echo "Capturing $IFACE for ${DUR}s...  (Mac=$MAC, iPhone=$IPHONE)"
echo "  generate traffic now: browse + run a curl in another terminal"
echo ""

# 1) capture raw packets to a file (reliable)
sudo timeout "$DUR" tcpdump -i "$IFACE" -nn -w "$CAP" 2>/dev/null

# 2) analyze: classify each packet by its NON-Mac endpoint (send + receive)
sudo tcpdump -nn -q -r "$CAP" 2>/dev/null | awk -v mac="$MAC" -v iphone="$IPHONE" '
{
    len = $NF
    if (len !~ /^[0-9]+$/) next          # only data-bearing lines (last field = byte len)
    total += len

    if ($2 == "IP") {                    # IPv4
        src = $3; dst = $5
        sub(/:$/, "", dst)               # strip trailing ":"
        sub(/\.[0-9]+$/, "", src)        # strip ".port" → bare IPv4
        sub(/\.[0-9]+$/, "", dst)

        # the "other" end = whichever side is NOT the Mac
        if (src == mac)      other = dst
        else if (dst == mac) other = src
        else                 other = dst   # neither is Mac (broadcast etc.)

        if (other == iphone)                                phone   += len   # tunnel (both dirs)
        else if (other ~ /^172\.20\.10\./)                  loc     += len   # other local device
        else if (other ~ /^(224|239|255)\./ || other ~ /\.255$/) loc += len  # mcast/bcast
        else                                                hotspot += len   # internet = LEAK (both dirs)
    } else if ($2 == "IP6") {            # IPv6
        if ($0 ~ /fe80/ || $0 ~ /ff0/) loc += len   # link-local / multicast
        else                           hotspot += len  # IPv6 internet = tethered
    } else {
        loc += len                       # ARP, etc.
    }
}
END {
    mb = 1048576
    printf "──────────────────────────────────────────────\n"
    printf "PHONE APN (iPhone app / tunnel):  %8.2f MB\n", phone/mb
    printf "HOTSPOT   (tethered to internet): %8.2f MB   <-- the leak\n", hotspot/mb
    printf "LOCAL     (noise):                %8.2f MB\n", loc/mb
    printf "──────────────────────────────────────────────\n"
    printf "TOTAL on en0 (send + receive):    %8.2f MB\n", total/mb
    if (phone+hotspot > 0)
        printf "\nLeak: %.1f%% of internet traffic went to HOTSPOT (tethered), not phone APN\n", 100*hotspot/(phone+hotspot)
    else
        printf "\n(no internet traffic captured — generate some during the capture)\n"
}'

rm -f "$CAP"
