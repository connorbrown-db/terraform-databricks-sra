# terraform {
#   required_version = ">= 1.0.0"
#   required_providers {
#     azuread = {
#       source  = "hashicorp/azuread"
#       version = ">= 2.15.0"
#     }
#     azurerm = {
#       source  = "hashicorp/azurerm"
#       version = ">= 3.7.0, < 4.0.0"
#     }
#     random = {
#       source  = "hashicorp/random"
#       version = ">= 3.5.0, < 4.0.0"
#     }
#   }
# }
#
# variable "location" {
#   type    = string
#   default = "westus2"
# }
#
# variable "subscription_id" {
#   type    = string
#   default = "edd4cc45-85c7-4aec-8bf5-648062d519bf"
# }
#
# provider "azurerm" {
#   features {}
#   subscription_id = var.subscription_id
# }
#
# # We need the tenant id.
# data "azurerm_client_config" "this" {}
#
#
# # This ensures we have unique CAF compliant names for our resources.
# module "naming" {
#   # checkov:skip=CKV_TF_1
#   source  = "Azure/naming/azurerm"
#   version = "0.4.1"
# }
#
# # This is required for resource modules
# resource "azurerm_resource_group" "this" {
#   location = var.location
#   name     = module.naming.resource_group.name_unique
# }
#
# #Key Vault needed for CMK
# resource "azurerm_key_vault" "this" {
#   location = azurerm_resource_group.this.location
#   # checkov:skip=CKV_AZURE_109: This is a test resource
#   # checkov:skip=CKV_AZURE_189: This is a test resource
#   name                = module.naming.key_vault.name_unique
#   resource_group_name = azurerm_resource_group.this.name
#   sku_name            = "standard"
#   tenant_id           = data.azurerm_client_config.this.tenant_id
#   # enable_rbac_authorization  = true
#   purge_protection_enabled   = true
#   soft_delete_retention_days = 7
# }
#
# # Create keys for CMK
# resource "azurerm_key_vault_key" "cmkms" {
#   key_opts = [
#     "decrypt",
#     "encrypt",
#     "sign",
#     "unwrapKey",
#     "verify",
#     "wrapKey",
#   ]
#   # checkov:skip=CKV_AZURE_112
#   # checkov:skip=CKV_AZURE_40
#   key_type     = "RSA"
#   key_vault_id = azurerm_key_vault.this.id
#   name         = "${module.naming.key_vault_key.name_unique}-cmkms"
#   key_size     = 2048
#
#   rotation_policy {
#     expire_after         = "P90D"
#     notify_before_expiry = "P29D"
#
#     automatic {
#       time_before_expiry = "P30D"
#     }
#   }
#
#   depends_on = [azurerm_role_assignment.current_user]
# }
#
#
# resource "azurerm_key_vault_key" "managed_disk_cmk" {
#   key_opts = [
#     "decrypt",
#     "encrypt",
#     "sign",
#     "unwrapKey",
#     "verify",
#     "wrapKey",
#   ]
#   # checkov:skip=CKV_AZURE_112
#   # checkov:skip=CKV_AZURE_40
#   key_type     = "RSA"
#   key_vault_id = azurerm_key_vault.this.id
#   name         = "${module.naming.key_vault_key.name_unique}-cmkds"
#   key_size     = 2048
#
#   rotation_policy {
#     expire_after         = "P90D"
#     notify_before_expiry = "P29D"
#
#     automatic {
#       time_before_expiry = "P30D"
#     }
#   }
#
#   depends_on = [azurerm_role_assignment.current_user]
# }
#
# # create a key vault key for the DBFS encryption
# resource "azurerm_key_vault_key" "dbfs_root" {
#   key_opts = [
#     "decrypt",
#     "encrypt",
#     "sign",
#     "unwrapKey",
#     "verify",
#     "wrapKey",
#   ]
#   # checkov:skip=CKV_AZURE_112
#   # checkov:skip=CKV_AZURE_40
#   key_type     = "RSA"
#   key_vault_id = azurerm_key_vault.this.id
#   name         = "${module.naming.key_vault_key.name_unique}-dbfs-root"
#   key_size     = 2048
#
#   rotation_policy {
#     expire_after         = "P90D"
#     notify_before_expiry = "P29D"
#
#     automatic {
#       time_before_expiry = "P30D"
#     }
#   }
#
#   depends_on = [azurerm_role_assignment.current_user, azurerm_role_assignment.storage_account, azurerm_role_assignment.azuredatabricks]
# }
# # Get the application IDs for APIs published by Microsoft
# data "azuread_application_published_app_ids" "well_known" {}
# # Get the object id of the Azure DataBricks service principal
# data "azuread_service_principal" "this" {
#   client_id = data.azuread_application_published_app_ids.well_known.result["AzureDataBricks"]
# }
#
# # Add the Azure DataBricks service principal to the key vault access policy
# resource "azurerm_role_assignment" "azuredatabricks" {
#   principal_id         = data.azuread_service_principal.this.object_id
#   scope                = azurerm_key_vault.this.id
#   role_definition_name = "Key Vault Crypto User"
# }
#
#
# # Add the current user to the key vault access policy
# resource "azurerm_role_assignment" "current_user" {
#   principal_id         = data.azurerm_client_config.this.object_id
#   scope                = azurerm_key_vault.this.id
#   role_definition_name = "Key Vault Crypto Officer"
# }
#
# # Define an Azure Databricks workspace resource
# resource "azurerm_databricks_workspace" "this" {
#   name                = "${var.prefix}-adb-workspace"
#   resource_group_name = azurerm_resource_group.this.name
#   location            = var.location
#   sku                 = "premium"
#
#   customer_managed_key_enabled      = true
#   infrastructure_encryption_enabled = true
#   # default_storage_firewall_enabled      = true
#   # access_connector_id = ???
#   public_network_access_enabled                       = false
#   network_security_group_rules_required               = "NoAzureDatabricksRules"
#   managed_services_cmk_key_vault_key_id               = azurerm_key_vault_key.cmkms.id
#   managed_disk_cmk_key_vault_key_id                   = azurerm_key_vault_key.managed_disk_cmk.id
#   managed_disk_cmk_rotation_to_latest_version_enabled = true
#   # dbfs_root_cmk_key_vault_key_id                      = azurerm_key_vault_key.dbfs_root.id
#
#   custom_parameters {
#     no_public_ip                                         = true
#     virtual_network_id                                   = azurerm_virtual_network.this.id
#     public_subnet_name                                   = azurerm_subnet.host.name
#     private_subnet_name                                  = azurerm_subnet.container.name
#     public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.host.id
#     private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.container.id
#   }
#
#   tags = {
#     Owner = "nathan.knox@databricks.com"
#   }
# }
#
# # add the disk encryption key to the key vault access policy
# resource "azurerm_role_assignment" "disk_encryption_set" {
#   principal_id         = module.databricks.databricks_workspace_managed_disk_identity.principal_id
#   scope                = azurerm_key_vault.this.id
#   role_definition_name = "Key Vault Crypto User"
# }
#
# # add the storage account encryption key to the key vault access policy
# resource "azurerm_role_assignment" "storage_account" {
#   principal_id         = module.databricks.databricks_workspace_storage_account_identity.principal_id
#   scope                = azurerm_key_vault.this.id
#   role_definition_name = "Key Vault Crypto User"
# }
#
# #---
# # data "azurerm_client_config" "current" {}
# #
# # data "azurerm_databricks_workspace_private_endpoint_connection" "example" {
# #   workspace_id        = azurerm_databricks_workspace.example.id
# #   private_endpoint_id = azurerm_private_endpoint.databricks.id
# # }
# #
# # resource "azurerm_resource_group" "example" {
# #   name     = "${var.prefix}-databricks-private-endpoint-ms-dbfscmk"
# #   location = "eastus2"
# # }
# #
# # resource "azurerm_virtual_network" "example" {
# #   name                = "${var.prefix}-vnet-databricks"
# #   address_space       = ["10.0.0.0/16"]
# #   location            = azurerm_resource_group.example.location
# #   resource_group_name = azurerm_resource_group.example.name
# # }
# #
# # resource "azurerm_subnet" "public" {
# #   name                 = "${var.prefix}-sn-public"
# #   resource_group_name  = azurerm_resource_group.example.name
# #   virtual_network_name = azurerm_virtual_network.example.name
# #   address_prefixes     = ["10.0.1.0/24"]
# #
# #   delegation {
# #     name = "databricks-del-pub-${var.prefix}"
# #
# #     service_delegation {
# #       actions = [
# #         "Microsoft.Network/virtualNetworks/subnets/join/action",
# #         "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
# #         "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
# #       ]
# #       name = "Microsoft.Databricks/workspaces"
# #     }
# #   }
# # }
# #
# # resource "azurerm_subnet" "private" {
# #   name                 = "${var.prefix}-sn-private"
# #   resource_group_name  = azurerm_resource_group.example.name
# #   virtual_network_name = azurerm_virtual_network.example.name
# #   address_prefixes     = ["10.0.2.0/24"]
# #
# #   delegation {
# #     name = "databricks-del-pri-${var.prefix}"
# #
# #     service_delegation {
# #       actions = [
# #         "Microsoft.Network/virtualNetworks/subnets/join/action",
# #         "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
# #         "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
# #       ]
# #       name = "Microsoft.Databricks/workspaces"
# #     }
# #   }
# # }
# #
# # resource "azurerm_subnet" "endpoint" {
# #   name                 = "${var.prefix}-sn-private-endpoint"
# #   resource_group_name  = azurerm_resource_group.example.name
# #   virtual_network_name = azurerm_virtual_network.example.name
# #   address_prefixes     = ["10.0.3.0/24"]
# #
# #   private_endpoint_network_policies_enabled = false
# # }
# #
# # resource "azurerm_subnet_network_security_group_association" "private" {
# #   subnet_id                 = azurerm_subnet.private.id
# #   network_security_group_id = azurerm_network_security_group.example.id
# # }
# #
# # resource "azurerm_subnet_network_security_group_association" "public" {
# #   subnet_id                 = azurerm_subnet.public.id
# #   network_security_group_id = azurerm_network_security_group.example.id
# # }
# #
# # resource "azurerm_network_security_group" "example" {
# #   name                = "${var.prefix}-nsg-databricks"
# #   location            = azurerm_resource_group.example.location
# #   resource_group_name = azurerm_resource_group.example.name
# # }
# #
# # resource "azurerm_databricks_workspace" "example" {
# #   name                        = "${var.prefix}-DBW"
# #   resource_group_name         = azurerm_resource_group.example.name
# #   location                    = azurerm_resource_group.example.location
# #   sku                         = "premium"
# #   managed_resource_group_name = "${var.prefix}-DBW-managed-private-endpoint-ms-dbfscmk"
# #
# #   customer_managed_key_enabled          = true
# #   managed_services_cmk_key_vault_key_id = azurerm_key_vault_key.example.id
# #   public_network_access_enabled         = false
# #   network_security_group_rules_required = "NoAzureDatabricksRules"
# #
# #   custom_parameters {
# #     no_public_ip        = true
# #     public_subnet_name  = azurerm_subnet.public.name
# #     private_subnet_name = azurerm_subnet.private.name
# #     virtual_network_id  = azurerm_virtual_network.example.id
# #
# #     public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.public.id
# #     private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.private.id
# #   }
# #
# #   tags = {
# #     Environment = "Production"
# #     Pricing     = "Premium"
# #   }
# # }
# #
# # resource "azurerm_databricks_workspace_root_dbfs_customer_managed_key" "example" {
# #   depends_on = [azurerm_key_vault_access_policy.databricks]
# #
# #   workspace_id     = azurerm_databricks_workspace.example.id
# #   key_vault_key_id = azurerm_key_vault_key.example.id
# # }
# #
# # resource "azurerm_private_endpoint" "databricks" {
# #   depends_on = [azurerm_databricks_workspace_root_dbfs_customer_managed_key.example]
# #
# #   name                = "${var.prefix}-pe-databricks"
# #   location            = azurerm_resource_group.example.location
# #   resource_group_name = azurerm_resource_group.example.name
# #   subnet_id           = azurerm_subnet.endpoint.id
# #
# #   private_service_connection {
# #     name                           = "${var.prefix}-psc"
# #     is_manual_connection           = false
# #     private_connection_resource_id = azurerm_databricks_workspace.example.id
# #     subresource_names              = ["databricks_ui_api"]
# #   }
# # }
# #
# # resource "azurerm_private_dns_zone" "example" {
# #   depends_on = [azurerm_private_endpoint.databricks]
# #
# #   name                = "privatelink.azuredatabricks.net"
# #   resource_group_name = azurerm_resource_group.example.name
# # }
# #
# # resource "azurerm_private_dns_cname_record" "example" {
# #   name                = azurerm_databricks_workspace.example.workspace_url
# #   zone_name           = azurerm_private_dns_zone.example.name
# #   resource_group_name = azurerm_resource_group.example.name
# #   ttl                 = 300
# #   record              = "eastus2-c2.azuredatabricks.net"
# # }
# #
# # resource "azurerm_key_vault" "example" {
# #   name                = "${var.prefix}-keyvault"
# #   location            = azurerm_resource_group.example.location
# #   resource_group_name = azurerm_resource_group.example.name
# #   tenant_id           = data.azurerm_client_config.current.tenant_id
# #   sku_name            = "premium"
# #
# #   soft_delete_retention_days = 7
# # }
# #
# # resource "azurerm_key_vault_key" "example" {
# #   depends_on = [azurerm_key_vault_access_policy.terraform]
# #
# #   name         = "${var.prefix}-certificate"
# #   key_vault_id = azurerm_key_vault.example.id
# #   key_type     = "RSA"
# #   key_size     = 2048
# #
# #   key_opts = [
# #     "decrypt",
# #     "encrypt",
# #     "sign",
# #     "unwrapKey",
# #     "verify",
# #     "wrapKey",
# #   ]
# # }
# #
# # resource "azurerm_key_vault_access_policy" "terraform" {
# #   key_vault_id = azurerm_key_vault.example.id
# #   tenant_id    = azurerm_key_vault.example.tenant_id
# #   object_id    = data.azurerm_client_config.current.object_id
# #
# #   key_permissions = [
# #     "Get",
# #     "List",
# #     "Create",
# #     "Decrypt",
# #     "Encrypt",
# #     "Sign",
# #     "UnwrapKey",
# #     "Verify",
# #     "WrapKey",
# #     "Delete",
# #     "Restore",
# #     "Recover",
# #     "Update",
# #     "Purge",
# #     "GetRotationPolicy",
# #     "SetRotationPolicy",
# #   ]
# # }
# #
# # resource "azurerm_key_vault_access_policy" "databricks" {
# #   depends_on = [azurerm_databricks_workspace.example]
# #
# #   key_vault_id = azurerm_key_vault.example.id
# #   tenant_id    = azurerm_databricks_workspace.example.storage_account_identity.0.tenant_id
# #   object_id    = azurerm_databricks_workspace.example.storage_account_identity.0.principal_id
# #
# #   key_permissions = [
# #     "Get",
# #     "UnwrapKey",
# #     "WrapKey",
# #   ]
# # }
# #
# # resource "azurerm_key_vault_access_policy" "managed" {
# #   key_vault_id = azurerm_key_vault.example.id
# #   tenant_id    = azurerm_key_vault.example.tenant_id
# #   object_id    = "00000000-0000-0000-0000-000000000000" # See the README.md file for instructions on how to lookup the correct value to enter here.
# #
# #   key_permissions = [
# #     "Get",
# #     "UnwrapKey",
# #     "WrapKey",
# #   ]
# # }
# #
# # output "databricks_workspace_private_endpoint_connection_workspace_id" {
# #   value = data.azurerm_databricks_workspace_private_endpoint_connection.example.workspace_id
# # }
# #
# # output "databricks_workspace_private_endpoint_connection_private_endpoint_id" {
# #   value = data.azurerm_databricks_workspace_private_endpoint_connection.example.private_endpoint_id
# # }
# #
# # output "databricks_workspace_private_endpoint_connection_name" {
# #   value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections.0.name
# # }
# #
# # output "databricks_workspace_private_endpoint_connection_workspace_private_endpoint_id" {
# #   value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections.0.workspace_private_endpoint_id
# # }
# #
# # output "databricks_workspace_private_endpoint_connection_status" {
# #   value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections.0.status
# # }
# #
# # output "databricks_workspace_private_endpoint_connection_description" {
# #   value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections.0.description
# # }
# #
# # output "databricks_workspace_private_endpoint_connection_action_required" {
# #   value = data.azurerm_databricks_workspace_private_endpoint_connection.example.connections.0.action_required
# # }
