#!/bin/bash
# ColdSpot — enable PF transparent proxy

echo "[coldspot] Loading PF rules..."
sudo pfctl -a coldspot -f "$(dirname "$0")/pf_rules.conf"
sudo pfctl -e 2>/dev/null || true

echo "[coldspot] Routing external traffic through loopback..."
# Route all external traffic via lo0 (PF will intercept)
sudo route -q add -net 0.0.0.0/1 127.0.0.1 2>/dev/null || true
sudo route -q add -net 128.0.0.0/1 127.0.0.1 2>/dev/null || true

# Keep hotspot network direct (not through proxy)
sudo route -q add -net 172.20.10.0/28 -interface en0 2>/dev/null || true

echo "[coldspot] PF enabled ✓"
echo "[coldspot] All TCP traffic will route through iPhone phone APN"
echo "[coldspot] Run: sudo python3 proxy.py"
