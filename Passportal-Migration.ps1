$workdir = $PSScriptRoot
# --- CONFIGURATION ---
$passportalData = @{
    Requested = @("folders", "passwords", "clients", "companies"); Fetched = @{}
    APIkey = $($passportalData_APIkey ?? "$(read-host "please enter your Passportal API key")"); APIkeyId = $($passportalData_APIkeyId ?? "$(read-host "please enter your Passportal API key")")
    Token = $null; Headers = @{}; BaseURL = $null; clients=@()
}

$sensitiveVars = @("PassportalApiKey","PassportalApiKeyId","HuduApiKey","PassPortalHeaders","passportalData")
$HuduBaseURL = $HuduBaseURL ?? "$(read-host "please enter your Hudu Base url")"
$HuduAPIKey = $HuduAPIKey ?? "$(read-host "please enter your Hudu API Key")"
$SelectedLocation = $SelectedLocation ?? $(Select-ObjectFromList -allowNull $false -objects $PPBaseURIs -message "Choose your Location for Passportal API access")
Write-Host "using $($selectedLocation.name) / $BaseUri for PassPortal"
$passportalData.BaseURL = "https://$($SelectedLocation.APIBase).passportalmsp.com/"

# Set-Up
foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}

$authResult = Get-PassportalAuthToken    
$passportalData.Token = $authResult.token
$passportalData.Headers = $authResult.headers

Set-Content -Path $logFile -Value "Starting Passportal Migration" 
Set-PrintAndLog -message "Checked Powershell Version... $(Get-PSVersionCompatible)" -Color DarkBlue
Set-PrintAndLog -message "Imported Hudu Module... $(Get-HuduModule)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Credentials... $(Set-HuduInstance)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Version... $(Get-HuduVersionCompatible)" -Color DarkBlue
Set-IncrementedState -newState "Check Source data and get Source Data Options"

$passportalData.Clients = $(Invoke-RestMethod -Headers $passportalData.Headers -Uri "$($passportalData.BaseURL)api/v2/documents/clients?resultsPerPage=1000" -Method Get -Verbose).results
foreach ($client in $passportalData.Clients) {Write-Host "found $($client.id)- $($client.name)"}

if ($(Select-ObjectFromList -objects @("all-clients","select-clients") -message "Would you like transfer data from all clients, or a slect list of clients") -eq "all-clients"){
    $RunSummary.JobInfo.MigrationSource.AddRange($passportalData.Clients)
} else {
    foreach ($client in $passportalData.Clients) {
        if ($(Select-ObjectFromList -objects @("yes","no") -message "Would you like to include data from client $($client.ID): $($client.Name) in this transfer to Hudu?") -eq "yes"){
            $RunSummary.JobInfo.MigrationSource.add($client)
        } else {
            Write-Host "Opted to not transfer data from client $($client.ID): $($client.Name)"
        }
    }
}
if ($RunSummary.JobInfo.MigrationSource.Count -lt 1){
    Write-Host "No clients selected for Migration Source. Exiting."
    exit
}

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