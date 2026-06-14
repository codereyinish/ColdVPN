# Everything tenancy-specific lives here as variables — fill them in
# terraform.tfvars (copy terraform.tfvars.example). Nothing secret is committed.

variable "oci_profile" {
  description = "Profile name in ~/.oci/config to authenticate with"
  type        = string
  default     = "DEFAULT"
}

variable "region" {
  description = "OCI region, e.g. us-ashburn-1"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment to create resources in (root tenancy OCID is fine for a personal setup)"
  type        = string
}

variable "ssh_public_key" {
  description = "Your SSH PUBLIC key text (contents of ~/.ssh/id_ed25519.pub) — added to the VM so you can log in"
  type        = string
}

variable "instance_shape" {
  # E2.1.Micro (AMD, 1 OCPU/1GB) is the default because it's reliably available
  # on Always-Free — plenty for WireGuard. A1.Flex (Ampere ARM, up to 4 OCPU/24GB)
  # is more powerful but frequently fails apply with "Out of host capacity."
  description = "VM shape. Always-Free: VM.Standard.E2.1.Micro (AMD, reliable) or VM.Standard.A1.Flex (Ampere, bigger but often no capacity)."
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "instance_ocpus" {
  description = "OCPUs (only used by Flex shapes like A1.Flex). Always-Free A1 allows up to 4."
  type        = number
  default     = 1
}

variable "instance_memory_gb" {
  description = "Memory in GB (Flex shapes only). Always-Free A1 allows up to 24."
  type        = number
  default     = 6
}

variable "wg_port" {
  description = "UDP port WireGuard listens on (opened as an ingress rule)"
  type        = number
  default     = 443
}

variable "run_setup_on_boot" {
  description = "If true, the VM runs server/setup.sh on first boot (installs WireGuard automatically via cloud-init)"
  type        = bool
  default     = true
}

variable "setup_sh_url" {
  description = "Raw URL of setup.sh that cloud-init fetches when run_setup_on_boot = true"
  type        = string
  default     = "https://raw.githubusercontent.com/codereyinish/ColdVPN/main/server/setup.sh"
}
