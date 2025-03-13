locals {
  loc                          = "uks"
  name                         = "libd"
  long_name                    = "libre-devops"
  env                          = "dev"
  management_rg_name           = "rg-${local.name}-${local.loc}-${local.env}-mgmt"
  location                     = "uksouth"
  spn_name                     = "spn-${local.name}-${local.loc}-${local.env}-mgmt-01"
  spn_description              = "Service Principal for ${local.long_name} ${local.loc} ${local.env} Management"
  fed_cred_name                = "fedcred-${local.spn_name}"
  fed_cred_description         = "Federated Credential for Azure DevOps ${data.azuredevops_project.current.name} ${local.spn_name}"
  fed_cred_audiences           = ["api://AzureADTokenExchange"]
  uid_name                     = "uid-${local.name}-${local.loc}-${local.env}-mgmt-01"
  uid_fed_cred_name            = "fedcred-${local.uid_name}"
  vnet_name                    = "vnet-${local.name}-${local.loc}-${local.env}-mgmt-01"
  nsg_name                     = "nsg-${local.name}-${local.loc}-${local.env}-mgmt-01"
  vnet_address_space           = ["10.0.0.0/16"]
  default_subnet_name          = "defaultSubnet"
  storage_subnet_name          = "storageSubnet"
  key_vault_subnet_name        = "keyVaultSubnet"
  azure_devops_subnet_name     = "devopsAgentSubnet"
  storage_account_name         = "satf${local.name}${local.loc}${local.env}01"
  tf_state_blob_container_name = "tfstate"
  key_vault_name               = "kv-${local.name}-${local.loc}-${local.env}-01"
}

module "service_principal" {
  source = "github.com/libre-devops/terraform-azuread-service-principal"

  spns = [
    {
      spn_name                            = local.spn_name
      description                         = local.spn_description
      create_corresponding_enterprise_app = true
      create_federated_credential         = true
      federated_credential_display_name   = local.fed_cred_name
      federated_credential_description    = local.fed_cred_description
      federated_credential_audiences      = local.fed_cred_audiences
      federated_credential_issuer         = format("https://vstoken.dev.azure.com/%s", var.AZDO_ORG_ID)
      federated_credential_subject        = format("sc://%s/%s/%s", var.AZDO_ORG_NAME, data.azuredevops_project.current.name, local.spn_name)
    }
  ]
}

module "rg" {
  source = "libre-devops/rg/azurerm"

  rg_name  = local.management_rg_name
  location = local.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "uid" {
  resource_group_name = module.rg.rg_name
  location            = module.rg.rg_location
  tags                = module.rg.rg_tags

  name = local.uid_name
}

module "shared_vars" {
  source = "libre-devops/shared-vars/azurerm"
}

module "subnet_calculator" {
  source = "libre-devops/subnet-calculator/null"

  base_cidr = local.vnet_address_space[0]
  subnets = {
    (local.default_subnet_name) = {
      mask_size = 27
      netnum    = 0
    },
    (local.storage_subnet_name) = {
      mask_size = 27
      netnum    = 1
    },
    (local.key_vault_subnet_name) = {
      mask_size = 27
      netnum    = 2
    },
    (local.azure_devops_subnet_name) = {
      mask_size = 26
      netnum    = 5
    },
  }
}

module "network" {
  source = "libre-devops/network/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vnet_name     = local.vnet_name
  vnet_location = module.rg.rg_location
  vnet_address_space = [module.subnet_calculator.base_cidr]

  subnets = {
    for i, name in module.subnet_calculator.subnet_names :
    name => {
      address_prefixes = toset([module.subnet_calculator.subnet_ranges[i]])
      service_endpoints = name == local.storage_subnet_name ? ["Microsoft.Storage"] : name == local.key_vault_subnet_name ? ["Microsoft.KeyVault"] : []

      # Only assign delegation to DevOps Agent Subnet
      delegation = name == local.azure_devops_subnet_name ? [
        {
          type = "Microsoft.DevOpsInfrastructure/pools"
        },
      ] : []
    }
  }
}

module "nsg" {
  source = "libre-devops/nsg/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  nsg_name              = local.nsg_name
  associate_with_subnet = false
  custom_nsg_rules = {
    "AllowVnetInbound" = {
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
    for_each = module.network.subnets_ids

    subnet_id                 = each.value
    network_security_group_id = module.nsg.nsg_id
}


module "role_assignments" {
  source = "github.com/libre-devops/terraform-azurerm-role-assignment"

  role_assignments = [
    {
      principal_ids = [azurerm_user_assigned_identity.uid.principal_id]
      role_names    = ["Owner", "Key Vault Administrator", "Storage Blob Data Owner"]
      scope         = data.azurerm_subscription.current.id
    },
    {
      principal_ids = [module.service_principal.enterprise_app_object_id[0]]
      role_names    = ["Owner", "Key Vault Administrator", "Storage Blob Data Owner"]
      scope         = data.azurerm_subscription.current.id
    },
  ]
}

module "sa" {
  source = "registry.terraform.io/libre-devops/storage-account/azurerm"
  storage_accounts = [
    {
      rg_name  = module.rg.rg_name
      location = module.rg.rg_location
      tags     = module.rg.rg_tags

      name = local.storage_account_name


      identity_type = "UserAssigned"
      identity_ids  = [azurerm_user_assigned_identity.uid.id]


      public_network_access_enabled                   = true
      shared_access_keys_enabled                      = false
      create_diagnostic_settings                      = false
      diagnostic_settings_enable_all_logs_and_metrics = false
      diagnostic_settings                             = {}
    },
  ]
}

resource "azurerm_storage_container" "terraform_state_container" {
  storage_account_id = module.sa.storage_account_ids[local.storage_account_name]

  name                  = local.tf_state_blob_container_name
  container_access_type = "private"
}

resource "azurerm_storage_account_network_rules" "rules" {
  default_action     = "Allow"
  storage_account_id = module.sa.storage_account_ids[local.storage_account_name]
  ip_rules           = []
  virtual_network_subnet_ids = [
    module.network.subnets_ids[local.storage_subnet_name],
  ]
}


module "key_vault" {
  source = "libre-devops/keyvault/azurerm"

  key_vaults = [
    {
      rg_name  = module.rg.rg_name
      location = module.rg.rg_location
      tags     = module.rg.rg_tags

      name = local.key_vault_name

      create_diagnostic_settings                      = false
      diagnostic_settings_enable_all_logs_and_metrics = false
      diagnostic_settings                             = {}

      enabled_for_deployment          = true
      enabled_for_disk_encryption     = true
      enabled_for_template_deployment = true
      enable_rbac_authorization       = true
      purge_protection_enabled        = false
      public_network_access_enabled   = true
      network_acls = {
        default_action             = "Allow"
        bypass                     = "AzureServices"
        ip_rules                   = []
        virtual_network_subnet_ids = [module.network.subnets_ids[local.key_vault_subnet_name]]
      }
    },
  ]
}


resource "azuredevops_serviceendpoint_azurerm" "azure_devops_service_endpoint_azurerm_spn" {
  depends_on                             = [module.role_assignments]
  project_id                             = data.azuredevops_project.current.id
  service_endpoint_name                  = local.spn_name
  description                            = local.spn_name
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"

  credentials {
    serviceprincipalid = module.service_principal.client_id["0"]
  }

  azurerm_spn_tenantid      = data.azurerm_client_config.current.tenant_id
  azurerm_subscription_id   = data.azurerm_subscription.current.subscription_id
  azurerm_subscription_name = data.azurerm_subscription.current.display_name
}

resource "azuredevops_serviceendpoint_azurerm" "azure_devops_service_endpoint_azurerm_managed_identity" {
  depends_on                             = [module.role_assignments]
  project_id                             = data.azuredevops_project.current.id
  service_endpoint_name                  = local.uid_name
  description                            = local.spn_description
  service_endpoint_authentication_scheme = "WorkloadIdentityFederation"

  credentials {
    serviceprincipalid = azurerm_user_assigned_identity.uid.client_id
  }

  azurerm_spn_tenantid      = data.azurerm_client_config.current.tenant_id
  azurerm_subscription_id   = data.azurerm_subscription.current.subscription_id
  azurerm_subscription_name = data.azurerm_subscription.current.display_name
}

resource "azurerm_federated_identity_credential" "federated_credential" {
  name                = local.uid_fed_cred_name
  resource_group_name = azurerm_user_assigned_identity.uid.resource_group_name
  parent_id           = azurerm_user_assigned_identity.uid.id
  audience            = local.fed_cred_audiences
  issuer              = azuredevops_serviceendpoint_azurerm.azure_devops_service_endpoint_azurerm_managed_identity.workload_identity_federation_issuer
  subject             = azuredevops_serviceendpoint_azurerm.azure_devops_service_endpoint_azurerm_managed_identity.workload_identity_federation_subject
}