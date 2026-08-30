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
  description = "Entra app registration Snowflake authenticates as. Granted the ACS send role here; not created here."
  type        = string
}

variable "sender_domain" {
  description = "Domain to send from, e.g. reports.example.com. Use a dedicated subdomain: ACS requires an exact SPF record that would clash with an existing one on the root."
  type        = string
}

variable "sender_domain_verified" {
  description = "Set true once the DNS records are verified in Azure."
  type        = bool
  default     = false
}
