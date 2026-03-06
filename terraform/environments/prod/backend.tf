terraform {
  backend "azurerm" {
    storage_account_name = "ravirajtfstate"
    container_name       = "tfstate"
    prefix               = "setoo-tfstate-prod"
  }
}