output "public_ip" {
  description = "The server's public IP — enter this as the Server IP when you run install.sh on your Mac"
  value       = oci_core_instance.vpn.public_ip
}

output "ssh" {
  description = "Ready-made SSH command"
  value       = "ssh ubuntu@${oci_core_instance.vpn.public_ip}"
}
