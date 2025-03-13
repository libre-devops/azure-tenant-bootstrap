provider "azuredevops" {
  org_service_url       = "https://dev.azure.com/${var.AZDO_ORG_NAME}" # Use PAT Token for auth for bootstrap
  personal_access_token = var.AZDO_PAT_TOKEN
}

data "azuredevops_project" "current" {
  name = var.AZDO_PROJECT_NAME
}