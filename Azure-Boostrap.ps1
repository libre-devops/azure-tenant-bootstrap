param (
    [bool]$ManualRun = $true, # By default, this script should run as a pipeline, this flag exists for when it is not
    [string]$TerraformCodePath = "$(Get-Location)"
)

# Get timestamp in "HH:mm:ss" format
$timestamp = Get-Date -Format "HH:mm:ss"

## Setup script modules etc

# Get script directory
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

# Import all required modules
$modules = @("Logger", "Utils", "AzureLogin", "Keyvault", "Nsg", "Terraform")
foreach ($module in $modules) {
    $modulePath = "$scriptDir\PowerShellModules\$module.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction Stop
    } else {
        Write-Host "ERROR: $timestamp - [$($MyInvocation.MyCommand.Name)] Module not found: $modulePath" -ForegroundColor Red
        exit 1
    }
}

# Log that modules were loaded
_LogMessage -Level "INFO" -Message "$timestamp - [$( $MyInvocation.MyCommand.Name )] Modules loaded successfully" -InvocationName "$($MyInvocation.MyCommand.Name)"

# Test pre-requisites are done
Get-InstalledPrograms -Programs @("terraform", "az")

# Only run 0login and environment checks if ManualRun is true
if ($ManualRun) {
    # Check if already logged in to Az PowerShell (handled by Test-AzCliConnection)
    _LogMessage -Level "INFO" -Message "Checking Azure-Cli authentication..." -InvocationName "$($MyInvocation.MyCommand.Name)"
    Test-AzureCliConnection
}

# Check environment variables
Test-EnvironmentVariablesExist -EnvVars @(
    "TF_VAR_AZDO_PROJECT_NAME",
    "TF_VAR_AZDO_PAT_TOKEN",
    "TF_VAR_AZDO_ORG_ID",
    "TF_VAR_AZDO_PROJECT_NAME"
    "ARM_SUBSCRIPTION_ID"
)
Test-PathExists -Paths @($TerraformCodePath)

try
{
    Invoke-TerraformValidate -CodePath $TerraformCodePath
    Invoke-TerraformFmtCheck -CodePath $TerraformCodePath
    Invoke-TerraformInit -CodePath $TerraformCodePath
    Invoke-TerraformPlan -CodePath $TerraformCodePath
    Invoke-TerraformApply -CodePath $TerraformCodePath
}
catch
{
    _LogMessage -Level "ERROR" -Message "An error occurred: $_" -InvocationName "$($MyInvocation.MyCommand.Name)"
    throw
}


