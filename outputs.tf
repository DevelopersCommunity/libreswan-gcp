output "server_address" {
  value       = var.hostname
  description = "Server address."
}

output "ipsec_identifier" {
  value       = var.ipsec_identifier
  description = "IPSec identifier."
}

output "ipsec_pre_shared_key" {
  value       = random_password.psk.result
  description = "IPSec pre-shared key."
  sensitive   = true
}