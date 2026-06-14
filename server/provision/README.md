# Provision the server with Terraform

Stands up the whole Oracle server from nothing — VCN → subnet → internet gateway
→ firewall (SSH + WireGuard UDP) → Ubuntu VM — in one command, instead of clicking
through the console. Why Terraform (and not a GUI agent or the raw `oci` CLI):
[decision 08](../../client/decisions/08-provisioning-terraform.md).

> ⚠️ **Status: untested against a live tenancy.** The config is written but hasn't
> been `apply`-ed on a real account yet. Run `terraform plan` first and read it
> before `apply`. Treat the first run as the test.

## One-time setup (the human bits — can't be scripted)

1. **An Oracle Cloud account** (Always-Free is fine). Signup needs identity/card
   verification — there's no way around that.
2. **Terraform** — install the **prebuilt binary**:
   ```bash
   TFVER=$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform \
     | sed -n 's/.*"current_version":"\([^"]*\)".*/\1/p')
   ARCH=$([ "$(uname -m)" = "arm64" ] && echo arm64 || echo amd64)
   curl -fsSLO "https://releases.hashicorp.com/terraform/$TFVER/terraform_${TFVER}_darwin_${ARCH}.zip"
   unzip -o "terraform_${TFVER}_darwin_${ARCH}.zip" terraform
   sudo mv terraform /usr/local/bin/        # Apple Silicon: mv terraform /opt/homebrew/bin/
   terraform version
   ```
   > **Why not `brew install terraform`?** Homebrew dropped `terraform` from core
   > (HashiCorp's BUSL license change), and HashiCorp's tap **builds it from
   > source**, which needs current Xcode Command Line Tools — easy to be outdated.
   > The prebuilt binary has **nothing to compile**, so it sidesteps both. (If your
   > Command Line Tools are current, `brew install hashicorp/tap/terraform` also
   > works.)
3. **An API key** so Terraform can authenticate. Easiest:
   ```bash
   brew install oci-cli      # only needed for this one-time setup step
   oci setup config          # creates an API key + ~/.oci/config; upload the
                             # generated public key in the OCI console when prompted
   ```
   (You can also create the key by hand in the console and write `~/.oci/config`
   yourself — Terraform just reads that file. The `oci` CLI isn't used after this.)

## Run it

```bash
cd server/provision
cp terraform.tfvars.example terraform.tfvars   # then fill in your values
terraform init      # downloads the OCI provider
terraform plan      # preview — shows exactly what it will create, no changes
terraform apply     # builds it; prints the server's public IP
```

When `run_setup_on_boot = true` (the default), the VM runs `setup.sh` on first
boot via cloud-init, so WireGuard is installed automatically. Then on your Mac:

```bash
cd ../.. && ./install.sh        # use the public_ip Terraform printed
```

## Under the hood — from credentials to a running server

The whole flow, and *why* each step exists: you paste 3 IDs, a key is minted,
and Terraform uses it to sign every API call that builds your server. The private
key is the crown jewel — its safety branch is on the right.

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#0f172a','primaryTextColor':'#e5e7eb','primaryBorderColor':'#475569','lineColor':'#94a3b8','fontSize':'13px'},'flowchart':{'nodeSpacing':40,'rankSpacing':45}}}%%
flowchart TB
    A(["oci setup config (one-time)"]) --> B["you paste: user OCID + tenancy OCID + region<br/>= WHO · WHICH account · WHERE"]
    B --> C["generates a key pair + writes ~/.oci/config"]
    C --> D["you upload the PUBLIC key to the Oracle console<br/>Oracle stores it, labelled by its fingerprint"]
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
        s1["~/.oci/oci_api_key.pem · chmod 600 (only your user)"]
        s2["never leaves the Mac — only signatures are sent"]
        s3["no passphrase → Terraform signs unattended"]
        s4["FileVault encrypts it at rest"]
        s5["leaked? delete the key in the console → revoked instantly"]
    end

    style PERCALL stroke:#8b5cf6,color:#c4b5fd
    style SEC stroke:#ef4444,color:#fecaca
```

Key idea: the OCIDs say *who/which/where*, the key pair *proves it's you* (private
signs, public verifies, fingerprint picks the right key), and HTTPS *proves you're
talking to real Oracle*. Together that's what lets `terraform apply` build your
server safely on every call.

## Tear it down

```bash
terraform destroy   # removes the VM + network it created, no leftovers
```

This is what makes a **throwaway test server** cheap: `apply` to create, `destroy`
to wipe — Terraform tracks everything it made, so nothing lingers or costs money.

## Notes
- **Always-Free A1 capacity**: `VM.Standard.A1.Flex` is in high demand and `apply`
  can fail with an out-of-capacity error. Retry later, switch region, or set
  `instance_shape = "VM.Standard.E2.1.Micro"` in `terraform.tfvars`.
- `terraform.tfvars` and `*.tfstate` are git-ignored — they hold your OCIDs / key
  and resource details.
- Reusing an existing VCN instead of creating one? That's a different setup — this
  recipe creates its own network so `destroy` stays clean.
