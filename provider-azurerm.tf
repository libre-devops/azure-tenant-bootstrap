provider "azurerm" {

  storage_use_azuread = true
  use_cli             = true
  # subscription_id      = var.subscription_id - source via ARM_SUBSCRIPTION_ID

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}