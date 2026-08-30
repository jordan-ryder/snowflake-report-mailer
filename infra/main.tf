# Azure Communication Services email, sending from a verified custom domain.

resource "azurerm_resource_group" "this" {
  name     = "${var.prefix}-rg"
  location = var.location
}

resource "azurerm_email_communication_service" "this" {
  name                = "${var.prefix}-email"
  resource_group_name = azurerm_resource_group.this.name
  data_location       = var.data_location
}

resource "azurerm_communication_service" "this" {
  name                = "${var.prefix}-acs"
  resource_group_name = azurerm_resource_group.this.name
  data_location       = var.data_location
}

resource "azurerm_email_communication_service_domain" "this" {
  name              = var.sender_domain
  email_service_id  = azurerm_email_communication_service.this.id
  domain_management = "CustomerManaged"
}

# Azure refuses to link an unverified domain. Add the DNS records this emits,
# verify them, then set sender_domain_verified = true and apply again.
resource "azurerm_communication_service_email_domain_association" "this" {
  count                    = var.sender_domain_verified ? 1 : 0
  communication_service_id = azurerm_communication_service.this.id
  email_service_domain_id  = azurerm_email_communication_service_domain.this.id
}

data "azuread_service_principal" "sender" {
  client_id = var.app_client_id
}

# Scoped to this one ACS resource, not the tenant.
resource "azurerm_role_assignment" "sender" {
  scope                = azurerm_communication_service.this.id
  role_definition_name = "Communication and Email Service Owner"
  principal_id         = data.azuread_service_principal.sender.object_id
}
