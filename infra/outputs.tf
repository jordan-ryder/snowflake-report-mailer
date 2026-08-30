output "acs_endpoint" {
  description = "Hostname Snowflake POSTs to. Feeds REPORT_CONFIG.acs_endpoint."
  value       = azurerm_communication_service.this.hostname
}

output "sender_address" {
  description = "MailFrom address on the Azure-managed domain."
  value       = "donotreply@${azurerm_email_communication_service_domain.this.mail_from_sender_domain}"
}

output "snowflake_config_sql" {
  description = "Paste into Snowflake once applied."
  value       = <<-EOT
    update SENTIMENT.REPORTING.REPORT_CONFIG set value = '${azurerm_communication_service.this.hostname}' where key = 'acs_endpoint';
    update SENTIMENT.REPORTING.REPORT_CONFIG set value = 'donotreply@${azurerm_email_communication_service_domain.this.mail_from_sender_domain}' where key = 'sender_mailbox';
  EOT
}
