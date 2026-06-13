# The OCI provider authenticates with the API key you set up once via
# `oci setup config` (stored in ~/.oci/config). We read it by profile name —
# no secrets live in this repo. (Terraform talks to the OCI REST API directly
# through this provider; it does NOT shell out to the `oci` CLI.)
provider "oci" {
  config_file_profile = var.oci_profile
  region              = var.region
}
