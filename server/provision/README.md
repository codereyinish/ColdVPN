# Provision the server with Terraform

Stands up the whole Oracle server from nothing — VCN → subnet → internet gateway
→ firewall (SSH + WireGuard UDP) → Ubuntu VM — in one command, instead of clicking
through the console. Why Terraform (and not a GUI agent or the raw `oci` CLI):
[decision 08](../../client/decisions/08-provisioning-terraform.md).

## What you do by hand

One thing: **create a free Oracle Cloud account** at
<https://signup.cloud.oracle.com> (Always-Free is fine). Signup needs credit-card
+ SMS verification — Oracle requires a human and exposes no API for it, so this
step can't be scripted. It's the only manual step.

## Run it

```bash
cd server/provision
./provision.sh
```

`provision.sh` does everything else, with **nothing to paste**:

- installs the **OCI CLI** and **Terraform** if they're missing
- `oci setup bootstrap` — **one browser login**: it mints an API signing key,
  uploads it to your user, and writes `~/.oci/config` for you (so the user/tenancy
  OCIDs, region, key, and fingerprint are all filled in automatically)
- reads your tenancy OCID + region back out of that config, and generates an SSH
  key if you don't have one
- `terraform apply` — builds the network + VM
- **waits for the server to be ready** — the VM boots and cloud-init installs
  WireGuard in the background, so provision.sh polls until SSH answers *and*
  `wg show wg0` succeeds (the exact thing install.sh's key exchange needs)
- **offers to run `install.sh`** — once ready, it asks *"Configure this Mac
  now?"*. Say yes and it runs install.sh with the server IP handed over
  automatically (no copy-paste); say no and it prints the command to run later

So a fresh setup is really just: create an Oracle account → `./provision.sh` →
one browser login → answer "yes" to configure the Mac. Nothing typed or pasted
in between.

> `install.sh` reconfigures *this Mac* (needs your password, turns the VPN on),
> which is why the hand-off asks first rather than running silently.

### Driving Terraform yourself

`provision.sh` is just a wrapper. Once `~/.oci/config` exists (from
`oci setup bootstrap` or your own setup), you can run Terraform directly —
passing `compartment_ocid` + `ssh_public_key` via `terraform.tfvars` or
`TF_VAR_*` env vars, with region read from your config profile:

```bash
terraform init && terraform plan && terraform apply
```

## Under the hood — from credentials to a running server

**Two credentials, used in sequence.** A short-lived **session token** (earned by
your browser login) is used *once* to set up a permanent **API key** (a key pair);
the API key then signs everything Terraform does. The token solves a chicken-and-egg:
you can't use the API key until Oracle has registered it, and registering needs you
authenticated — so the login mints a one-time token to bridge the gap, then retires.

The API key's life in one line:

```
2a CREATED (on your Mac) → 2c REGISTERED (public half uploaded) → 3 USED (signs every call)
```

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#0f172a','primaryTextColor':'#e5e7eb','primaryBorderColor':'#475569','lineColor':'#94a3b8','fontSize':'13px'},'flowchart':{'nodeSpacing':40,'rankSpacing':45}}}%%
flowchart TB
    subgraph BOOT["oci setup bootstrap — set up the credential (one browser login)"]
        direction TB
        A["2a · CREATE the API key = a key pair, on your Mac<br/>private → ~/.oci/*.pem (never leaves) · public → held for now"]
        A --> B["2b · browser login: you type username + password + MFA<br/>(the key plays NO part here) → Oracle returns a SESSION TOKEN"]
        B --> C["2c · CLI calls Oracle, authenticated by the TOKEN:<br/>① read user + tenancy OCID + region<br/>② REGISTER (upload) the PUBLIC key on your user"]
        C --> D["2d · write ~/.oci/config (OCIDs · region · fingerprint · key path)<br/>API key now USABLE — session token expires & retires"]
    end

    D --> E(["terraform apply"])

    subgraph PERCALL["for every API call — now authenticated by the API KEY"]
        direction TB
        p1["build the request (e.g. create VCN)"] --> p2["SIGN with the PRIVATE key<br/>+ attach fingerprint + user OCID"]
        p2 --> p3["HTTPS → region endpoint (real Oracle, via TLS cert)"]
        p3 --> p4["Oracle: fingerprint → finds your PUBLIC key<br/>→ verifies signature → checks permissions"]
        p4 --> p5["CREATE → returns new OCID / public IP"]
    end
    E --> PERCALL
    PERCALL --> Z(["server built → public IP printed → run install.sh"])

    A -.->|"the secret half"| SEC
    subgraph SEC["PRIVATE key — how it's kept safe"]
        direction TB
        s1["~/.oci/*.pem · chmod 600 (only your user)"]
        s2["never leaves the Mac — only signatures are sent"]
        s3["no passphrase → Terraform signs unattended"]
        s4["FileVault encrypts it at rest"]
        s5["leaked? delete the key in the console → revoked instantly"]
    end

    style BOOT stroke:#3b82f6,color:#bfdbfe
    style PERCALL stroke:#8b5cf6,color:#c4b5fd
    style SEC stroke:#ef4444,color:#fecaca
```

Key idea: the **session token** (from your login) proves it's you *once*, just long
enough to register the key and read your IDs. After that the **API key pair** does
all the work — the private half *signs* each request, Oracle *verifies* with the
registered public half (the fingerprint tells it which key to check), and HTTPS
proves you're talking to real Oracle. That's what lets `terraform apply` build your
server safely on every call, unattended, with no further login.

## Tear it down

```bash
terraform destroy   # removes the VM + network it created, no leftovers
```

This is what makes a **throwaway test server** cheap: `apply` to create, `destroy`
to wipe — Terraform tracks everything it made, so nothing lingers or costs money.

## Notes
- **Always-Free A1 capacity**: `VM.Standard.A1.Flex` is in high demand and `apply`
  can fail with an out-of-capacity error. The default is the reliably-available
  `VM.Standard.E2.1.Micro`; switch with `instance_shape` in `terraform.tfvars`.
- `terraform.tfvars` and `*.tfstate` are git-ignored — `tfvars` (if you create it)
  may hold OCIDs/keys, and state holds resource details.
- Reusing an existing VCN instead of creating one? That's a different setup — this
  recipe creates its own network so `destroy` stays clean.
