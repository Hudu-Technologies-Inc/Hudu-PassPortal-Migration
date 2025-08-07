$workdir = $PSScriptRoot
### CONFIGURATION
##
#
$passportalData = @{
    docTypes = @("asset","active_directory","application","backup","email","folders","file_sharing","contact","location","internet","lan","printing","remote_access","vendor","virtualization","voice","wireless","licencing","custom","ssl");
    APIkey = $($passportalData_APIkey ?? "$(read-host "please enter your Passportal API key")"); APIkeyId = $($passportalData_APIkeyId ?? "$(read-host "please enter your Passportal API key")")
    Token = $null; Headers = @{}; BaseURL = $null; clients=@(); Documents =@(); csvData = @{}
}

$sensitiveVars = @("PassportalApiKey","PassportalApiKeyId","HuduApiKey","PassPortalHeaders","passportalData")
$HuduBaseURL = $HuduBaseURL ?? "$(read-host "please enter your Hudu Base url")"
$HuduAPIKey = $HuduAPIKey ?? "$(read-host "please enter your Hudu API Key")"
$SelectedLocation = $SelectedLocation ?? $(Select-ObjectFromList -allowNull $false -objects $PPBaseURIs -message "Choose your Location for Passportal API access")
Write-Host "using $($selectedLocation.name) / $BaseUri for PassPortal"
$passportalData.BaseURL = "https://$($SelectedLocation.APIBase).passportalmsp.com/"

### SETUP
##
#
foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
Set-Content -Path $logFile -Value "Starting Passportal Migration" 
Set-PrintAndLog -message "Checked Powershell Version... $(Get-PSVersionCompatible)" -Color DarkBlue
Set-PrintAndLog -message "Imported Hudu Module... $(Get-HuduModule)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Credentials... $(Set-HuduInstance)" -Color DarkBlue
Set-PrintAndLog -message "Checked Hudu Version... $(Get-HuduVersionCompatible)" -Color DarkBlue
Set-IncrementedState -newState "Check Source data and get Source Data Options"

### LOAD SOURCEDATA
##
#
$authResult = Get-PassportalAuthToken    
$passportalData.Token = $authResult.token
$passportalData.Headers = $authResult.headers
write-host $passportalData.Token

$passportalData.Clients = $(Invoke-RestMethod -Headers $passportalData.Headers -Uri "$($passportalData.BaseURL)api/v2/documents/clients?resultsPerPage=1000" -Method Get -Verbose).results
foreach ($client in $passportalData.Clients) {Write-Host "found $($client.id)- $($client.name)"}
Get-CSVExportData -exportsFolder $(Join-Path $workdir "exported-csvs")

$SourceDataIDX=0
$SourceDataTotal=$($doctype.Count * $client.Count)
foreach ($doctype in $passportalData.docTypes) {
    foreach ($client in $passportalData.Clients) {
        $SourceDataIDX = $SourceDataIDX+1
        $completionPercentage = Get-PercentDone -current $SourceDataIDX -Total $SourceDataTotal
        Write-Progress -Activity "Fetching $doctype for $($client.name)" -Status "$completionPercentage%" -PercentComplete $completionPercentage

        $page = 1
        while ($true) {
            $queryParams = @{
                type=$doctype
                orderBy="label"
                orderDir="asc"
                clientId=$client.id
                resultsPerPage=1000
                pageNum=$page
            }
            $resourceURI = "documents/all?$(ConvertTo-QueryString -QueryParams $queryParams)"

            $response = Get-PassportalObjects -resource $resourceURI
            $results = $response.results

            if (-not $results -or $results -eq $null -or "$results".ToLower() -eq 'null' -or -not $response.success -or -not $true -eq $response.success) {
                break
            }

            $passportalData.Documents += [pscustomobject]@{
                queryParams = $queryParams
                resourceURI = $resourceURI
                doctype     = $doctype
                client      = $client
                page        = $page
                data        = $results
            }
            $page++
        }
    }
}
if (-not $passportaldata.Documents -or $passportaldata.Documents.Count -lt 1){
    Write-Host "Couldnt fetch any viable documents. Ensure Passportal API service is running and try again."
    exit
}
foreach ($obj in $passportaldata.Documents){
    Write-Host "$($obj.doctype) for $($obj.client): $(Write-InspectObject -object $obj.data)"
}
$passportaldata.Documents | ConvertTo-Json -Depth 45 | Out-File "export.json"


### LOAD DESTDATA and determine import path
##
#
Write-Host "obtaining data from Hudu!"
$HuduData = @{
    Resources = @(
        @{name="companies"; request="Get-HuduCompanies"},
        @{name="assets"; request="Get-HuduAssets"},
        @{name="articles"; request="Get-HuduArticles"},
        @{name="websites"; request="Get-HuduWebsites"},
        @{name="assetlayouts"; request="Get-HuduAssetLayouts"},
        @{name="articles"; request="Get-HuduArticles"},
        @{name="passwords"; request="Get-HuduArticles"},
        @{name="folders"; request="Get-HuduArticles"},
        @{name="passwordfolders"; request="Get-HuduArticles"},
        @{name="lists"; request="Get-HuduLists"},
        @{name="procedures"; request="Get-HuduProcedures"}
    )
    Data = @{}
    AssetLayoutNames = @{}
}

$resourceIDX=0
foreach ($resource in $HuduData.Resources) {
    $resourceIDX=$resourceIDX+1
    $completionPercentage = Get-PercentDone -current $resourceIDX -Total $HuduData.Resources.count
    Write-Progress -Activity "Obtaining Data from Hudu... Resource- $($resource.name)" -Status "$completionPercentage%" -PercentComplete $completionPercentage
    $result = & $resource.request
    $HuduData.Data[$resource.name] = $($result ?? @())
}
$companiesTable = @{}
foreach ($huduCompany in $Hududata.Data.companies){
    $runSummary.JobInfo.AttriutionOptions.Add(@{Id=$huducompany.id; Name="$($huducompany.Name)"})
    $companiesTable[$huducompany.id]=$huducompany
}
$HuduData.AssetLayoutNames = $HuduData.Data.AssetLayouts
if (-not $HuduData.AssetLayoutNames -contains "Location" -or -not $HuduData.AssetLayoutNames -contains "Locations"){
    $newLocationLayout = New-Huduassetlayout -name "Locations" -icon "fas fa-$NewIcon" -color "#00adef" -icon_color "#ffffff" -include_passwords $true -include_photos $true -include_comments $true -include_files $true -fields $LocAssetLayoutFields 
    $HuduData.AssetLayoutNames+=$newLocationLayout.asset_layout.name
    $HuduData.Data.assetlayouts+=$newLocationLayout.asset_layout
}





foreach ($PPcompany in $passportalData.Clients) {
    $MatchedCompany  = Select-ObjectFromList -objects $runSummary.JobInfo.AttriutionOptions -message "Which Company would you like to attribute PassPortal Company $($PPcompany.id)- $($PPcompany.name) to in Hudu?" -allowNull $false
    if ($MatchedCompany.id -eq -1) {
        write-host "Skipping $($PPcompany.name) per user request."
        continue
    }
    if ($MatchedCompany.id -eq  0) {
        write-host "Creating new Company, "
        $MatchedCompany = New-HuduCompany -Name $PPcompany.name
        $runSummary.JobInfo.AttriutionOptions.Add($matchedCompany)
    }
    foreach ($doctype in $passportalData.docTypes) {
        $ObjectsForTransfer =  $passportaldata.Documents | Where-Object { $_.data.type -eq $doctype -and $_.client.id -eq $PPCompany.id}
        if (-not $ObjectsForTransfer -or $ObjectsForTransfer.count -lt 1){
            write-host "Skipping doctype $doctype transfer for $($ppcompany.name). None present in export/dump"
            continue
        }
        $layoutName = Set-Capitalized $doctype
        $matchedLayout = $HuduData.Data.assetlayouts | Where-Object { $_.name -eq $layoutName }

        if (-not $matchedLayout) {
            Write-Host "Creating new layout for $layoutName"
            New-HuduAssetLayout -name $layoutName -icon $($PassportalLayoutDefaults[$docType]).icon -color "#300797ff" -icon_color "#bed6a9ff" `
                -include_passwords $true -include_photos $true -include_comments $true -include_files $true `
                -fields $(Get-PassportalFieldMapForType -Type $doctype)
            $HuduData.Data.assetlayouts += $newLayout.asset_layout
            $matchedLayout = $newLayout.asset_layout
        }
        $fieldMap = Get-PassportalFieldMapForType -Type $doctype
        foreach ($obj in $ObjectsForTransfer) {
            New-HuduAsset -name $($obj.data.label ?? $obj.data.name ?? $obj.data.title ?? "Unnamed $doctype") `
                -companyId $MatchedCompany.id -layoutId $matchedLayout.id `
                -fields $(Build-HuduFieldsFromDocument -FieldMap $fieldMap -Document $obj)
        }
    }
}














Write-Host "Unsetting vars before next run."
# foreach ($var in $sensitiveVars) {
#     Unset-Vars -varname $var
# }