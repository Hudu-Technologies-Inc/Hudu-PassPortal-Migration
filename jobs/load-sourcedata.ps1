$loadSourceDataStartedAt = Get-Date
Set-PrintAndLog -message "Starting source-data load from Passportal..." -Color DarkBlue

$passportalData.Clients = $(Invoke-RestMethod -Headers $passportalData.Headers -Uri "$($passportalData.BaseURL)api/v2/documents/clients?resultsPerPage=1000" -Method Get).results
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
Set-PrintAndLog -message "Source-data load duration: $($sourceDataDuration.ToString())" -Color DarkBlue

Set-PrintAndLog -message "$(if ((-not $passportaldata.Documents -or $passportaldata.Documents.Count -lt 1)) {"Couldnt fetch any viable documents. Ensure Passportal API service is running and try again."} else {"Fetched $($passportaldata.Documents.count) Documents"})" -Color DarkCyan
foreach ($obj in $passportaldata.Documents){Set-PrintAndLog -message "$($obj.doctype) for $($obj.client): $(Write-InspectObject -object $obj.data)" -Color DarkCyan}
$passportalData.documents | ConvertTo-json -depth 88 | Out-File "export.json"
