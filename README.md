# ColdVPN

A **self-hosted WireGuard VPN** for your Mac. Route *all* your traffic through a
cloud server **you own** — instead of trusting a third-party VPN provider.

```
your Mac → [WireGuard encrypted tunnel] → your server → internet
```

Everything's local and yours: your own app (SwiftBar), your own free server
(Oracle Always-Free), and easy to install — just log in once to create the server.

## What it hides

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#0f172a','primaryTextColor':'#e5e7eb','primaryBorderColor':'#475569','lineColor':'#94a3b8','fontSize':'13px'}}}%%
flowchart LR
    You["you<br/>(café / public Wi-Fi)"] -->|"locked tunnel"| Srv["your own server"]
    Srv --> Net["your bank's site"]
    Snoop["someone on the same Wi-Fi"] -.->|"sees only: you ↔ your server,<br/>can't read inside"| You
    Net -.->|"sees your server,<br/>not your real location"| Srv
```

On café, airport, or hotspot Wi-Fi, anyone on the same network can see which sites
you're connecting to. Turn ColdVPN on and all your traffic — even the lookups that find
each site — runs through one locked tunnel to your own server. Now they see only
"connected to my server": not that you opened your bank, and they can't redirect or
block you along the way.

Your bank, in turn, sees your server's address — not your real IP or location. (Your
password was already safe; bank sites are encrypted. What ColdVPN adds is hiding *which*
sites you visit, and from where.)

That's the core of it — not a full commercial VPN. For what it deliberately *doesn't*
do, see [Limitations](#limitations) below.

---

## Setup

Create an Oracle account, then run one command — everything else is automatic.

### 1 · Create a free Oracle Cloud account

The only manual step: <https://signup.cloud.oracle.com>. Signup needs card + SMS.

What you'll go through:

1. Email + country + name → verify your email
2. Set a password + an account name
3. **Choose a Home Region** — pick one near you. It's **permanent** on a free account,
   and your server must live in it, so remember which you pick.
4. Phone / SMS code
5. Credit card (identity check only — Always-Free doesn't charge you)
6. Accept → the account provisions in a few minutes, then the console loads

You'll re-enter that **Home Region** when `provision.sh` asks for a region in step 2.

### 2 · Run it — one command builds the server *and* sets up your Mac

```bash
git clone https://github.com/codereyinish/ColdVPN.git
cd ColdVPN/server/provision
./provision.sh
```

`provision.sh` does the rest, with nothing to paste:

- installs the **OCI CLI** + **Terraform** if they're missing
- **one browser login** (`oci setup bootstrap`): you log in and click *Authorize*;
  it generates an API key (a key pair) on your Mac, registers the **public** half
  on your account, and fills in `~/.oci/config` — no OCIDs or keys typed
- **Terraform** builds the VM + network, then **waits** until the server is ready
  (it's still installing WireGuard in the background)
- asks **"Configure this Mac now?"** → runs `install.sh` with the server IP handed
  over automatically, so you never copy-paste it

During the login the script walks you through four one-time prompts: pick your
**Home Region**, click **Allow** on the macOS *"Allow Python…"* popup (don't skip it
— the login needs it), **log in + Authorize** in the browser, and type **`N/A`** at
the passphrase prompt. After that it's hands-off.

→ how it works, step by step: [server/provision](server/provision)
([why Terraform](client/decisions/08-provisioning-terraform.md)).

**Prefer to do it by hand?** Create the VM in the console
([server/CREATE-VM.md](server/CREATE-VM.md)), then run `./install.sh` from the repo
root — it asks for the **server IP** and **SSH user** (`ubuntu`).

When it finishes, the **ColdVPN** button shows up in your menu bar — click it to
switch the tunnel on or off:

| off | on |
|:---:|:---:|
| <img src="docs/menubar-off.png" alt="ColdVPN menu bar, disconnected" width="260"> | <img src="docs/menubar-on.png" alt="ColdVPN menu bar, connected via Oracle" width="260"> |

### Test it's working

```bash
curl ifconfig.me
```

It should print your **server's IP** — not your home one. Click the menu-bar
button to toggle the tunnel off and back on.

**Visualize the flow above →** [How setup works](#how-setup-works)

---

## How setup works

Left to right: your one command to a live tunnel. Each numbered stage opens up
into what happens inside it.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#0f172a','primaryTextColor':'#e5e7eb','primaryBorderColor':'#475569','lineColor':'#94a3b8','fontSize':'14px'}}}%%
flowchart LR
    subgraph MAC["MAC — install.sh drives everything"]
        direction TB
        Start(["./install.sh"]) --> S1
        S1 --> CP["CHECKPOINT —<br/>enter server IP + SSH user"]
        CP --> SSH["SSH into the server"]
        SSH --> Q{"wg0 exists?"}
        S3 --> S4
        S4 --> Done(["tunnel up"])

        subgraph S1["① set up the Mac"]
            direction TB
            a1["install wireguard-tools + SwiftBar"] --> a2["generate Mac key pair"]
        end
        subgraph S3["③ exchange keys (over SSH)"]
            direction TB
            c1["Mac pubkey → server peer"] --> c2["server pubkey → Mac wg0.conf"]
        end
        subgraph S4["④ finish on the Mac"]
            direction TB
            d1["write wg0.conf"] --> d2["toggle + menu-bar button"]
        end
    end

    Q -->|"fresh"| b1
    Q -->|"existing"| SKIP
    b4 --> S3
    SKIP --> S3

    subgraph ORACLE["CLOUD — Oracle server · ② setup.sh (fresh only)"]
        direction TB
        b1["apt install wireguard"] --> b2["reuse or generate server key"]
        b2 --> b3["write dual-stack wg0.conf + NAT"]
        b3 --> b4["start wg-quick@wg0"]
        SKIP["skip setup — never re-keyed"]
    end

    style MAC fill:none,stroke:#3b82f6,stroke-width:2px,color:#3b82f6
    style ORACLE fill:none,stroke:#8b5cf6,stroke-width:2px,color:#8b5cf6
    style S1 fill:none,stroke:#3b82f6
    style S3 fill:none,stroke:#3b82f6
    style S4 fill:none,stroke:#3b82f6
```

**Go deeper:** ① [Mac client build](client/ARCHITECTURE.md) + [why not the WireGuard app](client/decisions/03-cli-vs-app.md) · ② [setup.sh](server/setup.sh) + [how the VM is made](server/CREATE-VM.md) · ③ [why SSH is automated](client/decisions/06-automate-key-handoff-over-ssh.md) + [SSH trust & flaws](client/decisions/05-ssh-trust-model.md) · ④ [client build](client/ARCHITECTURE.md)

**Once it's running:** 📦 [how a packet actually flows](client/PACKET-FLOW.md) (Mac → carrier → Oracle, the two NATs, and back) · 🏗️ [the Oracle network you create](server/CREATE-VM.md) (VCN → subnet → ingress → VM)

---

## Limitations

**What it does *not* hide:** the site still sees whatever your **browser/app** sends — User-Agent, cookies, logins, TLS/browser fingerprint. The server just **forwards** your packets; it doesn't add *or* strip those. So ColdVPN hides your **network identity (IP/location)**, not your **app-level identity**. For that you'd need browser-level defenses (private mode, anti-fingerprint browser), which are out of scope here.

**One location, fixed at signup.** You exit through the single Oracle region you chose when creating the account — and that region is **permanent** on the free tier. You can't switch countries on the fly. To appear somewhere else you'd create a second Oracle account, stand up a server in that region, and run the setup again.

**It's not an ad blocker.** A VPN changes your address, not what loads on a page — so ColdVPN doesn't stop cross-site tracking on its own *(a Pi-hole option on the server, to block known tracker domains, is planned)*. And it **can't block YouTube ads at all**: YouTube serves its ads from the **same domains as the videos themselves**, so there's no ad domain to block — cut it and you cut the video too. Killing YouTube ads needs browser/app-level tools (uBlock Origin, ReVanced), not a VPN.

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
