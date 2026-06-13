# Decision: automate server provisioning with Terraform (not a GUI agent, not raw `oci` CLI)

## The problem
Creating the server is the one step ColdVPN can't script today — you make the VM,
VCN, subnet, ingress rule, and SSH key by hand in the Oracle console
([CREATE-VM.md](../../server/CREATE-VM.md)). For a non-developer that's the
scariest part: a web console full of unfamiliar terms (compartment, VCN, security
list, ingress), lots of clicks, and it's easy to get impatient and give up when
you can't find the right button. So — can we automate it?

## First instinct: an agent that drives the web console
The obvious 2026 idea: a computer-use agent that logs into the Oracle console,
clicks "create instance," adds the ingress rule, and so on — the user just logs
in, passes the "I'm human" check, and watches. Tempting. Why not?

- **Signup can't be botted.** Account creation gates on phone/card/identity
  verification + CAPTCHA — built to stop exactly this. (Amazon-ordering agents
  work only because they reuse an *already-created* account; they don't bot
  signup either.)
- **Console GUIs change.** A click-bot breaks the moment Oracle redesigns a page.
- **Slower, flakier, costlier.** Screen-clicking is brittle and can hit mid-flow
  verification.
- **Too big a hammer.** Driving a GUI with a bot is *strictly worse* when a
  purpose-built door already exists ↓

It's also a huge solution for a problem with simpler answers.

## The purpose-built door: the API
Clouds expose an **API** for exactly this — the GUI is for humans, the API is for
machines. OCI has a first-class one. So we don't click (or bot clicks); we call
the API. Two ways to do that:

**Option A — the `oci` CLI (imperative).** Oracle's command-line tool; you write
every step and order yourself, and track what to delete:
```
oci network vcn create ...
oci network subnet create ...
oci compute instance launch ...
```

**Option B — Terraform (declarative) ← chosen.** You describe the *end result* in a
`.tf` file; Terraform works out the API calls and their order:
```hcl
resource "oci_core_vcn"      "main" { cidr_blocks = ["10.0.0.0/16"] ... }
resource "oci_core_subnet"   "main" { vcn_id = oci_core_vcn.main.id ... }
resource "oci_core_instance" "vpn"  { subnet_id = oci_core_subnet.main.id ... }
```

## How Terraform actually reaches OCI (it does *not* run `oci`)
Both tools hit the **same OCI REST API**, but with independent code — Terraform
never invokes the `oci` command:
```
oci CLI      ──(OCI Python SDK)──▶ HTTPS request ─┐
                                                   ├─▶ same OCI API ──▶ Oracle's backend ──▶ real VCN / VM
Terraform's  ──(OCI Go SDK)──────▶ HTTPS request ─┘     (SDN, hypervisors, DBs)
"OCI provider"
```
- The `oci` CLI is built on Oracle's **Python SDK**; Terraform's **OCI provider**
  plugin is built on the **Go SDK**. Two separate request-builders, one endpoint.
- You don't even need the `oci` CLI installed to run Terraform.
- The request lands on Oracle's API URL; **Oracle's own backend** builds the
  resources. No `oci` command runs server-side either — the CLI is only ever a
  client *you* might use, never part of the backend.

## Why Terraform over the CLI
1. **Simplicity** — describe *what* you want; no memorizing commands, flags, or the
   right order. Terraform plans the steps.
2. **Clean teardown (trial-and-destroy)** — Terraform tracks everything it created
   (its state file), so `terraform destroy` removes the whole stack in one
   command. With the CLI you'd hand-write commands to *find* and *delete* each
   resource. This is also what makes a throwaway test server cheap — `apply` to
   create it, `destroy` to remove it with no leftovers.

## Decision
Automate provisioning with **Terraform** (`server/provision/`). The human still
does the irreducible one-time bits — Oracle account signup + one API key — but
after that, `terraform apply` builds VCN → subnet → gateway → ingress → VM, and
`terraform destroy` tears it down. The GUI-agent route is rejected (fragile, can't
bot signup, worse than the API); raw `oci` CLI is rejected in favour of
Terraform's declarative simplicity and state-tracked teardown.
