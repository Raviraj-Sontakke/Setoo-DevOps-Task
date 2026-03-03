terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  backend "azurerm" {
    resource_group_name  = "raviraj-rg-shared"
    storage_account_name = "ravirajstoragestate"
    container_name       = "tfstate"
    key                  = "stage/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}
