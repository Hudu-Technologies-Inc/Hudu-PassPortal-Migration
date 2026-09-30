$loadSourceDataStartedAt = Get-Date
Set-PrintAndLog -message "Starting source-data load from Passportal..." -Color DarkBlue

function Get-SafePassportalApiDumpName {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return "unknown-instance" }

    $safeName = [System.Net.WebUtility]::HtmlDecode("$Name").Trim().ToLowerInvariant()
    $safeName = $safeName -replace '^(?i)https?://', ''
    $safeName = $safeName -replace '/+$', ''
    $safeName = $safeName -replace '[\\/:*?"<>|]+', '-'
    $safeName = $safeName -replace '[^a-z0-9._-]+', '-'
    $safeName = $safeName -replace '-+', '-'
    $safeName = $safeName.Trim('-')

    if ([string]::IsNullOrWhiteSpace($safeName)) { return "unknown-instance" }
    return $safeName
}

function Get-PassportalApiDumpInstanceName {
    if (Test-PassportalMeaningfulValue $PassportalApiDumpInstanceName) { return "$PassportalApiDumpInstanceName" }
    if (Test-PassportalMeaningfulValue $HuduBaseURL) { return "$HuduBaseURL" }
    if (Test-PassportalMeaningfulValue $SelectedLocation.APIBase) { return "passportal-$($SelectedLocation.APIBase)" }
    if (Test-PassportalMeaningfulValue $passportalData.BaseURL) { return "$($passportalData.BaseURL)" }
    return "unknown-instance"
}

$passportalApiDumpInstanceName = Get-SafePassportalApiDumpName (Get-PassportalApiDumpInstanceName)
$passportalApiDumpPath = $PassportalApiDumpPath ?? (Join-Path $workdir "export-$passportalApiDumpInstanceName.json")
$passportalApiDumpMaxAgeHours = $PassportalApiDumpMaxAgeHours ?? 8
Set-PrintAndLog -message "Passportal API dump path set to '$passportalApiDumpPath'." -Color DarkGray

function Get-PassportalClientsFromApiDump {
    param(
        [AllowNull()][array]$Documents
    )

    $clients = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($documentPage in @($Documents)) {
        $client = Get-PPPropertyValue -Object $documentPage -Name 'client'
        if ($null -eq $client) { continue }

        $clientId = ConvertTo-PassportalIdString (Get-PPPropertyValue -Object $client -Name 'id')
        $clientName = Get-PPPropertyValue -Object $client -Name 'name'
        $key = $clientId ?? "$clientName"
        if (-not (Test-PassportalMeaningfulValue $key)) { continue }

        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$clients.Add($client)
        }
    }

    return $clients.ToArray()
}

function Get-PassportalDocumentsFromApiDump {
    param(
        [AllowNull()]$Dump
    )

    if ($null -eq $Dump) { return @() }

    $documents = Get-PPPropertyValue -Object $Dump -Name 'Documents'
    if ($null -eq $documents) { $documents = Get-PPPropertyValue -Object $Dump -Name 'documents' }
    if ($null -ne $documents) { return @($documents) }

    return @($Dump)
}

function Get-PassportalDocumentDataCount {
    param(
        [AllowNull()][array]$Documents
    )

    $count = 0
    foreach ($documentPage in @($Documents)) {
        $count += @($documentPage.data).Count
    }
    return $count
}

if (Test-Path -LiteralPath $passportalApiDumpPath -PathType Leaf) {
    $dumpFile = Get-Item -LiteralPath $passportalApiDumpPath
    $dumpAge = (Get-Date) - $dumpFile.LastWriteTime
    if ($dumpAge.TotalHours -le [double]$passportalApiDumpMaxAgeHours) {
        try {
            Set-PrintAndLog -message "Using cached Passportal API dump '$passportalApiDumpPath' from $($dumpFile.LastWriteTime) ($([math]::Round($dumpAge.TotalHours, 2)) hours old)." -Color DarkBlue
            $cachedDump = Get-Content -LiteralPath $passportalApiDumpPath -Raw | ConvertFrom-Json
            $passportalData.Documents = @(Get-PassportalDocumentsFromApiDump -Dump $cachedDump)
            if (-not $passportalData.Documents -or $passportalData.Documents.Count -lt 1) {
                throw "Cached Passportal API dump contained no document pages."
            }
            $passportalData.Clients = @(Get-PassportalClientsFromApiDump -Documents $passportalData.Documents)
            $foundDocs = Get-PassportalDocumentDataCount -Documents $passportalData.Documents

            Set-PrintAndLog -message "Loaded $($passportalData.Documents.Count) cached document pages, $foundDocs source row(s), and $($passportalData.Clients.Count) clients from Passportal API dump." -Color DarkBlue

            Set-PrintAndLog -message "Beginning CSV export discovery/import..." -Color DarkBlue
            $passportalData.csvData = Get-CSVExportData -exportsFolder $(if ($(test-path "$csvPath")) {$csvPath} else {Read-Host "Folder for CSV exports from Passportal?"})
            Set-PrintAndLog -message "CSV export discovery/import complete." -Color DarkBlue

            $loadSourceDataEndedAt = Get-Date
            $sourceDataDuration = New-TimeSpan -Start $loadSourceDataStartedAt -End $loadSourceDataEndedAt
            Set-PrintAndLog -message "Source-data load duration: $($sourceDataDuration.ToString())" -Color DarkBlue
            Set-PrintAndLog -message "$(if ((-not $passportaldata.Documents -or $passportaldata.Documents.Count -lt 1)) {"Couldnt load any viable documents from cached Passportal API dump."} else {"Loaded $($passportaldata.Documents.count) cached Documents"})" -Color DarkCyan
            foreach ($obj in $passportaldata.Documents){Set-PrintAndLog -message "$($obj.doctype) for $($obj.client): $(Write-InspectObject -object $obj.data)" -Color DarkCyan}
            return
        } catch {
            Set-PrintAndLog -message "Could not load cached Passportal API dump '$passportalApiDumpPath'; fetching fresh data. $($_.Exception.Message)" -Color DarkYellow
        }
    } else {
        Set-PrintAndLog -message "Cached Passportal API dump '$passportalApiDumpPath' is $([math]::Round($dumpAge.TotalHours, 2)) hours old, which is older than $passportalApiDumpMaxAgeHours hours. Fetching fresh data." -Color DarkYellow
    }
}

$passportalData.Clients = @()
$clientPage = 1
$clientResultsPerPage = 100
while ($true) {
    $clientQueryParams = @{
        resultsPerPage = $clientResultsPerPage
        pageNum = $clientPage
    }

    $clientResourceURI = "documents/clients?$(ConvertTo-QueryString -QueryParams $clientQueryParams)"
    $clientResponse = Get-PassportalObjects -resource $clientResourceURI
    $clientResults = @($clientResponse.results)
    $clientResultCount = @($clientResults).Count

    Set-PrintAndLog -message "Client page $clientPage returned $clientResultCount rows." -Color DarkGray

    if (-not $clientResults -or -not $clientResponse.success -or "$clientResults".ToLower() -eq 'null') {
        break
    }

    $passportalData.Clients += $clientResults
    $clientPage++
}
Set-PrintAndLog -message "Loaded $($passportalData.Clients.Count) clients from Passportal." -Color DarkBlue
foreach ($client in $passportalData.clients) {$client | Add-Member -NotePropertyName decodedName -NotePropertyValue $(Get-HTTPDecodedString $client.name) -Force; Set-PrintAndLog -message  "found $($client.id)-  $($client.decodedName)" -Color DarkCyan}

Set-PrintAndLog -message "Beginning CSV export discovery/import..." -Color DarkBlue
$passportalData.csvData = Get-CSVExportData -exportsFolder $(if ($(test-path "$csvPath")) {$csvPath} else {Read-Host "Folder for CSV exports from Passportal?"})
Set-PrintAndLog -message "CSV export discovery/import complete." -Color DarkBlue


$SourceDataIDX = 0
$SourceDataTotal = $passportalData.docTypes.Count * $passportalData.Clients.Count
Set-PrintAndLog -message "Starting Passportal document crawl for $($passportalData.docTypes.Count) doc types across $($passportalData.Clients.Count) clients ($SourceDataTotal client/type combinations)." -Color DarkBlue
try {foreach ($doctype in $passportalData.docTypes) {
    foreach ($client in $passportalData.Clients) {
        Set-PrintAndLog -message "Fetching '$doctype' documents for client '$($client.decodedName)' ($($client.id))..." -Color DarkBlue
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
            $resultCount = @($results).Count

            Set-PrintAndLog -message "Page $page for '$doctype' / '$($client.decodedName)' returned $resultCount rows." -Color DarkGray

            if (-not $results -or -not $response.success -or "$results".ToLower() -eq 'null') {
                $SourceDataIDX++
                $completionPercentage = Get-PercentDone -current $SourceDataIDX -Total $SourceDataTotal
                Write-Progress -Activity "Fetching $doctype for $($client.decodedName)" -Status "$completionPercentage%" -PercentComplete $completionPercentage
                break
            }

            $details = @()
            $detailFetchIdx = 0
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
                    $detailFetchIdx++
                    if ($detailFetchIdx % 100 -eq 0) {
                        Set-PrintAndLog -message "Fetched detail for $detailFetchIdx / $resultCount docs on page $page ('$doctype' / '$($client.decodedName)')." -Color DarkGray
                    }
                }

            if ($resultCount -gt 0) {
                Set-PrintAndLog -message "Completed detail fetch for page $page ('$doctype' / '$($client.decodedName)')." -Color DarkGray
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
            $foundDocs = $foundDocs+1
            $page++
        }

        Set-PrintAndLog -message "Completed '$doctype' for client '$($client.decodedName)'." -Color DarkBlue
    }
}} catch {
    Write-ErrorObjectsToFile -ErrorObject @{
        Error = $_
        During = "Fetch source data from Passportal"
    } -name "DataFetch-$SourceDataIDX-$SourceDataTotal"
}

$loadSourceDataEndedAt = Get-Date
$sourceDataDuration = New-TimeSpan -Start $loadSourceDataStartedAt -End $loadSourceDataEndedAt
$foundDocs = Get-PassportalDocumentDataCount -Documents $passportalData.Documents
Set-PrintAndLog -message "Source-data load duration: $($sourceDataDuration.ToString())" -Color DarkBlue

Set-PrintAndLog -message "$(if ((-not $passportaldata.Documents -or $passportaldata.Documents.Count -lt 1)) {"Couldnt fetch any viable documents. Ensure Passportal API service is running and try again."} else {"Fetched $($passportaldata.Documents.count) document pages with $foundDocs source row(s)"})" -Color DarkCyan
foreach ($obj in $passportaldata.Documents){Set-PrintAndLog -message "$($obj.doctype) for $($obj.client): $(Write-InspectObject -object $obj.data)" -Color DarkCyan}
$passportalData.documents | ConvertTo-json -depth 88 | Out-File -LiteralPath $passportalApiDumpPath
