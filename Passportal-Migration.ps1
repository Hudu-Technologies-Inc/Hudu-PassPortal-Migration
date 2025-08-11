$workdir = $PSScriptRoot
### CONFIGURATION
##
#
$passportalData = @{
    docTypes = @("asset","active_directory","application","backup","email","folders","file_sharing","contact","location","internet","lan","printing","remote_access","vendor","virtualization","voice","wireless","licencing","custom","ssl");
    APIkey = $($passportalData_APIkey ?? "$(read-host "please enter your Passportal API key")"); APIkeyId = $($passportalData_APIkeyId ?? "$(read-host "please enter your Passportal API key ID")")
    Token = $null; Headers = @{}; BaseURL = $null; clients=@(); Documents =@(); csvData = @{}
}

$sensitiveVars = @("PassportalApiKey","PassportalApiKeyId","HuduApiKey","PassPortalHeaders","passportalData")
$HuduBaseURL = $HuduBaseURL ?? "$(read-host "please enter your Hudu Base url")"
$HuduAPIKey = $HuduAPIKey ?? "$(read-host "please enter your Hudu API Key")"
$SelectedLocation = $SelectedLocation ?? $(Select-ObjectFromList -allowNull $false -objects $PPBaseURIs -message "Choose your Location for Passportal API access")
$passportalData.BaseURL = "https://$($SelectedLocation.APIBase).passportalmsp.com/"

$MatchedCompanies = @()
$CreatedCompanies = @()
$CreatedLayouts = @()
$CreatedAssets = @()
$CreatedPasswords = @()
$CreatedFolders = @()
$foundDocs = 0

### SETUP
##
#
foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
Set-IncrementedState -newState "Set up and init"
Set-PrintAndLog -message "using $($selectedLocation.name) / $BaseUri for PassPortal" -Color DarkBlue
Set-Content -Path $logFile -Value "Starting Passportal Migration" 
Set-PrintAndLog -message "Checked Powershell Version... $(Get-PSVersionCompatible)" -Color DarkBlue
Set-PrintAndLog -message "Imported Hudu Module... $(Get-HuduModule)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Credentials... $(Set-HuduInstance)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Version... $(Get-HuduVersionCompatible)" -Color DarkBlue
Set-IncrementedState -newState "Check Source data and get Source Data Options"

### LOAD SOURCEDATA
##
#
Set-IncrementedState -newState "Authenticate to Passportal"
$authResult = Get-PassportalAuthToken    
$passportalData.Token = $authResult.token
$passportalData.Headers = $authResult.headers

Set-IncrementedState -newState "Load Source Data"
. .\jobs\load-sourcedata.ps1

### LOAD DESTDATA and determine import strategy
##
#
Set-IncrementedState -newState "Obtain data from Hudu Instance- $(Get-HuduBaseURL)"
. .\jobs\load-destinationdata.ps1

### Transfer assets, companies, and layouts into hudu
##
#
Set-IncrementedState -newState "Transfer assets, companies, and layouts into hudu"
. .\jobs\transfer-companies-assets-layouts.ps1

Set-IncrementedState -newState "Set Layouts as active"
foreach ($layout in Get-HuduAssetLayouts) {Set-PrintAndLog -message "setting $($(Set-HuduAssetLayout -id $layout.id -Active $true).asset_layout.name) as active" -Color DarkMagenta }


### Transfer passwords if CSVs present
##
#
Set-IncrementedState -newState "Import and match passwords from CSV data"
. .\jobs\transfer-passwords.ps1

Set-IncrementedState -newState "Complete"

Set-IncrementedState -newState "Calculate and Relay Results"
. .\jobs\relay-results.ps1

# Set-IncrementedState -newState "Import and match websites from SSL data"
Set-IncrementedState -newState "Wrap-Up, and Unsetting $($sensitiveVars.count) sensitive vars"
foreach ($var in $sensitiveVars) {
    Set-PrintAndLog -message  "Unset Sensitive Var $var"
    Unset-Vars -varname $var
}

