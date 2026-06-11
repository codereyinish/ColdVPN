# ColdVPN

An **always-on, self-hosted WireGuard VPN** for your Mac. Route *all* your
traffic through a cloud server **you own** — instead of trusting a third-party
VPN provider. Built as a hands-on deep-dive into how networking actually works:
routing, tunneling, sockets, and encryption.

```
your Mac → [WireGuard encrypted tunnel] → your server → internet
```

It comes up by itself at boot on **any** network, and a menu-bar button toggles
it on/off. No carrier tricks, no bypass — just a clean VPN to a box you control.

## The two halves

| Part | What it is | Docs |
|------|-----------|------|
| 🖥️ [`client/`](client/) | the **Mac side** — installer, the always-on toggle, the menu-bar button | → [client/README.md](client/README.md) |
| ☁️ [`server/`](server/) | the **cloud side** — one-command WireGuard server setup | → [server/README.md](server/README.md) |
| 📐 design | why WireGuard, why the Mac, DNS through the tunnel | → [client/ARCHITECTURE.md](client/ARCHITECTURE.md) |

## Quick start
1. **Server** — on an Ubuntu VPS (e.g. Oracle Cloud Free Tier): run the setup
   script and open **UDP 443**. → [server/README.md](server/README.md)
2. **Mac** — clone this repo and run `./install.sh`. → [client/README.md](client/README.md)

## License
[Elastic License 2.0](LICENSE) — free for personal use, source visible,
redistribution not permitted.
