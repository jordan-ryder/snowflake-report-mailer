output "acs_endpoint" {
  description = "Hostname Snowflake POSTs to. Feeds REPORT_CONFIG.acs_endpoint."
  value       = azurerm_communication_service.this.hostname
}

output "sender_address" {
  description = "MailFrom address; the custom domain when one is configured."
  value = var.custom_domain == null ? (
    "donotreply@${azurerm_email_communication_service_domain.this.mail_from_sender_domain}"
  ) : "donotreply@${var.custom_domain}"
}


output "custom_domain_dns_records" {
  description = "Add these at the registrar, then verify the domain in Azure."
  value       = try(azurerm_email_communication_service_domain.custom[0].verification_records, null)
}

