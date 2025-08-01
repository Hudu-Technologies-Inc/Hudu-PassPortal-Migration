$workdir = $PSScriptRoot
# --- CONFIGURATION ---
$passportalData = @{
    Requested = @("folders", "passwords", "clients", "companies")
    Fetched = @{}
    APIkey = $($passportalData.APIkey ?? "$(read-host "please enter your Passportal API key")")
    APIkeyId = $($passportalData.APIkeyId ?? "$(read-host "please enter your Passportal API key")")
}



$sensitiveVars = @("PassportalApiKey","PassportalApiKeyId","HuduApiKey","PassPortalHeaders")
$HuduBaseURL = $HuduBaseURL ?? "$(read-host "please enter your Hudu Base url")"
$HuduAPIKey = $HuduAPIKey ?? "$(read-host "please enter your Hudu API Key")"
$BaseUri = "https://$($SelectedLocation.APIBase).passportalmsp.com/v4"
# $BaseUri = "https://api.passportalmsp.com/v4"

# Set-Up
foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
$passportalData.requestHeaders = @{"x-api-key"    = $passportalData.APIkey
                       "x-api-key-id" = $passportalData.APIkeyId
                       "Content-Type" = "application/json"}
$SelectedLocation = $SelectedLocation ?? $(Select-ObjectFromList -allowNull $false -objects $PPBaseURIs -message "Choose your Location for Passportal API access")
Write-Host "using $($selectedLocation.name) / $BaseUri for PassPortal"
Set-Content -Path $logFile -Value "Starting Passportal Migration" 
Set-PrintAndLog -message "Checked Powershell Version... $(Get-PSVersionCompatible)" -Color DarkBlue
Set-PrintAndLog -message "Imported Hudu Module... $(Get-HuduModule)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Credentials... $(Set-HuduInstance)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Version... $(Get-HuduVersionCompatible)" -Color DarkBlue
Set-IncrementedState -newState "Check Source data and get Source Data Options"


# --- Example usage ---
foreach ($objType in $passportalData.Requested) {
    write-host "Fetching $objType from Passportal"
    $PassportalData.Fetched[$objType] = Get-PassportalObjects -ObjectType $objType
    Write-Host "Got $($PassportalData.Fetched[$objType].Count) $objType"
    foreach ($obj in $PassportalData.Fetched[$objType]) {
        write-host "$($($($obj ?? @{}) | ConvertTo-Json -depth 88).ToString())"
    }
}



Write-Host "Unsetting vars before next run."
# foreach ($var in $sensitiveVars) {
#     Unset-Vars -varname $var
# }