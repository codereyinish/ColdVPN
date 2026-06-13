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
2. **Terraform**: `brew install terraform`
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
