# Only the values that identify a specific tenant. Everything else is inline in
# main.tf - this repo is public, so these stay out of it.

variable "subscription_id" {
  description = "Azure subscription GUID"
  type        = string
}

variable "app_client_id" {
  description = "Entra app registration Snowflake authenticates as. Granted the ACS send role here; not created here."
  type        = string
}

variable "sender_domain" {
  description = "Domain to send from, e.g. reports.example.com. Use a dedicated subdomain: ACS requires an exact SPF record that would clash with an existing one on the root."
  type        = string
}
