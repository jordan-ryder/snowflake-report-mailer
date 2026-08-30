variable "subscription_id" {
  description = "Azure subscription GUID"
  type        = string
}

variable "location" {
  description = "Azure region for the resource group"
  type        = string
  default     = "eastus"
}

variable "data_location" {
  description = "Where Communication Services stores data at rest. Not the same as location."
  type        = string
  default     = "United States"
}

variable "prefix" {
  description = "Name prefix for all resources"
  type        = string
  default     = "snowreports"
}

variable "app_client_id" {
  description = <<-EOT
    Application (client) ID of the existing Entra app registration that Snowflake
    authenticates as. Terraform grants this app the ACS send role; it does not
    create the app.
  EOT
  type        = string
}

variable "custom_domain" {
  description = "Domain to send from, e.g. example.com. Null uses the Azure-managed domain only."
  type        = string
  default     = null
}

variable "custom_domain_verified" {
  description = "Set true once the custom domain's DNS records are verified in Azure."
  type        = bool
  default     = false
}
