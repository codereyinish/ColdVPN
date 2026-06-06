#!/bin/bash
# find_leak.sh — identify WHAT is leaking to hotspot.
# Captures en0 for N seconds, isolates the LEAK (traffic to/from internet IPs that
# bypassed the tunnel), and breaks it down by protocol + destination + volume.
#
# Usage:  sudo bash find_leak.sh [seconds]   (default 30)

IFACE=en0
IPHONE=172.20.10.1
DUR=${1:-30}
CAP=/tmp/coldspot_leak.pcap

MAC=$(ifconfig "$IFACE" 2>/dev/null | awk '/inet 172\.20\.10/{print $2; exit}')
[ -z "$MAC" ] && MAC="172.20.10.2"

echo "Capturing $IFACE for ${DUR}s to find the leak... (use the Mac normally now)"
sudo timeout "$DUR" tcpdump -i "$IFACE" -nn -w "$CAP" 2>/dev/null
echo ""

# Analyze: classify each packet; for LEAK packets, tally by protocol + dest:port.
# Protocol/total summary → stderr (prints as-is); destinations → stdout (sorted).
sudo tcpdump -nn -q -r "$CAP" 2>/dev/null | awk -v mac="$MAC" -v iphone="$IPHONE" '
{
    len=$NF; if (len !~ /^[0-9]+$/) next
    if ($2 != "IP") next                         # IPv4 only for clean IP:port parse

    proto = ($0 ~ /UDP/) ? "UDP" : (($0 ~ / tcp/) ? "TCP" : "OTH")

    src=$3; dst=$5; sub(/:$/,"",dst)
    sip=src; sub(/\.[0-9]+$/,"",sip)             # src IP
    dip=dst; sub(/\.[0-9]+$/,"",dip)             # dst IP
    sport=src; sub(/.*\./,"",sport)              # src port
    dport=dst; sub(/.*\./,"",dport)              # dst port

    if (sip==mac)      { other=dip; oport=dport } # Mac sending  → other = dst
    else if (dip==mac) { other=sip; oport=sport } # Mac receiving → other = src
    else next

    # keep ONLY leak: other end is a public internet IP
    if (other==iphone) next
    if (other ~ /^172\.20\.10\./ || other ~ /^(224|239|255)\./ || other ~ /\.255$/) next

    key = proto "  " other ":" oport
    bytes[key]    += len
    bps[proto]    += len
    total         += len
}
END {
    mb=1048576
    printf "================ LEAK SUMMARY ================\n" > "/dev/stderr"
    for (p in bps) printf "  %-4s %8.2f MB\n", p, bps[p]/mb > "/dev/stderr"
    printf "  TOTAL leak: %.2f MB\n", total/mb > "/dev/stderr"
    printf "\n=== Top leaking destinations (proto  ip:port) ===\n" > "/dev/stderr"
    for (k in bytes) printf "%12.2f MB  %s\n", bytes[k]/mb, k    # → stdout, sortable
}' | sort -rn | head -25

rm -f "$CAP"
