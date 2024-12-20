provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "databricks" {
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
  auth_type  = "azure-cli"
}

provider "random" {

}
