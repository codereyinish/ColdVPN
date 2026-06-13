# ColdVPN — Architecture & Decisions

🔗 [Main README](../README.md) · 🔧 [Developer guide](../DEVELOPER.md)

A record of the key design decisions, one file each — short "why this, not that"
notes, written as the reasoning, not just the result.

| # | Decision | Why |
|---|----------|-----|
| [01](decisions/01-wireguard-vs-tls-relay.md) | WireGuard, not a TLS relay | a TLS relay is TCP-in-TCP (melts down on lossy links), TCP-only (leaks UDP/QUIC), and a shared token is weaker than asymmetric keys |
| [02](decisions/02-mac-not-iphone.md) | The Mac runs the VPN, not the iPhone | iOS can't tunnel a tethered Mac and needs a $99 entitlement; macOS does it free |
| [03](decisions/03-cli-vs-app.md) | The CLI, not the WireGuard app | the App Store app is easy (Network Extension, GUI, import-and-click) but its tunnel is a sandboxed NE the shell can't drive — ColdVPN needs `wg-quick`/`wg show` for install.sh, the toggle, and the menu-bar status |
| [04](decisions/04-dns-through-tunnel.md) | DNS through the tunnel, not direct | resolving direct leaks every domain you visit (the one cleartext metadata); routing via the VPS closes that leak, and TLS certs backstop any tampering on the VPS→resolver leg |
| [08](decisions/08-provisioning-terraform.md) | Provision the server with Terraform, not a GUI-agent or raw `oci` CLI | a console-clicking bot is fragile and can't bot signup; the API is the right door — and Terraform's declarative config + state-tracked `destroy` beats hand-written `oci` commands (one-command create/teardown) |

## At a glance
```
your Mac → [WireGuard encrypted tunnel] → your VPS → internet
```
- **UDP, packet-level (L3)** — carries every protocol, no TCP-over-TCP meltdown
- **asymmetric keys** — the private key never leaves the device
- **runs on the Mac** — free utun, protects the Mac's own traffic
- **two ways to run it** — the App Store app (easy) or the CLI (advanced)

> **Runtime data path** — how a packet actually moves through the two NATs and
> back — lives in its own doc: **[PACKET-FLOW.md](PACKET-FLOW.md)**.
