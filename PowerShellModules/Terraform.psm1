# Run 'terraform validate'
function Invoke-TerraformValidate {
    param (
        [string]$CodePath
    )

    if (-not (Test-Path $CodePath)) {
        _LogMessage -Level "ERROR" -Message "Terraform code not found: $TemplatePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
        throw "Terraform code not found: $CodePath"
    }

    _LogMessage -Level "INFO" -Message "Validating Terraform: $CodePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
    Set-Location $CodePath
    & terraform validate
}

# Run 'terraform validate'
function Invoke-TerraformFmtCheck {
    param (
        [string]$CodePath
    )

    if (-not (Test-Path $CodePath)) {
        _LogMessage -Level "ERROR" -Message "Terraform code not found: $TemplatePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
        throw "Terraform code not found: $CodePath"
    }

    _LogMessage -Level "INFO" -Message "Validating Terraform: $CodePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
    Set-Location $CodePath
    & terraform fmt -check
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform code formatting check failed, format your code before running!"
    }
}

function Invoke-TerraformInit {
    param (
        [string]$CodePath,
        [bool]$RunUpgrade = $true
    )

    if (-not (Test-Path $CodePath)) {
        _LogMessage -Level "ERROR" -Message "Terraform code not found: $TemplatePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
        throw "Terraform code not found: $CodePath"
    }

    _LogMessage -Level "INFO" -Message "Initializing Terraform: $CodePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
    Set-Location $CodePath
    if ($RunUpgrade) {
        & terraform init -upgrade
    }
    else {
        & terraform init
    }
}

function Invoke-TerraformPlan {
    param (
        [string]$CodePath,
        [string]$PlanPath,
        [bool]$OutputPlan = $false,
        [bool]$ConvertPlanToJson = $false


    )

    if (-not (Test-Path $CodePath)) {
        _LogMessage -Level "ERROR" -Message "Terraform code not found: $TemplatePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
        throw "Terraform code not found: $CodePath"
    }

    _LogMessage -Level "INFO" -Message "Planning Terraform: $CodePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
    Set-Location $CodePath
    if ($OutputPlan) {
        & terraform plan -out=$PlanPath
        if ($OutputPlan -and $ConvertPlanToJson)
        {
            terraform show -json $PlanPath > $PlanPath.json
        }
    }
    else {
        & terraform plan
    }
}

function Invoke-TerraformApply {
    param (
        [string]$CodePath,
        [bool]$OutputPlan = $false,
        [string]$PlanPath
    )

    if (-not (Test-Path $CodePath)) {
        _LogMessage -Level "ERROR" -Message "Terraform code not found: $TemplatePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
        throw "Terraform code not found: $CodePath"
    }

    _LogMessage -Level "INFO" -Message "Applying Terraform: $CodePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
    Set-Location $CodePath
    if ($OutputPlan)
    {
        & terraform apply $PlanPath -auto-approve
    }
    else
    {
        & terraform apply -auto-approve
    }
}

function Invoke-TerraformPlanDestroy {
    param (
        [string]$CodePath,
        [string]$PlanPath
    )

    if (-not (Test-Path $CodePath)) {
        _LogMessage -Level "ERROR" -Message "Terraform code not found: $TemplatePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
        throw "Terraform code not found: $CodePath"
    }

    _LogMessage -Level "INFO" -Message "Planning Terraform destroy: $CodePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
    Set-Location $CodePath
    if ($OutputPlan)
    {
        & terraform plan -destroy -out=$PlanPath
    }
    else
    {
        & terraform plan -destroy
    }

}

function Invoke-TerraformDestroy {
    param (
        [string]$CodePath,
        [bool]$OutputPlan = $false,
        [string]$PlanPath
    )

    if (-not (Test-Path $CodePath)) {
        _LogMessage -Level "ERROR" -Message "Terraform code not found: $TemplatePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
        throw "Terraform code not found: $CodePath"
    }

    _LogMessage -Level "INFO" -Message "Destroying Terraform: $CodePath" -InvocationName "$($MyInvocation.MyCommand.Name)"
    Set-Location $CodePath
    if ($OutputPlan)
    {
        & terraform destroy $PlanPath -auto-approve
    }
    else
    {
        & terraform destroy -auto-approve
    }
}

Export-ModuleMember -Function Invoke-TerraformValidate, Invoke-TerraformFmtCheck, Invoke-TerraformInit, Invoke-TerraformPlan, Invoke-TerraformApply, Invoke-TerraformPlanDestroy, Invoke-TerraformDestroy
