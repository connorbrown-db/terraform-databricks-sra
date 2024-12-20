# Define an Azure Databricks workspace resource
resource "azurerm_databricks_workspace" "this" {
  name                = "${var.prefix}-adb-workspace"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "premium"

  customer_managed_key_enabled      = true
  infrastructure_encryption_enabled = true
  # default_storage_firewall_enabled      = true
  # access_connector_id = ???
  managed_services_cmk_key_vault_key_id = var.managed_services_key_id
  managed_disk_cmk_key_vault_key_id     = var.managed_disk_key_id
  public_network_access_enabled         = false
  network_security_group_rules_required = "NoAzureDatabricksRules"

  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = azurerm_virtual_network.this.id
    public_subnet_name                                   = azurerm_subnet.host.name
    private_subnet_name                                  = azurerm_subnet.container.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.host.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.container.id
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_key_vault_access_policy" "databricks" {
  depends_on = [azurerm_databricks_workspace.this]

  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_databricks_workspace.example.storage_account_identity[0].tenant_id
  object_id    = azurerm_databricks_workspace.example.storage_account_identity[0].principal_id

  key_permissions = [
    "Get",
    "UnwrapKey",
    "WrapKey",
  ]
}

resource "azurerm_databricks_workspace_root_dbfs_customer_managed_key" "this" {
  workspace_id     = azurerm_databricks_workspace.this.workspace_id
  key_vault_key_id = var.managed_disk_key_id
}

# Define a Databricks metastore assignment
resource "databricks_metastore_assignment" "this" {
  # may need to use an explicit workspace-authenticated provider here
  # provider = databricks.workspace
  workspace_id = azurerm_databricks_workspace.this.workspace_id
  metastore_id = var.metastore_id
}
