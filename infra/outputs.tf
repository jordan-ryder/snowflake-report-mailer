output "acs_endpoint" {
  description = "Hostname Snowflake POSTs to. Goes in secrets.local.toml as acs_host."
  value       = azurerm_communication_service.this.hostname
}

output "sender_address" {
  description = "Goes in secrets.local.toml as sender."
  value       = "donotreply@${var.sender_domain}"
}

output "dns_records" {
  description = "Add these at the registrar, then verify the domain in Azure."
  value       = azurerm_email_communication_service_domain.this.verification_records
}
