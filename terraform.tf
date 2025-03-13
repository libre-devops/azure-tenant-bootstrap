terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    azuread = {
      source = "hashicorp/azuread"
    }
    random = {
      source = "hashicorp/random"
    }
    azapi = {
      source = "Azure/azapi"
    }
    azuredevops = {
      source = "microsoft/azuredevops"
    }
  }
  backend "local" {} # Use local backend for storing since this is a bootstrap
}
