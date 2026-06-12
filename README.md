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

You set up **two machines** — they swap public keys and you're done:

| | Machine | What it is |
|---|---|---|
| **1** | **Server** | a cloud VM — the exit node |
| **2** | **Mac** | the client that connects to it |

Do the **server first**: it hands you the public key and IP that the Mac needs.

---

## 1 · Server

### Create the VM
A one-time, by-hand step in your cloud console (Oracle Cloud Free Tier works
well). In short: an **Ubuntu 22.04** instance, your **SSH key** added, and
**UDP 443 open** in the firewall.

→ **New to this? Full walkthrough: [server/CREATE-VM.md](server/CREATE-VM.md).**

> **Why by hand?** Creating an account, a VM, and opening a cloud firewall can
> only be done by a human in the provider's console — there's no server to script
> against yet. Everything *after* you can SSH in is automated, below.

### Run the installer
SSH into the server, then:

```bash
curl -fsSL https://raw.githubusercontent.com/codereyinish/ColdVPN/main/server/setup.sh | sudo bash
```

This installs WireGuard, generates the server keys, enables forwarding + NAT,
and starts the tunnel as a boot service.

**When it finishes you'll see:**

```
✓ Server setup complete!

  Server public key:  <copy this>
  Server IP:          <your server's IP>
  Server port:        443

  Now run install.sh on your Mac.
```

Keep the **public key** and **IP** — the Mac asks for them next.

---

## 2 · Mac

```bash
git clone https://github.com/codereyinish/ColdVPN.git
cd ColdVPN
./install.sh
```

The installer generates your Mac's keys, writes `wg0.conf` (using the server key
+ IP from step 1), and installs the boot service, the on/off switch, and the
🟢/🔴 **ColdVPN** menu-bar button.

**Partway through it pauses** and shows your Mac's public key — paste that into
the server's config (it shows you exactly what to add), then continue.

> **Prefer no scripts?** Install **WireGuard** from the Mac App Store →
> *Add Tunnel → Import from file* → pick your `wg0.conf`. Same tunnel, native app.
> ([why](client/decisions/03-cli-vs-app.md))

---

## How the two keys meet

Each side needs the *other's* public key — which is why the two installers
interleave rather than running strictly one-then-the-other:

```
Mac install.sh   ──(Mac public key)──▶   server config
server setup.sh  ──(server public key)─▶  Mac config
```

The Mac generates its key and **pauses** → you add it on the server → the server
hands back its key → you finish the Mac. That handshake is the whole setup.

---

## Troubleshooting

Connected but something's off? Check in this order:

- **No handshake / won't connect** — UDP 443 isn't open in the cloud firewall, or the server IP / port / key is wrong.
- **Connects, but no internet** — IP forwarding or NAT isn't active on the server. *(Oracle's image also ships a default `FORWARD … REJECT` rule; `setup.sh` inserts WireGuard's accept rule above it.)*
- **Pages won't resolve** — DNS; check the `DNS =` line in your `wg0.conf`.

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
