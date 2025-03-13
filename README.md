```hcl
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

  vnet_name          = local.vnet_name
  vnet_location      = module.rg.rg_location
  vnet_address_space = [module.subnet_calculator.base_cidr]

  subnets = {
    for i, name in module.subnet_calculator.subnet_names :
    name => {
      address_prefixes  = toset([module.subnet_calculator.subnet_ranges[i]])
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
```
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azuredevops"></a> [azuredevops](#provider\_azuredevops) | 1.8.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.23.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_key_vault"></a> [key\_vault](#module\_key\_vault) | libre-devops/keyvault/azurerm | n/a |
| <a name="module_network"></a> [network](#module\_network) | libre-devops/network/azurerm | n/a |
| <a name="module_nsg"></a> [nsg](#module\_nsg) | libre-devops/nsg/azurerm | n/a |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | n/a |
| <a name="module_role_assignments"></a> [role\_assignments](#module\_role\_assignments) | github.com/libre-devops/terraform-azurerm-role-assignment | n/a |
| <a name="module_sa"></a> [sa](#module\_sa) | registry.terraform.io/libre-devops/storage-account/azurerm | n/a |
| <a name="module_service_principal"></a> [service\_principal](#module\_service\_principal) | github.com/libre-devops/terraform-azuread-service-principal | n/a |
| <a name="module_shared_vars"></a> [shared\_vars](#module\_shared\_vars) | libre-devops/shared-vars/azurerm | n/a |
| <a name="module_subnet_calculator"></a> [subnet\_calculator](#module\_subnet\_calculator) | libre-devops/subnet-calculator/null | n/a |

## Resources

| Name | Type |
|------|------|
| [azuredevops_serviceendpoint_azurerm.azure_devops_service_endpoint_azurerm_managed_identity](https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs/resources/serviceendpoint_azurerm) | resource |
| [azuredevops_serviceendpoint_azurerm.azure_devops_service_endpoint_azurerm_spn](https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs/resources/serviceendpoint_azurerm) | resource |
| [azurerm_federated_identity_credential.federated_credential](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_storage_account_network_rules.rules](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account_network_rules) | resource |
| [azurerm_storage_container.terraform_state_container](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_subnet_network_security_group_association.nsg_assoc](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_user_assigned_identity.uid](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azuredevops_project.current](https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs/data-sources/project) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_AZDO_ORG_ID"></a> [AZDO\_ORG\_ID](#input\_AZDO\_ORG\_ID) | Azure DevOps Organization ID, passed as a TF\_VAR | `string` | n/a | yes |
| <a name="input_AZDO_ORG_NAME"></a> [AZDO\_ORG\_NAME](#input\_AZDO\_ORG\_NAME) | Azure DevOps Organization Name, passed as a TF\_VAR | `string` | n/a | yes |
| <a name="input_AZDO_PAT_TOKEN"></a> [AZDO\_PAT\_TOKEN](#input\_AZDO\_PAT\_TOKEN) | Azure DevOps Personal Access Token, passed as a TF\_VAR | `string` | n/a | yes |
| <a name="input_AZDO_PROJECT_NAME"></a> [AZDO\_PROJECT\_NAME](#input\_AZDO\_PROJECT\_NAME) | Azure DevOps Project Name, passed as a TF\_VAR | `string` | n/a | yes |
| <a name="input_static_tags"></a> [static\_tags](#input\_static\_tags) | The tags variable | `map(string)` | <pre>{<br/>  "Contact": "libredevops.org",<br/>  "CostCentre": "671888",<br/>  "ManagedBy": "Terraform"<br/>}</pre> | no |

## Outputs

No outputs.
