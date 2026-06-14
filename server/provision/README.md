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

A browser login mints a key, Oracle stores its public half, and Terraform uses the
private half to sign every API call that builds your server. The private key is the
crown jewel — its safety branch is on the right.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#0f172a','primaryTextColor':'#e5e7eb','primaryBorderColor':'#475569','lineColor':'#94a3b8','fontSize':'13px'},'flowchart':{'nodeSpacing':40,'rankSpacing':45}}}%%
flowchart TB
    A(["oci setup bootstrap (one browser login)"]) --> B["Oracle authenticates you in the browser<br/>identifies WHO · WHICH account · WHERE — no pasting"]
    B --> C["mints a key pair + writes ~/.oci/config<br/>(user + tenancy OCID, region, fingerprint, key path)"]
    C --> D["uploads the PUBLIC key to your user automatically<br/>Oracle stores it, labelled by its fingerprint"]
    D --> E(["terraform apply"])
    E --> F["reads ~/.oci/config (credentials) + *.tf (desired infra)"]
    F --> G["plan: desired vs state (empty on first run)<br/>→ 'will create VCN, subnet, gateway, VM'"]
    G --> PERCALL

    subgraph PERCALL["for every API call (signed + verified)"]
        direction TB
        p1["build the request (e.g. create VCN)"] --> p2["SIGN with the PRIVATE key<br/>+ attach fingerprint + user OCID"]
        p2 --> p3["HTTPS → region endpoint (real Oracle, via TLS cert)"]
        p3 --> p4["Oracle: fingerprint → finds your PUBLIC key<br/>→ verifies signature → checks permissions"]
        p4 --> p5["CREATE → returns new OCID / public IP"]
        p5 --> p6["record in terraform.tfstate"]
    end

    PERCALL --> Z(["server built → public IP printed → run install.sh"])

    C -.->|"the secret half"| SEC
    subgraph SEC["PRIVATE key — how it's kept safe"]
        direction TB
        s1["~/.oci/*.pem · chmod 600 (only your user)"]
        s2["never leaves the Mac — only signatures are sent"]
        s3["no passphrase → Terraform signs unattended"]
        s4["FileVault encrypts it at rest"]
        s5["leaked? delete the key in the console → revoked instantly"]
    end

    style PERCALL stroke:#8b5cf6,color:#c4b5fd
    style SEC stroke:#ef4444,color:#fecaca
```

Key idea: the bootstrapped config says *who/which/where*, the key pair *proves it's
you* (private signs, public verifies, fingerprint picks the right key), and HTTPS
*proves you're talking to real Oracle*. Together that's what lets `terraform apply`
build your server safely on every call.

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
