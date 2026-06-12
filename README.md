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

---

## Setup

Two things you do by hand — everything after is automatic.

### 1 · Create the server VM

A free **Oracle Cloud** Ubuntu instance, with **UDP 443** open. One-time, in the
cloud console. → [server/CREATE-VM.md](server/CREATE-VM.md)

### 2 · Run the installer on your Mac

```bash
git clone https://github.com/codereyinish/ColdVPN.git
cd ColdVPN
./install.sh
```

Partway through, it asks for the server's **public IP** — grab it from the Oracle
console under *Instances → your instance → Public IP address* — and the **SSH
username** (`ubuntu` on Oracle's image). Enter those and `install.sh` takes over:
SSHes in, sets up the server if it's fresh, swaps keys, and brings the tunnel up.

When it finishes, the **ColdVPN** button shows up in your menu bar:

![ColdVPN menu-bar button](docs/menubar.png)

### Test it's working

```bash
curl ifconfig.me
```

It should print your **server's IP** — not your home one. Click the menu-bar
button to toggle the tunnel off and back on.

> **Prefer no scripts?** Install **WireGuard** from the Mac App Store →
> *Add Tunnel → Import from file* → pick your `wg0.conf`. Same tunnel, native app.
> ([why](client/decisions/03-cli-vs-app.md))

---

## How the two keys meet

WireGuard is mutual — each side needs the *other's* public key. `install.sh`
does the whole swap over one SSH connection:

```
              ┌─────────── over SSH (the access you already have) ───────────┐
this Mac's key  ──copied UP──▶   server /etc/wireguard/wg0.conf   [Peer]
server's key    ◀──copied DOWN── server  (read live with `wg show`)   into Mac wg0.conf
```

No manual paste — the Mac's in-tunnel address and the server's port come down the
same read. ([why SSH](client/decisions/06-automate-key-handoff-over-ssh.md))

---

## Troubleshooting

Connected but something's off? Check in this order:

- **No handshake / won't connect** — UDP 443 isn't open in the cloud firewall, or the server IP / port / key is wrong.
- **Connects, but no internet** — IP forwarding or NAT isn't active on the server. *(Oracle's image also ships a default `FORWARD … REJECT` rule; `setup.sh` inserts WireGuard's accept rule above it.)*
- **Pages won't resolve** — DNS; check the `DNS =` line in your `wg0.conf`.
- **Real IP leaking on IPv6** (`curl ifconfig.me` ≠ `curl -4`) — `install.sh` routes `::/0` only if the server has IPv6 (address on `wg0` + ip6tables `MASQUERADE`). IPv4-only server? Disable IPv6 on the Mac.

## Learn more
- **Why WireGuard? DNS through the tunnel?** → [client/ARCHITECTURE.md](client/ARCHITECTURE.md)
- **Every step by hand** → [DEVELOPER.md](DEVELOPER.md)
- **Design decisions** → [client/decisions/](client/decisions/)

## Layout
- [`client/`](client/) — the Mac side: installer, toggle, menu-bar button
- [`server/`](server/) — the cloud side: `setup.sh` + config template

## License
[Elastic License 2.0](LICENSE) — free for personal use, source visible,
redistribution not permitted.
