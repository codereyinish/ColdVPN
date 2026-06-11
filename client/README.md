# ColdVPN — Mac client

Tunnel your Mac through your own cloud server over an encrypted WireGuard
connection, so traffic is encrypted to a server *you* control — instead of
trusting a third-party VPN provider.

🔗 [Main README](../README.md) · ☁️ [Server setup](../server/README.md) ·
📐 [Architecture & decisions](ARCHITECTURE.md)

## Why self-hosted
Public / free WiFi is slow and untrusted: anything between you and a site can
snoop or tamper. A VPN fixes that — but commercial VPNs ask you to trust *their*
servers (logging, leaks, data-selling). Running your own removes that: the only
server in the path is yours.

## How it works
```
your Mac → [WireGuard encrypted tunnel] → your VPS → internet
```
- **WireGuard** — modern, fast VPN protocol (ChaCha20, tiny codebase)
- **Your VPS** (e.g. Oracle Cloud Free Tier) — the always-on exit node you control
- **Always on** — the tunnel comes up at boot on **any** network; a menu-bar
  button toggles it on/off. No network detection, no carrier tricks.

## Install
First set up the server → [server/README.md](../server/README.md), then on the Mac:
```bash
git clone https://github.com/codereyinish/ColdVPN.git
cd ColdVPN
./install.sh
```
The installer generates your keys, writes `wg0.conf`, installs the boot service
(`com.wireguardvpn.plist`), the on/off switch (`wireguardvpn-toggle.sh`), and the
🟢/🔴 **ColdVPN** menu-bar button (`coldvpn.5s.sh`).

### Prefer no scripts? — the WireGuard app
You can also just install **WireGuard** from the **Mac App Store**, *Add Tunnel →
Import from file* → pick your `wg0.conf`, and toggle from its menu-bar icon. Same
tunnel, native UI. See [decision 03](decisions/03-cli-vs-app.md).

## Layout
- `client/` — `wg0.conf.example`, the toggle script, the menu-bar button, and
  `decisions/` (the architecture notes)
- `server/` — VPS / WireGuard server setup → [server/README.md](../server/README.md)

## Note on `wg0.conf.example`
It's a **full dual-stack tunnel** — both IPv4 (`0.0.0.0/0`) and IPv6 (`::/0`) go
through WireGuard, so nothing leaks outside the tunnel. The clean "regular VPN"
route: everything is tunneled, no need to disable IPv6. Standard VPN hygiene.
