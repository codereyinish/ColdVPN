# ColdVPN

An **always-on, self-hosted WireGuard VPN** for your Mac. Route *all* your
traffic through a cloud server **you own** — instead of trusting a third-party
VPN provider.

```
your Mac → [WireGuard encrypted tunnel] → your server → internet
```

It comes up by itself at boot on **any** network, and a 🟢/🔴 menu-bar button
toggles it on/off. No carrier tricks, no bypass — just a clean VPN to a box you
control.

📐 Want the *why* (WireGuard vs alternatives, DNS through the tunnel)? →
[client/ARCHITECTURE.md](client/ARCHITECTURE.md)
🔧 Want every step by hand? → [DEVELOPER.md](DEVELOPER.md)

---

## Setup

Two halves: a **server** (the exit node) and your **Mac** (the client). Do the
server first — it gives you the public key and IP the Mac needs.

### 1. Server — on an Ubuntu VPS (e.g. Oracle Cloud Free Tier)

Run as root:
```bash
curl -fsSL https://raw.githubusercontent.com/codereyinish/ColdVPN/main/server/setup.sh | sudo bash
```
This installs WireGuard, generates the server keys, enables forwarding, sets up
NAT, and starts the tunnel as a boot service. At the end it prints the **server
public key** and **public IP** — keep those for the Mac.

Then open the port in your **cloud firewall**: WireGuard listens on **UDP 443**.
On Oracle: *Networking → VCN → Security Lists → Add Ingress Rule → Protocol UDP,
Port 443*.

> **Oracle note:** the server's firewall must put the WireGuard FORWARD-accept
> rule *above* Oracle's default REJECT — `setup.sh` already does this. If clients
> connect but get no internet, that's the rule to check.

### 2. Mac — the client

```bash
git clone https://github.com/codereyinish/ColdVPN.git
cd ColdVPN
./install.sh
```
The installer generates your keys, writes `wg0.conf` (using the server key + IP
from step 1), installs the boot service (`com.coldvpn.plist`), the on/off switch
(`coldvpn-toggle.sh`), and the 🟢/🔴 **ColdVPN** menu-bar button (`coldvpn.5s.sh`).

During install you'll paste your Mac's public key into the server's config (the
installer shows you exactly what to add).

### Prefer no scripts?
Install **WireGuard** from the **Mac App Store**, *Add Tunnel → Import from file*
→ pick your `wg0.conf`, and toggle from its menu-bar icon. Same tunnel, native UI.
See [decision 03](client/decisions/03-cli-vs-app.md).

---

## Layout
- [`client/`](client/) — the Mac side: installer scripts, the toggle, the
  menu-bar button, and [`ARCHITECTURE.md`](client/ARCHITECTURE.md) + `decisions/`
- [`server/`](server/) — the cloud side: `setup.sh` + the config template

## License
[Elastic License 2.0](LICENSE) — free for personal use, source visible,
redistribution not permitted.
