$workdir = $PSScriptRoot
# Set-Up
$sensitiveVars = @("PassportalApiKey","PassportalSecretAccessKey","HuduApiKey","PassPortalHeaders","passportalData")
foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
$passportalData = Set-PassportalData

$HuduBaseURL = $HuduBaseURL ?? "$(read-host "please enter your Hudu Base url")"
$HuduAPIKey = $HuduAPIKey ?? "$(read-host "please enter your Hudu API Key")"



 
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
}

Write-Host "Unsetting vars before next run."
# foreach ($var in $sensitiveVars) {
#     Unset-Vars -varname $var
# }