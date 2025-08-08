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
$passportalData.BaseURL = "https://$($SelectedLocation.APIBase).passportalmsp.com/"

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
Set-IncrementedState -newState "Load Source Data"
$authResult = Get-PassportalAuthToken    
$passportalData.Token = $authResult.token
$passportalData.Headers = $authResult.headers
$passportalData.Clients = $(Invoke-RestMethod -Headers $passportalData.Headers -Uri "$($passportalData.BaseURL)api/v2/documents/clients?resultsPerPage=1000" -Method Get).results
foreach ($client in $passportalData.clients) {$client | Add-Member -NotePropertyName decodedName -NotePropertyValue $(Get-HTTPDecodedString $client.name) -Force; Set-PrintAndLog -message  "found $($client.id)-  $($client.decodedName)" -Color DarkCyan}
$passportalData.csvData = Get-CSVExportData -exportsFolder $(if ($(test-path $csvPath)) {$csvPath} else {Read-Host "Folder for CSV exports from Passportal?"})


$SourceDataIDX = 0
$SourceDataTotal = $passportalData.docTypes.Count * $passportalData.Clients.Count
try {foreach ($doctype in $passportalData.docTypes) {
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
                Write-Progress -Activity "Fetching $doctype for $($client.decodedName)" -Status "$completionPercentage%" -PercentComplete $completionPercentage
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
}} catch {
    Write-ErrorObjectsToFile -ErrorObject @{
        Error = $_
        During = "Fetch source data from Passportal"
    } -name "DataFetch-$SourceDataIDX-$SourceDataTotal"
}

Set-PrintAndLog -message "$(if ((-not $passportaldata.Documents -or $passportaldata.Documents.Count -lt 1)) {"Couldnt fetch any viable documents. Ensure Passportal API service is running and try again."} else {"Fetched $($passportaldata.Documents.count) Documents"})" -Color DarkCyan
foreach ($obj in $passportaldata.Documents){Set-PrintAndLog -message "$($obj.doctype) for $($obj.client): $(Write-InspectObject -object $obj.data)" -Color DarkCyan}
$passportalData.documents | ConvertTo-json -depth 88 | Out-File "export.json"

### LOAD DESTDATA and determine import strategy
##
#
Set-IncrementedState -newState "Obtain data from Hudu Instance- $(Get-HuduBaseURL)"
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
    $runSummary.JobInfo.AttriutionOptions.Add(@{id=$huducompany.id; name="$($huducompany.Name)"; decodedName="$($huducompany.Name)"})
    $companiesTable[$huducompany.id]=$huducompany
}
if ($Hududata.Data.companies.count -lt 1) {
    Set-PrintAndLog -message "Hudu doesnt have any companies yet- Opting to create companies instead of matching" -Color DarkCyan
    $alwaysCreateCompanies=$true
} else {
    Set-PrintAndLog -message "Found $($Hududata.Data.companies.count) Companies to Match for In Hudu" -Color DarkCyan
}

### Transfer assets, companies, and layouts into hudu
##
#
Set-IncrementedState -newState "Transfer assets, companies, and layouts into hudu"
$TransferIDX=0
$TransferredTotal = $passportalData.Clients.count
foreach ($PPcompany in $PassportalData.Clients) {
    $TransferIDX = $SourceDataIDX+1
    $completionPercentage = Get-PercentDone -current $TransferIDX -Total $TransferredTotal
    Write-Progress -Activity "Transferring items for $($PPcompany.decodedName)" -Status "$completionPercentage%" -PercentComplete $completionPercentage

    # Set, Match, Create, or Skip company
    $MatchedCompany=$(if ($true -eq $alwaysCreateCompanies) {@{Id= 0; Name="Create New"}} else {$(Select-ObjectFromList -objects $runSummary.JobInfo.AttriutionOptions -message "Which Company would you like to attribute PassPortal Company $($PPcompany.id)- $($PPcompany.name) to in Hudu?" -allowNull $false)})
    if ($MatchedCompany.id -eq -1) {Set-PrintAndLog -message  "Skipping $($PPcompany.decodedName) per user request." -Color DarkCyan; continue}
    if ($MatchedCompany.id -eq  0) {
        Set-PrintAndLog -message  "Creating new Company, $($PPcompany.decodedName)" -Color DarkCyan
        try {
            $MatchedCompany = New-HuduCompany -Name $PPcompany.decodedName
        } catch {
            Write-ErrorObjectsToFile -ErrorObject @{
                Error = $_
                During = "creating company for $($ppcompany.decodedName) in hudu"
            } -Name "CompanyCreate-$($ppcompany.decodedName ?? "na")"
        }            
        Set-PrintAndLog -message "Created new company $($($MatchedCompany.id))"
        $runSummary.JobInfo.AttriutionOptions.Add($matchedCompany)
    }
    if ($null -eq $MatchedCompany) {
        Set-PrintAndLog -message  "No Company matched or selected for $($PPcompany.decodedName), skipping" -Color DarkCyan; continue
    } else {
        Set-PrintAndLog -message  "Company set to $($MatchedCompany.name) for $($ppcompany.decodedName)" -Color DarkCyan
    }
    # Migrate all doctypes for company, if no doctypes for company, skip for now
    foreach ($doctype in $passportalData.docTypes) {
        write-host "Starting doctype $doctype"
        
        $ObjectsForTransfer = $passportaldata.Documents  | where-object {$_.data.type -eq $doctype -and $($_.data.client_id -eq $PPcompany.id -or $_.data.clientName -eq $PPcompany.decodedName)}
        # Match layout in hudu to doctype in Passportal. Create if not in Hudu
        $layoutName = Set-Capitalized $doctype
        $matchedLayout = $HuduData.Data.assetlayouts | Where-Object { $_.name -eq $layoutName }
        $fieldMap = Get-PassportalFieldMapForType -Type $doctype
        if (-not $matchedLayout) {
            Set-PrintAndLog -message  "Creating new layout for $layoutName with fields $($($fieldMap | convertto-json -depth 66).ToString())" -Color DarkCyan
            try {
                $newLayout = New-HuduAssetLayout -name $layoutName -icon $($PassportalLayoutDefaults[$docType]).icon -color "#300797ff" -icon_color "#bed6a9ff" `
                    -include_passwords $true -include_photos $true -include_comments $true -include_files $true `
                    -fields $fieldMap
            } catch {
                Write-ErrorObjectsToFile -ErrorObject @{
                    Error = $_
                    During = "creating $($matchedLayout.name) layout to use with  $($doctype)"
                } -Name "LayoutCreate-$($layoutName ?? "$doctype")"
            }                
            $HuduData.Data.assetlayouts += $newLayout.asset_layout
            $matchedLayout = $newLayout.asset_layout
        }
        

        # Create new asset for each doc in type
        foreach ($obj in $ObjectsForTransfer) {

            $data = $obj.data[0]

            $fields = $obj.details[0].Fields ??  $obj.details[0].Fields[0] ?? @()

            $newAsset = Get-TopLevelFieldforAsset -data $data `
                                                  -doctype $doctype `
                                                  -layoutId $matchedLayout.id `
                                                  -companyId $MatchedCompany.id `
                                                  -fields $fields
            $ppIndex = Get-NormalizedPassportalFields -ppFields $fields
            $mappedValues = Set-PPToHuduFieldValues -FieldMap $fieldMap -PPIndex $ppIndex
            $customFields = Build-HuduCustomFields -FieldMap $fieldMap -HuduValuesByLabel $mappedValues
            if ($customFields -and $customFields.count -gt 0) {
                $newAsset["fields"] = $customFields
            }
            Write-Host "creating asset $(Get-JsonString $newAsset)"
            try {
                New-HuduAsset @newAsset
            } catch {
                Write-ErrorObjectsToFile -ErrorObject @{
                    Error = $_
                    During = "creating $($matchedLayout.name) asset for $($MatchedCompany.name)"
                } -Name "AssetCreate-$($obj.data[0].label ?? "$doctype")"
            }
        }
    }
}

# Set-IncrementedState -newState "Import and match passwords from CSV data"
# $passportalData.csvData = $passportalData.csvData ?? $(Get-CSVExportData -exportsFolder $(if ($(test-path $csvPath)) {$csvPath} else {Read-Host "Folder for CSV exports from Passportal?"}))
# if ($null -eq $passportalData.csvData) {
#     Set-Prontandlog -message "Sorry, we dont have any CSV data in your exports directory needed to migrate passwords..."
# }



# Set-IncrementedState -newState "Import and match websites from SSL data"



Set-IncrementedState -newState "Set Layouts as active, Wrap-Up, and Unsetting $($sensitiveVars.count) sensitive vars"
foreach ($layout in Get-HuduAssetLayouts) {Set-PrintAndLog -message "setting $($(Set-HuduAssetLayout -id $layout.id -Active $true).asset_layout.name) as active" -Color DarkMagenta }
Set-PrintAndLog -message  ""
foreach ($var in $sensitiveVars) {
    Unset-Vars -varname $var
}