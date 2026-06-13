# The network ColdVPN's server needs: a VCN, a public subnet reachable from the
# internet (internet gateway + route), and a firewall (security list) that opens
# SSH (so you can log in / install.sh can reach it) and the WireGuard UDP port.

resource "oci_core_vcn" "coldvpn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "coldvpn-vcn"
  dns_label      = "coldvpn"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.coldvpn.id
  display_name   = "coldvpn-igw"
}

resource "oci_core_route_table" "rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.coldvpn.id
  display_name   = "coldvpn-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_security_list" "sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.coldvpn.id
  display_name   = "coldvpn-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH — so you can log in and install.sh can SSH in to register the peer.
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6" # TCP
    tcp_options {
      min = 22
      max = 22
    }
  }

  # WireGuard.
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "17" # UDP
    udp_options {
      min = var.wg_port
      max = var.wg_port
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.coldvpn.id
  cidr_block        = "10.0.0.0/24"
  display_name      = "coldvpn-subnet"
  dns_label         = "sub"
  route_table_id    = oci_core_route_table.rt.id
  security_list_ids = [oci_core_security_list.sl.id]
}
