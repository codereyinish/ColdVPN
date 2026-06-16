# ColdVPN — end-to-end flow

How one command turns *"I have an Oracle account"* into *"all my Mac traffic exits
through my own server."* This is the living reference for the whole pipeline.

> One manual thing only: **create a free Oracle account** (signup needs card + SMS).
> Everything below is automated by `./provision.sh`.

---

## The whole flow, top to bottom

```
provision.sh   ← you run this
│
├─ 1 · prepare tools
│      installs the OCI CLI + Terraform if missing
│
├─ 2 · oci setup bootstrap   ← set up credentials (ONE browser login, first time only)
│      │
│      ├─ 2a  CREATE the API key  = a private+public key pair, made ON THE MAC
│      │        private → ~/.oci/*.pem (chmod 600, never leaves the Mac)
│      │        public  → held for now (not on Oracle yet)
│      │
│      ├─ 2b  browser opens + the CLI waits
│      │        you type username + password + MFA, click Authorize
│      │        (the key plays NO part in login) → Oracle returns a SESSION TOKEN
│      │
│      ├─ 2c  using the SESSION TOKEN, the CLI calls Oracle:
│      │        ① read identity → user OCID · tenancy OCID · region
│      │        ② REGISTER (upload) the PUBLIC key on your user
│      │
│      └─ 2d  save the PRIVATE key to disk (passphrase = N/A) + write ~/.oci/config
│             → the API key is now USABLE; the session token expires & retires
│
│      Re-runs SKIP this whole step: if ~/.oci/config exists, the key is REUSED
│      (no new upload). Oracle caps you at 3 API keys per user, so we never make
│      a new one we don't need.
│
├─ 3 · SSH key
│      reuse ~/.ssh/id_ed25519 if it exists, else generate it ONCE.
│      its PUBLIC half → Terraform (TF_VAR_ssh_public_key), to plant on the VM.
│
├─ 4 · terraform apply   ← first real use of the API key
│      reads ~/.oci/config, SIGNS each call with the PRIVATE key (Oracle verifies
│      with the registered PUBLIC key), and builds:
│      VCN → subnet → internet gateway → route table → firewall → VM
│      injects your SSH PUBLIC key onto the VM (see "SSH" below). Nothing else is
│      installed at boot — WireGuard comes in step 4, pushed from the Mac.
│      (progress shown as a bar; full output → server/provision/provision.log)
│
│   ⤷ provision.sh's READINESS WAIT sits here: it polls until SSH answers — that's
│      all it needs now, since WireGuard isn't installed until the next step.
│
├─ 5 · install.sh runs ON THE MAC   (server IP handed over automatically — no prompt)
│      installs Homebrew + wireguard-tools (→ wireguard-go, userspace) + SwiftBar
│      generates the MAC key pair (private → Mac's wg0.conf only)
│
│      INSTALL WIREGUARD ON THE SERVER — by PUSHING setup.sh over SSH:
│          ssh ubuntu@<ip> 'sudo bash -s' < server/setup.sh
│          → the SCRIPT isn't downloaded (pushed from the Mac, no GitHub). But it
│            apt-installs WireGuard, which DOES need the server's DNS — and sshd
│            comes up before DNS is ready, so setup.sh first WAITS until the VM can
│            resolve the package mirrors, then apt-installs.
│          → server installs wireguard + wireguard-tools + iptables (KERNEL module),
│            generates its key, writes /etc/wireguard/wg0.conf [Interface] ONLY
│            (key · 10.8.0.1/24 +::1/64 · :443 · NAT PostUp), starts wg-quick@wg0
│          → skipped entirely if wg0 already exists (never re-keyed)
│
│      KEY EXCHANGE over the same SSH:
│          PULL ← server's public key + ListenPort + wg0 address
│          PUSH → add the Mac's public key into the server's wg0.conf as [Peer]
│                 → restart wg-quick@wg0 on the server
│      writes the Mac's wg0.conf:
│          [Interface] Mac private key · Address 10.8.0.2/32 (+IPv6) · DNS
│          [Peer] server public key · Endpoint <ip>:443 · AllowedIPs 0.0.0.0/0 (+::/0)
│      installs: toggle script + passwordless sudoers rule + SwiftBar plugin
│
└─ 6 · tunnel up:  wg-quick up wg0
       all Mac traffic now exits through your server
       MANUAL by design — no boot service; OFF after reboot until you toggle it
       menu bar: coldvpn.5s.sh refreshes 🟢/🔴 every 5s; a click runs the toggle
       (wg-quick up/down, which needs the sudoers rule)
```

---

## The credential handshake (step 2, in depth)

The puzzle bootstrap solves: you can't use an API key until Oracle has registered
it, and you can't register it without being authenticated. So **two credentials are
used in sequence** — a temporary one to set up the permanent one.

```
session token   ─ from your browser LOGIN (username+password+MFA), short-lived,
                  used ONCE to register the key + read your IDs, then expires
API key pair    ─ generated locally, permanent, signs EVERY Terraform call after
```

Lifecycle of the API key:

```
2a CREATED (on your Mac) → 2c REGISTERED (public half uploaded) → 3 USED (signs calls)
```

Key facts:
- An OCI **"API key" is just an RSA key pair** — like an SSH key. Private stays on
  the Mac; public is registered on Oracle. The **fingerprint** in `~/.oci/config`
  is the public key's ID tag (so Oracle knows which key to verify against).
- The browser login hands the result **back to the waiting CLI** (it opened a local
  listener — that's what the macOS "Allow Python… on local networks" popup is for;
  you must click **Allow** or the login can't return).
- The passphrase prompt (`N/A`) only asks whether to encrypt the **local** key file.
  We skip it so Terraform can run unattended; the file is already protected by
  `chmod 600` + FileVault.

---

## The three key pairs (don't mix them up)

Same private-signs / public-verifies idea each time — three different doors.

| key pair | private lives | public lives | unlocks |
|---|---|---|---|
| **OCI API key** | Mac `~/.oci` | your Oracle account | making API calls (Terraform builds infra) |
| **SSH key** | Mac `~/.ssh` | the VM (`ubuntu`'s authorized_keys) | logging into the VM |
| **WireGuard keys** | each end | the other end | the encrypted VPN tunnel |

---

## How SSH into the new VM "just works"

We never configure SSH by hand — Terraform plants the key at creation:

1. `provision.sh` ensures `~/.ssh/id_ed25519` exists and feeds the **public** half
   to Terraform (`TF_VAR_ssh_public_key`).
2. `compute.tf` sets it as instance metadata: `ssh_authorized_keys = var.ssh_public_key`.
3. Oracle's Ubuntu image already has a default **`ubuntu`** user (passwordless sudo);
   cloud-init drops your public key into its `authorized_keys` at boot.
4. So `ssh ubuntu@<ip>` logs in with **no password** — your Mac proves it holds the
   private key, the server has the matching public key.

---

## Checkpoints / safe to re-run

A failure doesn't force a from-scratch redo — each stage records state that makes
re-running safe (idempotent), so you resume rather than restart:

| stage | checkpoint | on re-run |
|---|---|---|
| credentials | `~/.oci/config` | skip bootstrap, reuse the key (no new upload) |
| SSH key | `~/.ssh/id_ed25519` | reuse |
| server infra | `terraform.tfstate` | no-op if built; only creates what's missing |
| WireGuard on server | `wg show wg0` check | skip setup.sh if up; setup.sh is *key-preserving* (never re-keys) |
| Mac client | *(none, intentional)* | wiped + rewritten fresh each run (cheap, single-client) |

Resume points:
- **server build failed** → re-run `provision.sh` (Terraform resumes from state).
- **setup / client failed** → re-run `install.sh` alone (`SERVER_IP=<ip> ./install.sh`)
  — no rebuild; setup.sh re-runs idempotently, the Mac peer is re-registered (REPLACE).

### Re-running by mistake = no duplication

Terraform doesn't "create a server" — it makes reality MATCH the config, tracking
what it built in `terraform.tfstate`. Each `apply` only creates what's **missing**:

```
desired (*.tf)  vs  what exists (terraform.tfstate)  →  create only the gap
```

- Server already in state → `apply` is a **no-op** ("No changes"). Run `provision.sh`
  100× → still **exactly one server**. (A console "create instance" would duplicate;
  Terraform won't.)
- Bootstrap is skipped when `~/.oci/config` exists → **no extra API key uploaded**.
- `install.sh` has **no Terraform at all** — it can't create a server, only reconfigure
  the Mac + re-register the single peer. Re-running it is harmless.

**Caveat — the guard lives in `terraform.tfstate`** (git-ignored, kept locally). Delete
that file, or run on a *different machine* without it, and Terraform forgets the server
exists → it WOULD build a **duplicate**. Keep the state file; it's the source of truth
for "what I already created."

## Output / logging

Both driver scripts keep the screen clean and stream verbose detail to a log:
- **provision.sh** → Terraform output goes to `server/provision/provision.log`; the
  screen shows a full-width `####` bar (terminal width measured once up front, since
  the bar renders inside a pipe subshell where `tput cols` can't read the terminal).
- **setup.sh** (on the server) → apt/systemctl output goes to `/var/log/coldvpn-setup.log`;
  the screen shows a per-step `####` bar. It's printed fresh each step (no in-place
  cursor tricks) because it's piped back over SSH.
- On failure, both print the tail of their log so errors aren't hidden.

## Notes / gotchas

- **Nothing is downloaded on the server, by design.** `install.sh` PUSHES the local
  `server/setup.sh` over SSH (`sudo bash -s < setup.sh`), so the VM never fetches
  anything at boot — no GitHub dependency and no boot-time DNS race (which used to
  fail with "Could not resolve host" and silently skip WireGuard). Bonus: it runs
  the exact `setup.sh` from the repo you cloned, not whatever's on `main`.
- **`created ≠ ready`.** `terraform apply` returns when the VM exists, but it's still
  booting. The readiness wait holds until SSH answers before handing to install.sh
  (which then installs WireGuard + does the key exchange).
- **API-key quota.** Oracle allows 3 keys per user; each bootstrap (or Ctrl-C'd
  attempt) uploads one. provision.sh reuses the existing key and, on quota failure,
  prints how to delete old ones.
