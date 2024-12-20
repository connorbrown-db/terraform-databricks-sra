terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.104.0"
    }

    databricks = {
      source  = "databricks/databricks"
      version = ">=1.29.0"
    }
  }
  required_version = ">=1.2"
}
