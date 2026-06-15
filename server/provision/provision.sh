#!/bin/bash
# =============================================================================
# provision.sh — stand up the ColdVPN server on Oracle Cloud (no copy-paste)
# =============================================================================
# The ONE thing you do by hand: create a free Oracle Cloud account at
# https://signup.cloud.oracle.com — Oracle requires a human for signup
# (credit-card + SMS verification, by design). Everything after is automated:
#
#   1. installs the OCI CLI and Terraform if they're missing
#   2. logs you into Oracle in the browser ONCE (`oci setup bootstrap`): this
#      generates an API signing key, uploads it to your user, and writes
#      ~/.oci/config for you — so there are NO OCIDs or keys to paste
#   3. reads your tenancy OCID + region back out of that config
#   4. generates an SSH key if you don't have one
#   5. runs Terraform to build the VM, network, and firewall
#
# Then run ./install.sh on this Mac with the IP this prints.
#
# Usage:  cd server/provision && ./provision.sh
# =============================================================================
set -e

RED=$'\033[91m'; GRN=$'\033[92m'; YLW=$'\033[93m'; BLU=$'\033[96m'; BLD=$'\033[1m'; DIM=$'\033[90m'; RST=$'\033[0m'
header() { echo ""; echo "${BLD}${BLU}── $1 ${RST}"; }
ok()   { echo "  ${GRN}✓${RST} $1"; }
info() { echo "  ${YLW}→${RST} $1"; }
die()  { echo ""; echo "  ${RED}✗ $1${RST}"; echo ""; exit 1; }

cd "$(dirname "$0")"
PROFILE="${OCI_PROFILE:-DEFAULT}"
OCI_CONFIG="$HOME/.oci/config"

# --- 1. OCI CLI ---------------------------------------------------------------
header "OCI CLI"
if command -v oci >/dev/null 2>&1; then
    ok "oci already installed"
else
    command -v brew >/dev/null 2>&1 || die "Homebrew not found — install it from https://brew.sh then re-run."
    info "installing oci-cli via Homebrew..."
    brew install oci-cli
    ok "oci-cli installed"
fi

# --- 2. Terraform -------------------------------------------------------------
header "Terraform"
if command -v terraform >/dev/null 2>&1; then
    ok "terraform already installed"
else
    # brew core dropped terraform and the tap needs Xcode CLT to compile, so we
    # drop the official prebuilt binary into ~/.local/bin (no sudo, no compiler).
    TF_VER="1.9.8"
    case "$(uname -m)" in arm64) TF_ARCH=arm64;; *) TF_ARCH=amd64;; esac
    info "installing Terraform ${TF_VER} (prebuilt binary → ~/.local/bin)..."
    mkdir -p "$HOME/.local/bin"
    TMP=$(mktemp -d)
    curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_darwin_${TF_ARCH}.zip" -o "$TMP/tf.zip"
    unzip -o -q "$TMP/tf.zip" -d "$TMP"
    mv "$TMP/terraform" "$HOME/.local/bin/terraform"
    chmod +x "$HOME/.local/bin/terraform"
    rm -rf "$TMP"
    export PATH="$HOME/.local/bin:$PATH"
    command -v terraform >/dev/null 2>&1 || die "terraform installed to ~/.local/bin but it's not on PATH — add it and re-run."
    ok "terraform ${TF_VER} installed (add ~/.local/bin to your PATH to keep it)"
fi

# --- 3. Oracle credentials (browser login, once) ------------------------------
header "Oracle credentials — one-time browser login"
if [ -f "$OCI_CONFIG" ] && grep -q "^\[$PROFILE\]" "$OCI_CONFIG"; then
    ok "~/.oci/config already has profile [$PROFILE] — skipping login"
else
    # The next command (oci setup bootstrap) fires 4 interactive prompts in a row.
    # Spell them out FIRST so they don't catch the user off guard, then pause so
    # they can read before the prompts start scrolling.
    echo ""
    echo "  ${BLD}You'll be asked 4 quick things — here's what to do:${RST}"
    echo ""
    echo "  ${BLU}1.${RST} ${BLD}Region${RST}  — type the number of your ${BLD}Home Region${RST} (the one you"
    echo "         picked at signup).  ${DIM}e.g.  72  for us-ashburn-1${RST}"
    echo ""
    echo "  ${BLU}2.${RST} ${BLD}macOS popup${RST}  \"Allow 'Python' to find devices on local networks?\""
    echo "         → click ${GRN}Allow${RST}.  ${YLW}⚠ Don't click \"Don't Allow\" — your browser login${RST}"
    echo "         ${YLW}can't get back to the tool and the whole thing hangs / aborts.${RST}"
    echo ""
    echo "  ${BLU}3.${RST} ${BLD}Browser opens${RST}  → log into Oracle → click ${GRN}Authorize${RST}."
    echo ""
    echo "  ${BLU}4.${RST} ${BLD}Passphrase${RST} prompt  → type ${GRN}N/A${RST}  (no passphrase, so this can run"
    echo "         later without asking you to unlock the key)."
    echo ""
    read -rp "  Press Enter to start the login... "
    echo ""
    oci setup bootstrap --profile-name "$PROFILE"
    [ -f "$OCI_CONFIG" ] || die "bootstrap finished but ~/.oci/config wasn't written."
    ok "credentials configured"
fi

# --- 4. read tenancy OCID + region from the config ----------------------------
# For a personal setup, resources go in the root compartment (= tenancy OCID).
# Terraform's region comes from the profile too (providers.tf no longer sets it).
read_cfg() {
    awk -v p="[$PROFILE]" -v k="$1" '
        /^\[/ { sec=$0 }
        sec==p && index($0, k"=")==1 { sub("^"k"=",""); gsub(/[ \t\r]/,""); print; exit }
    ' "$OCI_CONFIG"
}
TENANCY=$(read_cfg tenancy)
REGION=$(read_cfg region)
[ -n "$TENANCY" ] || die "couldn't read tenancy OCID from $OCI_CONFIG profile [$PROFILE]."
ok "tenancy ${BLU}${TENANCY}${RST}"
ok "region  ${BLU}${REGION}${RST}"

# --- 5. SSH key ---------------------------------------------------------------
header "SSH key"
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ -f "$SSH_KEY.pub" ]; then
    ok "using existing $SSH_KEY.pub"
else
    info "no SSH key found — generating $SSH_KEY"
    ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "coldvpn@$(hostname)"
    ok "SSH key generated"
fi

# --- 6. Terraform apply -------------------------------------------------------
# Credentials are fed to Terraform as TF_VAR_* env vars — nothing is written to
# terraform.tfvars, so no secrets land on disk in the repo.
header "Building the server with Terraform"
export TF_VAR_oci_profile="$PROFILE"
export TF_VAR_compartment_ocid="$TENANCY"
export TF_VAR_ssh_public_key="$(cat "$SSH_KEY.pub")"
terraform init -input=false
terraform apply -auto-approve

# --- 7. wait until the server is actually ready -------------------------------
# `apply` returns the moment the VM is CREATED, but it's still booting and
# cloud-init is installing WireGuard in the background. install.sh's key exchange
# reads the server's live wg0 key, so we wait for two things before handing off:
#   1. SSH answers (OS is up)
#   2. `wg show wg0` succeeds (setup.sh finished → WireGuard running, key exists)
# That second check is the EXACT condition the key exchange needs, so once it
# passes the hand-off can't run too early.
IP=$(terraform output -raw public_ip 2>/dev/null || true)
[ -n "$IP" ] || die "apply finished but no public IP in terraform output — check 'terraform output'."

SSH_DEST="ubuntu@${IP}"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes"

# Poll a command until it succeeds, giving up after $2 tries (5s apart) so a
# server that never comes up fails with a message instead of hanging forever.
wait_for() {
    local desc=$1 tries=$2 cmd=$3 n=0
    info "waiting for $desc..."
    until eval "$cmd" >/dev/null 2>&1; do
        n=$((n + 1))
        [ "$n" -ge "$tries" ] && return 1
        sleep 5
    done
    return 0
}

header "Waiting for the server to be ready (${IP})"
info "this takes ~1–2 min while it boots and installs WireGuard..."

# ~3 min for SSH, ~5 min for WireGuard (cloud-init pulls + runs setup.sh).
wait_for "SSH" 36 "ssh $SSH_OPTS $SSH_DEST true" \
    || die "SSH never came up at ${IP} — check the instance + security list in the OCI console, then re-run install.sh with SERVER_IP=${IP}."
ok "SSH is up"

wait_for "WireGuard (cloud-init runs setup.sh)" 60 "ssh $SSH_OPTS $SSH_DEST 'sudo wg show wg0'" \
    || die "WireGuard didn't come up. SSH in (ssh ${SSH_DEST}) and check 'sudo cloud-init status' / 'sudo wg show wg0', then re-run install.sh with SERVER_IP=${IP}."
ok "WireGuard is up — server is ready"

# --- 8. hand off to install.sh ------------------------------------------------
# Pass the IP + SSH user as env vars so install.sh skips its Step 6 prompts.
INSTALL_SH="$(cd ../.. && pwd)/install.sh"
header "Set up this Mac"
echo "  The server is ready at ${BLU}${IP}${RST}. install.sh will now configure"
echo "  THIS Mac to use it (needs your password; turns the VPN on)."
echo ""
printf "  ${BLD}Configure this Mac now? [Y/n]${RST} "
read -r REPLY
case "$REPLY" in
    [nN]*)
        info "skipped. To do it later, run:"
        echo "     ${YLW}SERVER_IP=${IP} ${INSTALL_SH}${RST}"
        ;;
    *)
        SERVER_IP="$IP" SSH_USER="ubuntu" "$INSTALL_SH"
        ;;
esac
