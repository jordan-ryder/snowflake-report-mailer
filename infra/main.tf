# Azure Communication Services email, sending from the free Azure-managed domain.
# No M365 tenant, no mailbox, no DNS records required.

resource "azurerm_resource_group" "this" {
  name     = "${var.prefix}-rg"
  location = var.location
}

resource "azurerm_email_communication_service" "this" {
  name                = "${var.prefix}-email"
  resource_group_name = azurerm_resource_group.this.name
  data_location       = var.data_location
}

# Azure-managed domain: provisions instantly, sends as donotreply@<random>.azurecomm.net.
# Swap domain_management to "CustomerManaged" later to send from your-domain.com.
resource "azurerm_email_communication_service_domain" "this" {
  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.this.id
  domain_management = "AzureManaged"
}

resource "azurerm_communication_service" "this" {
  name                = "${var.prefix}-acs"
  resource_group_name = azurerm_resource_group.this.name
  data_location       = var.data_location
}

resource "azurerm_communication_service_email_domain_association" "this" {
  communication_service_id = azurerm_communication_service.this.id
  email_service_domain_id  = azurerm_email_communication_service_domain.this.id
}

# The app registration Snowflake authenticates as. Created by hand, referenced here.
data "azuread_service_principal" "sender" {
  client_id = var.app_client_id
}

# Scoped to this one ACS resource, not the tenant. Replaces the tenant-wide
# Mail.Send grant that needed Global Admin consent.
resource "azurerm_role_assignment" "sender" {
  scope                = azurerm_communication_service.this.id
  role_definition_name = "Communication and Email Service Owner"
  principal_id         = data.azuread_service_principal.sender.object_id
}

# Managed domains are capped at 10 emails/hour and cannot be raised. A verified
# custom domain starts at 100/hour, with increases available on request.
resource "azurerm_email_communication_service_domain" "custom" {
  count             = var.custom_domain == null ? 0 : 1
  name              = var.custom_domain
  email_service_id  = azurerm_email_communication_service.this.id
  domain_management = "CustomerManaged"
}

# Azure refuses to link an unverified domain. Add the DNS records, verify in the
# portal, then set custom_domain_verified = true and apply again.
resource "azurerm_communication_service_email_domain_association" "custom" {
  count                    = var.custom_domain_verified ? 1 : 0
  communication_service_id = azurerm_communication_service.this.id
  email_service_domain_id  = azurerm_email_communication_service_domain.custom[0].id
}
