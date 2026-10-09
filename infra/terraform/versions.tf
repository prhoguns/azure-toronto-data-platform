terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.14"
    }
  }
}

provider "azurerm" {
  features {}
  # Talk to the data plane (containers) with Entra ID, so storage account keys can be disabled.
  storage_use_azuread = true
}

# Uses the Azure CLI login by default, like azurerm. Only called when enable_fabric is true.
provider "fabric" {}
