variable "AZDO_ORG_ID" {
  description = "Azure DevOps Organization ID, passed as a TF_VAR"
  type        = string
  nullable    = false
}

variable "AZDO_ORG_NAME" {
  description = "Azure DevOps Organization Name, passed as a TF_VAR"
  type        = string
  nullable    = false
}

variable "AZDO_PAT_TOKEN" {
  description = "Azure DevOps Personal Access Token, passed as a TF_VAR"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "AZDO_PROJECT_NAME" {
  description = "Azure DevOps Project Name, passed as a TF_VAR"
  type        = string
  nullable    = false
}
