#!/bin/bash
# ColdSpot — disable PF transparent proxy

echo "[coldspot] Removing PF rules..."
sudo pfctl -a coldspot -F all 2>/dev/null || true

echo "[coldspot] Restoring routing table..."
sudo route -q delete -net 0.0.0.0/1 127.0.0.1 2>/dev/null || true
sudo route -q delete -net 128.0.0.0/1 127.0.0.1 2>/dev/null || true
sudo route -q delete -net 172.20.10.0/28 2>/dev/null || true

echo "[coldspot] PF disabled ✓ — back to normal hotspot"
