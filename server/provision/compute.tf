# The VM itself. We look up an Ubuntu 22.04 image for the chosen shape, pick the
# first availability domain, and launch the instance on the public subnet with a
# public IP and your SSH key. Optionally, cloud-init runs setup.sh on first boot
# so WireGuard is installed the moment the box exists.

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  # cloud-init runs as root on first boot → setup.sh's root check passes, and it's
  # non-interactive, so it installs WireGuard unattended.
  cloud_init = <<-EOT
    #!/bin/bash
    set -e
    curl -fsSL ${var.setup_sh_url} | bash
  EOT
}

resource "oci_core_instance" "vpn" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "coldvpn-server"
  shape               = var.instance_shape

  # Flex shapes (e.g. A1.Flex) require ocpus/memory; fixed shapes (E2.1.Micro) reject it.
  dynamic "shape_config" {
    for_each = can(regex("Flex", var.instance_shape)) ? [1] : []
    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_gb
    }
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = var.run_setup_on_boot ? base64encode(local.cloud_init) : null
  }
}
