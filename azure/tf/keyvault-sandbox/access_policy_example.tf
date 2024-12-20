terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.15.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

variable "tags" {
  type    = map(string)
  default = { Owner = "nathan.knox@databricks.com" }
}

variable "prefix" {
  type    = string
  default = "knoxsra"
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "subscription_id" {
  type    = string
  default = "edd4cc45-85c7-4aec-8bf5-648062d519bf"
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  # checkov:skip=CKV_TF_1
  source  = "Azure/naming/azurerm"
  version = "0.4.1"
}

# Get the application IDs for APIs published by Microsoft
data "azuread_application_published_app_ids" "well_known" {}
# Get the object id of the Azure DataBricks service principal
data "azuread_service_principal" "this" {
  client_id = data.azuread_application_published_app_ids.well_known.result["AzureDataBricks"]
}

data "azurerm_client_config" "current" {}

data "azurerm_databricks_workspace_private_endpoint_connection" "example" {
  workspace_id        = azurerm_databricks_workspace.example.id
  private_endpoint_id = azurerm_private_endpoint.databricks.id
}

resource "azurerm_resource_group" "example" {
  name     = module.naming.resource_group.name_unique
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "example" {
  name                = module.naming.virtual_network.name_unique
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "public" {
  name                 = "${module.naming.subnet.name_unique}-public"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "databricks-del-pub-${var.prefix}"

    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
      name = "Microsoft.Databricks/workspaces"
    }
  }
}

resource "azurerm_subnet" "private" {
  name                 = "${module.naming.subnet.name_unique}-private"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "databricks-del-pri"

    service_delegation {
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
      name = "Microsoft.Databricks/workspaces"
    }
  }
}

resource "azurerm_subnet" "endpoint" {
  name                 = "${module.naming.subnet.name_unique}-endpoint"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.3.0/24"]

  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.example.id
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.example.id
}

resource "azurerm_network_security_group" "example" {
  name                = module.naming.network_security_group.name_unique
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_databricks_workspace" "example" {
  name                = module.naming.databricks_workspace.name_unique
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  sku                 = "premium"

  customer_managed_key_enabled          = true
  managed_services_cmk_key_vault_key_id = azurerm_key_vault_key.example.id
  public_network_access_enabled         = false
  network_security_group_rules_required = "NoAzureDatabricksRules"

  custom_parameters {
    no_public_ip        = true
    public_subnet_name  = azurerm_subnet.public.name
    private_subnet_name = azurerm_subnet.private.name
    virtual_network_id  = azurerm_virtual_network.example.id

    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.private.id
  }

  tags = var.tags
}

resource "azurerm_databricks_workspace_root_dbfs_customer_managed_key" "example" {
  depends_on = [azurerm_key_vault_access_policy.databricks]

  workspace_id     = azurerm_databricks_workspace.example.id
  key_vault_key_id = azurerm_key_vault_key.example.id
}

resource "azurerm_private_endpoint" "databricks" {
  depends_on = [azurerm_databricks_workspace_root_dbfs_customer_managed_key.example]

  name                = "${module.naming.private_endpoint.name_unique}-pe-databricks"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  subnet_id           = azurerm_subnet.endpoint.id

  private_service_connection {
    name                           = "psc"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_databricks_workspace.example.id
    subresource_names              = ["databricks_ui_api"]
  }
}

resource "azurerm_private_dns_zone" "example" {
  depends_on = [azurerm_private_endpoint.databricks]

  name                = "privatelink.azuredatabricks.net"
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_private_dns_cname_record" "example" {
  name                = azurerm_databricks_workspace.example.workspace_url
  zone_name           = azurerm_private_dns_zone.example.name
  resource_group_name = azurerm_resource_group.example.name
  ttl                 = 300
  record              = "eastus2-c2.azuredatabricks.net"
}

resource "azurerm_key_vault" "example" {
  name                     = "${module.naming.key_vault.name_unique}-keyvault"
  location                 = azurerm_resource_group.example.location
  resource_group_name      = azurerm_resource_group.example.name
  tenant_id                = data.azurerm_client_config.current.tenant_id
  sku_name                 = "premium"
  purge_protection_enabled = true

  soft_delete_retention_days = 7
}

resource "azurerm_key_vault_key" "example" {
  depends_on = [azurerm_key_vault_access_policy.terraform]

  name         = "${var.prefix}-certificate"
  key_vault_id = azurerm_key_vault.example.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
}

resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.example.id
  tenant_id    = azurerm_key_vault.example.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get",
    "List",
    "Create",
    "Decrypt",
    "Encrypt",
    "Sign",
    "UnwrapKey",
    "Verify",
    "WrapKey",
    "Delete",
    "Restore",
    "Recover",
    "Update",
    "Purge",
    "GetRotationPolicy",
    "SetRotationPolicy",
  ]
}

resource "azurerm_key_vault_access_policy" "databricks" {
  depends_on = [azurerm_databricks_workspace.example]

  key_vault_id = azurerm_key_vault.example.id
  tenant_id    = azurerm_databricks_workspace.example.storage_account_identity[0].tenant_id
  object_id    = azurerm_databricks_workspace.example.storage_account_identity[0].principal_id

  key_permissions = [
    "Get",
    "UnwrapKey",
    "WrapKey",
  ]
}

resource "azurerm_key_vault_access_policy" "managed" {
  depends_on   = [data.azuread_service_principal.this]
  key_vault_id = azurerm_key_vault.example.id
  tenant_id    = azurerm_key_vault.example.tenant_id
  object_id    = data.azuread_service_principal.this.object_id

  key_permissions = [
    "Get",
    "UnwrapKey",
    "WrapKey",
  ]
}

output "databricks_sp_client_id" {
  value = data.azuread_service_principal.this.client_id
}

output "databricks_workspace_private_endpoint_connection_workspace_id" {
  value = data.azurerm_databricks_workspace_private_endpoint_connection.example.workspace_id
}

output "databricks_workspace_private_endpoint_connection_private_endpoint_id" {
  value = data.azurerm_databricks_workspace_private_endpoint_connection.example.private_endpoint_id
}

output "databricks_workspace_private_endpoint_connection_name" {
  value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections[0].name
}

output "databricks_workspace_private_endpoint_connection_workspace_private_endpoint_id" {
  value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections[0].workspace_private_endpoint_id
}

output "databricks_workspace_private_endpoint_connection_status" {
  value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections[0].status
}

output "databricks_workspace_private_endpoint_connection_description" {
  value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections[0].description
}

output "databricks_workspace_private_endpoint_connection_action_required" {
  value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections[0].action_required
}
