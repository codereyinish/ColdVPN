# ColdVPN — server

The cloud side: a one-command WireGuard server on an Ubuntu VPS. This is the
**exit node** your Mac tunnels to — all your traffic leaves the internet wearing
this server's IP.

🔗 [Main README](../README.md) · 🖥️ [Mac client](../client/README.md) ·
📐 [Architecture & decisions](../client/ARCHITECTURE.md)

## How it fits
```
your Mac → [WireGuard encrypted tunnel] → THIS server → internet
```

## Setup
On a fresh Ubuntu VPS (e.g. Oracle Cloud Free Tier), as root:
```bash
curl -fsSL https://raw.githubusercontent.com/codereyinish/ColdVPN/main/server/setup.sh | sudo bash
```
`setup.sh` walks 10 steps: installs WireGuard, generates the server keys,
auto-detects the network interface, enables IP forwarding, writes
`/etc/wireguard/wg0.conf`, and starts the tunnel as a boot service. At the end it
prints the **server public key** and **public IP** — you paste those into the Mac
installer.

You provide one thing: your **Mac's public key** (the Mac installer prints it).

## Open the port
WireGuard listens on **UDP 443**. Two firewalls to clear:
- **OS firewall** — `setup.sh` opens it if `ufw` is active.
- **Cloud firewall** — you must add an ingress rule yourself. On Oracle:
  *Networking → VCN → Security Lists → Add Ingress Rule* → **Protocol UDP, Port 443**.

## Files
- `setup.sh` — the installer (run it on the server)
- `wg0.conf.example` — a template of what `setup.sh` writes

## Heads-up: Oracle's default firewall
Oracle's Ubuntu image ships a default `FORWARD ... REJECT` rule. The WireGuard
`FORWARD` ACCEPT rule must be **inserted above** it (`iptables -I FORWARD 1`, not
`-A`), or clients connect but get no internet. `setup.sh` already does this — just
don't "fix" it back to `-A`.
