```hcl
locals {
  loc                  = "uks"
  name                 = "libd"
  long_name            = "libre-devops"
  env                  = "dev"
  management_rg_name   = "rg-${local.name}-${local.loc}-${local.env}-mgmt"
  location             = "uksouth"
  spn_name             = "spn-${local.name}-${local.loc}-${local.env}-mgmt-01"
  spn_description      = "Service Principal for ${local.long_name} ${local.loc} ${local.env} Management"
  fed_cred_name        = "fedcred-${local.spn_name}"
  fed_cred_description = "Federated Credential for Azure DevOps ${data.azuredevops_project.current.name} ${local.spn_name}"
  fed_cred_audiences   = ["api://AzureADTokenExchange"]
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
| <a name="module_service_principal"></a> [service\_principal](#module\_service\_principal) | github.com/libre-devops/terraform-azuread-service-principal | n/a |

## Resources

| Name | Type |
|------|------|
| [azuredevops_project.current](https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs/data-sources/project) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_AZDO_ORG_ID"></a> [AZDO\_ORG\_ID](#input\_AZDO\_ORG\_ID) | Azure DevOps Organization ID, passed as a TF\_VAR | `string` | n/a | yes |
| <a name="input_AZDO_ORG_NAME"></a> [AZDO\_ORG\_NAME](#input\_AZDO\_ORG\_NAME) | Azure DevOps Organization Name, passed as a TF\_VAR | `string` | n/a | yes |
| <a name="input_static_tags"></a> [static\_tags](#input\_static\_tags) | The tags variable | `map(string)` | <pre>{<br/>  "Contact": "info@cyber.scot",<br/>  "CostCentre": "671888",<br/>  "ManagedBy": "Terraform"<br/>}</pre> | no |

## Outputs

No outputs.
