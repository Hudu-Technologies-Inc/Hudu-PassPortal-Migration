$workdir = $PSScriptRoot
# --- CONFIGURATION ---
$passportalData = @{
    docTypes = @("asset","active_directory","application","backup","email","file_sharing","contact","location","internet","lan","printing","remote_access","vendor","virtualization","voice","wireless","licencing","custom","ssl");
    APIkey = $($passportalData_APIkey ?? "$(read-host "please enter your Passportal API key")"); APIkeyId = $($passportalData_APIkeyId ?? "$(read-host "please enter your Passportal API key")")
    Token = $null; Headers = @{}; BaseURL = $null; clients=@(); documents =@{}; csvData = @{}
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
write-host $passportalData.Token
Set-Content -Path $logFile -Value "Starting Passportal Migration" 
Set-PrintAndLog -message "Checked Powershell Version... $(Get-PSVersionCompatible)" -Color DarkBlue
Set-PrintAndLog -message "Imported Hudu Module... $(Get-HuduModule)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Credentials... $(Set-HuduInstance)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Version... $(Get-HuduVersionCompatible)" -Color DarkBlue
Set-IncrementedState -newState "Check Source data and get Source Data Options"

$passportalData.Clients = $(Invoke-RestMethod -Headers $passportalData.Headers -Uri "$($passportalData.BaseURL)api/v2/documents/clients?resultsPerPage=1000" -Method Get -Verbose).results
foreach ($client in $passportalData.Clients) {Write-Host "found $($client.id)- $($client.name)"}
Write-Host "Checking .\exported-csvs folder for Passportal exports..."
foreach ($file in Get-ChildItem -Path ".\exported-csvs" -Filter "*.csv" -File | Sort-Object Name) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue

    $fullPath = $file.FullName
    $firstLine = (Get-Content -Path $fullPath -TotalCount 1).Trim()

    # Check if the first line appears to be a header
    $hasHeader = $firstLine -match 'PassPortal ID'

    if ($file.Name -like "*clients.csv") {
        $csv = if ($hasHeader) {
            Import-Csv -Path $fullPath
        } else {
            Import-Csv -Path $fullPath -Header "PassPortal ID","Name","Email"
        }
        $passportalData.csvData['clients'] = $csv
    } elseif ($file.Name -like "*passwords.csv") {
        $csv = if ($hasHeader) {
            Import-Csv -Path $fullPath
        } else {
            Import-Csv -Path $fullPath -Header "Passportal ID","Client Name","Credential","Username","Password","Description","Expires (Yes/No)","Notes","URL","Folder(Optional)"
        }
        $passportalData.csvData['passwords'] = $csv
    } elseif ($file.Name -like "*users.csv") {
        $csv = if ($hasHeader) {
            Import-Csv -Path $fullPath
        } else {
            Import-Csv -Path $fullPath -Header "Passportal ID (BLANK)","Last Name","First Name","Email","Phone"

        }
        $passportalData.csvData['users'] = $csv
    } elseif ($file.Name -like "*vault.csv") {
        $csv = if ($hasHeader) {
            Import-Csv -Path $fullPath
        } else {
            Import-Csv -Path $fullPath -Header "Passportal ID","Credential","Username","Password","Description","Expires (Yes/No)","Notes","URL","Folder(Optional)"
        }
        $passportalData.csvData['vault'] = $csv
    }        
}

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

foreach ($doctype in $passportalData.docTypes) {
    foreach ($client in $passportalData.Clients) {
        $page = 1
        while ($true) {
            Write-Host "Fetching $doctype for $($client.name); page $page"
            $baseURI = "https://us-clover.passportalmsp.com/api/v2/documents/all"
            $queryParams = @{
                type=$doctype
                orderBy="label"
                orderDir="asc"
                clientId=$client.id
                resultsPerPage=1000
                pageNum=$page
            }
            $resourceURI = "$baseURI?$(ConvertTo-QueryString -QueryParams $queryParams)"

            $response = Get-PassportalObjects -resource $resourceURI
            $results = $response.results

            if (-not $results -or -not $response.success -or -not $true -eq $response.success) {
                break
            } else {
                write-host "$($($results | convertto-json -depth 66).ToString())"
            }

            $passportalData.Documents += [pscustomobject]@{
                queryParams = $queryParams
                resourceURI = $resourceURI
                doctype     = $doctype
                clientId    = $client.id
                page        = $page
                data        = $results
            }
            write-host "$($($results | convertto-json -depth 66).ToString())"

            $page++
        }
    }
}g


Write-Host "Unsetting vars before next run."
# foreach ($var in $sensitiveVars) {
#     Unset-Vars -varname $var
# }