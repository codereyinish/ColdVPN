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

Do the **server first** — then on the Mac you only need its **IP** (plus the SSH
access you already have). `install.sh` fetches everything else over SSH.

---

## 1 · Server

### Create the VM

A Linux box with a public IP to be your exit node — a free **Oracle Cloud**
Ubuntu instance works well. You make it once, by hand, in the cloud console, and
open **UDP 443** so WireGuard can be reached.

→ **How: [server/CREATE-VM.md](server/CREATE-VM.md).**

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

Keep the **IP** — that, plus your SSH access to the box, is all the Mac needs.
It reads the server's public key itself over SSH (next).

---

## 2 · Mac

```bash
git clone https://github.com/codereyinish/ColdVPN.git
cd ColdVPN
./install.sh
```

All you give it is the **server's IP** (SSH user defaults to `ubuntu`). It then:

1. installs `wireguard-tools` + SwiftBar and generates this Mac's keys
2. SSHes into the server, reads its public key + port + tunnel subnet
3. swaps keys (below) and writes `wg0.conf`
4. installs the boot service, on/off switch, and 🟢/🔴 menu-bar button

When it finishes the tunnel is up — `curl ifconfig.me` shows your server's IP.

> **Prefer no scripts?** Install **WireGuard** from the Mac App Store →
> *Add Tunnel → Import from file* → pick your `wg0.conf`. Same tunnel, native app.
> ([why](client/decisions/03-cli-vs-app.md))

---

## How the two keys meet

WireGuard is mutual — each side needs the *other's* public key. `install.sh`
does the whole swap over one SSH connection:

```
this Mac's key  ──up──▶   server's [Peer]
server's key    ◀─down──  Mac's wg0.conf
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
