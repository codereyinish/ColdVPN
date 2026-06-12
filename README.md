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

WireGuard runs on a Linux VM **you own** — a free **Oracle Cloud** instance works
well. Because the box is yours, *you* stand up everything around it: the instance
itself, your SSH access, and the network rules that let traffic in and out.

A one-time, by-hand pass in the cloud console:

- an **Ubuntu 22.04** instance (an Always-Free shape is plenty)
- your **SSH public key** added, so you can log in
- **UDP 443 opened** in the instance's **security list / cloud firewall** — this
  is the port WireGuard listens on, and nothing connects until it's open
- *(the OS firewall, IP forwarding, and NAT are set up later by `setup.sh` — you
  don't touch those by hand)*

→ **New to this? Step-by-step walkthrough: [server/CREATE-VM.md](server/CREATE-VM.md).**

> **Why by hand?** An account, a VM, and a cloud firewall rule can only be created
> by a human in the provider's console — there's no server to script against *yet*.
> Once you can **SSH in**, the rest is automated: you SSH to the box and run
> `setup.sh` (next), and later the Mac's `install.sh` SSHes in on its own to finish
> the key handoff. That console click-through is the **only** manual part.

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

All you hand it is the **server's IP** (and SSH user — default `ubuntu`).
Everything else it works out. In order, `install.sh`:

1. **Sets up the Mac** — installs `wireguard-tools` + SwiftBar, then generates a
   fresh key pair for this Mac.
2. **SSHes into the server** using the access you already have, and in one shot
   reads the server's **public key**, **WireGuard port**, and **tunnel subnet**
   (and IPv6 subnet, if any) — so you never copy/paste them.
3. **Swaps the keys automatically** (see *How the two keys meet*, below).
4. **Writes `wg0.conf`** and installs the boot service, the on/off switch, and
   the 🟢/🔴 **ColdVPN** menu-bar button.

No manual pausing or pasting — when it finishes the tunnel is already up.
`curl ifconfig.me` should show your server's address.

> **Prefer no scripts?** Install **WireGuard** from the Mac App Store →
> *Add Tunnel → Import from file* → pick your `wg0.conf`. Same tunnel, native app.
> ([why](client/decisions/03-cli-vs-app.md))

---

## How the two keys meet

WireGuard is mutual: each side must hold the *other's* public key. That used to
mean an interleaved manual dance — generate on the Mac, paste it onto the server,
copy the server's key back. **`install.sh` now does the entire exchange itself,
over one SSH connection:**

```
              ┌─────────── over SSH (the access you already have) ───────────┐
this Mac's key  ──copied UP──▶   server /etc/wireguard/wg0.conf   [Peer]
server's key    ◀──copied DOWN── server  (read live with `wg show`)   into Mac wg0.conf
```

So the server's `[Peer]` block gets filled in by **copying the Mac's public key
up**, and the Mac's pre-written `wg0.conf` gets the server's key by **copying it
down** — both in the same step, no human in the loop. The Mac's in-tunnel
address (v4 + v6) and the server's port ride along the same SSH read.

**Why SSH?** You already have authenticated SSH to the box you just created —
it's the one channel guaranteed present on a fresh server, so the installer needs
no extra secret or service to do the handoff.
→ [decisions/05-ssh-trust-model](client/decisions/05-ssh-trust-model.md) ·
  [decisions/06-automate-key-handoff-over-ssh](client/decisions/06-automate-key-handoff-over-ssh.md)

---

## Troubleshooting

Connected but something's off? Check in this order:

- **No handshake / won't connect** — UDP 443 isn't open in the cloud firewall, or the server IP / port / key is wrong.
- **Connects, but no internet** — IP forwarding or NAT isn't active on the server. *(Oracle's image also ships a default `FORWARD … REJECT` rule; `setup.sh` inserts WireGuard's accept rule above it.)*
- **Pages won't resolve** — DNS; check the `DNS =` line in your `wg0.conf`.
- **Real IP still showing on IPv6** (`curl ifconfig.me` ≠ `curl -4 ifconfig.me`) — the tunnel only routes IPv6 when the *server* has it (an IPv6 address on `wg0` + an ip6tables `MASQUERADE` rule); `install.sh` adds `::/0` only when it detects that. On an IPv4-only server, disable IPv6 on the Mac instead.

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
