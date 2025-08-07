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

$passportalData.Clients = $(Invoke-RestMethod -Headers $passportalData.Headers -Uri "$($passportalData.BaseURL)api/v2/documents/clients?resultsPerPage=1000" -Method Get).results
foreach ($client in $passportalData.Clients) {Write-Host "found $($client.id)- $($client.name)"}
$passportalData.csvData = Get-CSVExportData -exportsFolder $(if ($(test-path $csvPath)) {$csvPath} else {Read-Host "Folder for CSV exports from Passportal?"})

$SourceDataIDX=0
$SourceDataTotal = $passportalData.docTypes.Count * $passportalData.Clients.Count

$SourceDataIDX = 0
$SourceDataTotal = $passportalData.docTypes.Count * $passportalData.Clients.Count
$DetailedDocumentsById = @{}

foreach ($doctype in $passportalData.docTypes) {
    foreach ($client in $passportalData.Clients) {
        $page = 1
        while ($true) {
            $queryParams = @{
                type = $doctype
                orderBy = "label"
                orderDir = "asc"
                clientId = $client.id
                resultsPerPage = 1000
                pageNum = $page
            }

            $resourceURI = "documents/all?$(ConvertTo-QueryString -QueryParams $queryParams)"
            $response = Get-PassportalObjects -resource $resourceURI
            $results = @($response.results)

            if (-not $results -or -not $response.success -or "$results".ToLower() -eq 'null') {
                $SourceDataIDX++
                $completionPercentage = Get-PercentDone -current $SourceDataIDX -Total $SourceDataTotal
                Write-Progress -Activity "Fetching $doctype for $($client.name)" -Status "$completionPercentage%" -PercentComplete $completionPercentage
                break
            }

            $details = @()
            foreach ($doc in $results) {
                $docId = $doc.id
                if (-not $docId) { continue }
                    $detail = $null
                    $detail=[pscustomobject]@{
                        ID=$docId
                        Fields=$(try {$(Invoke-RestMethod -Uri "$($passportalData.BaseURL)api/v2/documents/$docId" -Headers $passportalData.Headers -Method Get).details
                                } catch {
                                Write-Warning "Failed to fetch detailed doc $docId... $($_.Exception.Message)"
                                $null
                        })}

                    $Details+=$detail
                }
            
            $passportalData.Documents += [pscustomobject]@{
                queryParams = $queryParams
                resourceURI = $resourceURI
                doctype     = $doctype
                client      = $client
                page        = $page
                data        = $results
                details     = $details
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
$passportalData.documents | ConvertTo-json -depth 88 | Out-File "export.json"


### LOAD DESTDATA and determine import strategy
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
    $HuduData.Data[$resource.name] =$HuduData.Data[$resource.name] ?? @()
    if ($result) {$HuduData.Data[$resource.name]+=$result}
}
$alwaysCreateCompanies=$false
$companiesTable = @{}
foreach ($huduCompany in $Hududata.Data.companies){
    $runSummary.JobInfo.AttriutionOptions.Add(@{Id=$huducompany.id; Name="$($huducompany.Name)"})
    $companiesTable[$huducompany.id]=$huducompany
}
if ($Hududata.Data.companies.count -lt 1) {
    Write-Host "Hudu doesnt have any companies yet- Opting to create companies instead of matching"
    $alwaysCreateCompanies=$true
}

### Transfer assets, companies, and layouts into hudu
##
#
$TransferIDX=0
$TransferredTotal = $passportalData.Clients.count
foreach ($PPcompany in $PassportalData.Clients) {
    $TransferIDX = $SourceDataIDX+1
    $completionPercentage = Get-PercentDone -current $TransferIDX -Total $TransferredTotal
    Write-Progress -Activity "Transferring items for $($PPcompany.name)" -Status "$completionPercentage%" -PercentComplete $completionPercentage

    # Set, Match, Create, or Skip company
    $MatchedCompany=$(if ($true -eq $alwaysCreateCompanies) {@{Id= 0; Name="Create New"}} else {$(Select-ObjectFromList -objects $runSummary.JobInfo.AttriutionOptions -message "Which Company would you like to attribute PassPortal Company $($PPcompany.id)- $($PPcompany.name) to in Hudu?" -allowNull $false)})
    if ($MatchedCompany.id -eq -1) {write-host "Skipping $($PPcompany.name) per user request."; continue}
    if ($MatchedCompany.id -eq  0) {
        write-host "Creating new Company, $($PPcompany.name)"
        $MatchedCompany = New-HuduCompany -Name $PPcompany.name
        $runSummary.JobInfo.AttriutionOptions.Add($matchedCompany)
    }
    Write-Host "Company set to $($MatchedCompany.name) for $($ppcompany.name)"

    # Migrate all doctypes for company, if no doctypes for company, skip for now
    foreach ($doctype in $passportalData.docTypes) {
        $ObjectsForTransfer =  $passportaldata.Documents.data | Where-Object { $_.data.type -eq $doctype -and $_.client.id -eq $PPCompany.id}
        if (-not $ObjectsForTransfer -or $ObjectsForTransfer.count -lt 1){write-host "Skipping doctype $doctype transfer for $($ppcompany.name). None present in export/dump"; continue}

    # Match layout in hudu to doctype in Passportal. Create if not in Hudu
        $layoutName = Set-Capitalized $doctype
        $matchedLayout = $HuduData.Data.assetlayouts | Where-Object { $_.name -eq $layoutName }
        if (-not $matchedLayout) {
            Write-Host "Creating new layout for $layoutName"
            $newLayout = New-HuduAssetLayout -name $layoutName -icon $($PassportalLayoutDefaults[$docType]).icon -color "#300797ff" -icon_color "#bed6a9ff" `
                -include_passwords $true -include_photos $true -include_comments $true -include_files $true `
                -fields $(Get-PassportalFieldMapForType -Type $doctype)
            $HuduData.Data.assetlayouts += $newLayout.asset_layout
            $matchedLayout = $newLayout.asset_layout
        }
    # Create new asset for each doc in type
        foreach ($obj in $ObjectsForTransfer) {
            $fields = $passportalData.documents.details | Where-Object { $_.ID -eq $Document.data.id }



            New-HuduAsset -name "$($obj.data.label ?? $obj.data.name ?? $obj.data.title ?? "Unnamed $doctype")" `
                -companyId $MatchedCompany.id -AssetLayoutId $matchedLayout.id `
                -fields $(Build-HuduFieldsFromDocument -FieldMap $(Get-PassportalFieldMapForType -Type $doctype) -Document $obj)
        }
    }
}














Write-Host "Unsetting vars before next run."
# foreach ($var in $sensitiveVars) {
#     Unset-Vars -varname $var
# }