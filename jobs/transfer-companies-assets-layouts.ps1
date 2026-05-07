$TransferIDX=0
$TransferredTotal = $passportalData.Clients.count
$huducompanies = Get-HuduCompanies
$script:huduAssetCache = @{}

function ConvertTo-PassportalCompanyMatchName {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    return (normalize-companyName ([System.Net.WebUtility]::HtmlDecode([System.Net.WebUtility]::UrlDecode($Text)))).ToLowerInvariant()
}

function Test-PassportalDocumentPageBelongsToCompany {
    param(
        [AllowNull()]$DocumentPage,
        [Parameter(Mandatory)]$PPCompany
    )

    if ($null -eq $DocumentPage) { return $false }

    $companyId = Get-PPPropertyValue -Object $PPCompany -Name 'id'
    $client = Get-PPPropertyValue -Object $DocumentPage -Name 'client'
    $queryParams = Get-PPPropertyValue -Object $DocumentPage -Name 'queryParams'
    $pageClientId = Get-PPPropertyValue -Object $client -Name 'id'
    $queryClientId = Get-PPPropertyValue -Object $queryParams -Name 'clientId'

    if (Test-PassportalMeaningfulValue $companyId) {
        if ((Test-PassportalMeaningfulValue $pageClientId) -and "$pageClientId" -eq "$companyId") { return $true }
        if ((Test-PassportalMeaningfulValue $queryClientId) -and "$queryClientId" -eq "$companyId") { return $true }
    }

    $companyNames = @(
        (Get-PPPropertyValue -Object $PPCompany -Name 'decodedName')
        (Get-PPPropertyValue -Object $PPCompany -Name 'name')
    ) | ForEach-Object { ConvertTo-PassportalCompanyMatchName $_ } | Where-Object { $_ }

    $pageNames = @(
        (Get-PPPropertyValue -Object $client -Name 'decodedName')
        (Get-PPPropertyValue -Object $client -Name 'name')
    ) | ForEach-Object { ConvertTo-PassportalCompanyMatchName $_ } | Where-Object { $_ }

    foreach ($companyName in $companyNames) {
        if ($pageNames -contains $companyName) { return $true }
    }

    return $false
}

function Test-PassportalDocumentDataHasStrongCompanyReference {
    param([AllowNull()]$Data)

    if ($null -eq $Data) { return $false }
    foreach ($propertyName in @('client_id', 'clientId', 'clientName')) {
        if (Test-PassportalMeaningfulValue (Get-PPPropertyValue -Object $Data -Name $propertyName)) { return $true }
    }

    $client = Get-PPPropertyValue -Object $Data -Name 'client'
    if ($null -ne $client) {
        foreach ($propertyName in @('id', 'name', 'decodedName')) {
            if (Test-PassportalMeaningfulValue (Get-PPPropertyValue -Object $client -Name $propertyName)) { return $true }
        }
    }

    return $false
}

function Test-PassportalDocumentDataBelongsToCompany {
    param(
        [AllowNull()]$Data,
        [Parameter(Mandatory)]$PPCompany
    )

    if ($null -eq $Data) { return $false }

    $companyId = Get-PPPropertyValue -Object $PPCompany -Name 'id'
    $dataClientIds = @(
        (Get-PPPropertyValue -Object $Data -Name 'client_id')
        (Get-PPPropertyValue -Object $Data -Name 'clientId')
    ) | Where-Object { Test-PassportalMeaningfulValue $_ }

    $client = Get-PPPropertyValue -Object $Data -Name 'client'
    if ($null -ne $client) {
        $clientId = Get-PPPropertyValue -Object $client -Name 'id'
        if (Test-PassportalMeaningfulValue $clientId) { $dataClientIds += $clientId }
    }

    if (Test-PassportalMeaningfulValue $companyId) {
        foreach ($dataClientId in $dataClientIds) {
            if ("$dataClientId" -eq "$companyId") { return $true }
        }
    }

    $companyNames = @(
        (Get-PPPropertyValue -Object $PPCompany -Name 'decodedName')
        (Get-PPPropertyValue -Object $PPCompany -Name 'name')
    ) | ForEach-Object { ConvertTo-PassportalCompanyMatchName $_ } | Where-Object { $_ }

    $dataNames = @(
        (Get-PPPropertyValue -Object $Data -Name 'clientName')
        (Get-PPPropertyValue -Object $client -Name 'decodedName')
        (Get-PPPropertyValue -Object $client -Name 'name')
    ) | ForEach-Object { ConvertTo-PassportalCompanyMatchName $_ } | Where-Object { $_ }

    foreach ($companyName in $companyNames) {
        if ($dataNames -contains $companyName) { return $true }
    }

    $organizationId = Get-PPPropertyValue -Object $Data -Name 'organization_id'
    if ((Test-PassportalMeaningfulValue $companyId) -and (Test-PassportalMeaningfulValue $organizationId) -and "$organizationId" -eq "$companyId") {
        return $true
    }

    return $false
}

function Get-HuduAssetFieldValueForMigration {
    param(
        [AllowNull()]$Asset,
        [Parameter(Mandatory)][string]$FieldName
    )

    if ($null -eq $Asset) { return $null }
    $assetObject = $Asset.asset ?? $Asset
    $fieldBags = @(
        $assetObject.fields
        $assetObject.Fields
        $assetObject.custom_fields
        $assetObject.customFields
        $assetObject.asset_fields
        $assetObject.assetFields
    ) | Where-Object { $null -ne $_ }

    foreach ($fieldBag in $fieldBags) {
        if ($fieldBag -is [System.Collections.IDictionary]) {
            foreach ($key in $fieldBag.Keys) {
                if ("$key" -ieq $FieldName) {
                    return Resolve-PPValue $fieldBag[$key]
                }
            }
        }

        $direct = Get-PPPropertyValue -Object $fieldBag -Name $FieldName
        if ($null -ne $direct) { return Resolve-PPValue $direct }

        if ($fieldBag -is [System.Collections.IEnumerable] -and $fieldBag -isnot [string]) {
            foreach ($field in $fieldBag) {
                $label = (Get-PPPropertyValue -Object $field -Name 'label') ??
                         (Get-PPPropertyValue -Object $field -Name 'name') ??
                         (Get-PPPropertyValue -Object $field -Name 'field_name') ??
                         (Get-PPPropertyValue -Object $field -Name 'fieldName')
                if ($label -and "$label" -ieq $FieldName) {
                    foreach ($valueProp in @('value', 'Value', 'value_text', 'valueText', 'text')) {
                        $value = Get-PPPropertyValue -Object $field -Name $valueProp
                        if ($null -ne $value) { return Resolve-PPValue $value }
                    }
                    return Resolve-PPValue $field
                }
            }
        }
    }

    return $null
}

function Get-HuduAssetNameForMigration {
    param([AllowNull()]$Asset)
    if ($null -eq $Asset) { return $null }
    $assetObject = $Asset.asset ?? $Asset
    return $assetObject.name ?? $assetObject.Name
}

function Get-HuduAssetIdForMigration {
    param([AllowNull()]$Asset)
    if ($null -eq $Asset) { return $null }
    $assetObject = $Asset.asset ?? $Asset
    return $assetObject.id ?? $assetObject.Id
}

function Add-HuduAssetToMigrationIndexes {
    param(
        [Parameter(Mandatory)]$Indexes,
        [AllowNull()]$Asset
    )

    if ($null -eq $Asset) { return }
    $assetObject = $Asset.asset ?? $Asset
    $assetId = Get-HuduAssetIdForMigration -Asset $assetObject
    if (-not $assetId) { return }

    $ppId = Get-HuduAssetFieldValueForMigration -Asset $assetObject -FieldName 'PassPortalID'
    if (Test-PassportalMeaningfulValue $ppId) {
        $ppKey = "$ppId"
        if (-not $Indexes.ByPassPortalId.ContainsKey($ppKey)) {
            $Indexes.ByPassPortalId[$ppKey] = [System.Collections.Generic.List[object]]::new()
        }
        if (-not @($Indexes.ByPassPortalId[$ppKey] | Where-Object { "$(Get-HuduAssetIdForMigration -Asset $_)" -eq "$assetId" })) {
            [void]$Indexes.ByPassPortalId[$ppKey].Add($assetObject)
        }
    }

    $assetName = Get-HuduAssetNameForMigration -Asset $assetObject
    if (Test-PassportalMeaningfulValue $assetName) {
        $nameKey = "$assetName".Trim().ToLowerInvariant()
        if (-not $Indexes.ByName.ContainsKey($nameKey)) {
            $Indexes.ByName[$nameKey] = [System.Collections.Generic.List[object]]::new()
        }
        if (-not @($Indexes.ByName[$nameKey] | Where-Object { "$(Get-HuduAssetIdForMigration -Asset $_)" -eq "$assetId" })) {
            [void]$Indexes.ByName[$nameKey].Add($assetObject)
        }
    }
}

function Get-HuduAssetMigrationIndexes {
    param(
        [Parameter(Mandatory)][int]$CompanyId,
        [Parameter(Mandatory)][int]$LayoutId
    )

    $cacheKey = "$CompanyId|$LayoutId"
    if ($script:huduAssetCache.ContainsKey($cacheKey)) { return $script:huduAssetCache[$cacheKey] }

    $indexes = @{
        ByPassPortalId = @{}
        ByName = @{}
    }

    $assets = @()
    try {
        $assets = @(Get-HuduAssets -CompanyId $CompanyId -AssetLayoutId $LayoutId)
    } catch {
        Write-ErrorObjectsToFile -ErrorObject @{
            Error = $_
            During = "loading existing Hudu assets for company $CompanyId and layout $LayoutId"
        } -Name "ExistingAssets-$CompanyId-$LayoutId"
    }

    foreach ($asset in $assets) {
        Add-HuduAssetToMigrationIndexes -Indexes $indexes -Asset ($asset.asset ?? $asset)
    }

    $script:huduAssetCache[$cacheKey] = $indexes
    return $indexes
}

foreach ($PPcompany in $PassportalData.Clients) {
    $TransferIDX = $SourceDataIDX+1
    $completionPercentage = Get-PercentDone -current $TransferIDX -Total $TransferredTotal
    Write-Progress -Activity "Transferring items for $($PPcompany.decodedName)" -Status "$completionPercentage%" -PercentComplete $completionPercentage

    # Set, Match, Create, or Skip company
    $MatchedCompany=$(if ($true -eq $alwaysCreateCompanies) {@{Id= 0; Name="Create New"}} else {$null})
    $matchedCompany = $MatchedCompany ?? $(Get-HuduCompanyFromName -CompanyName $PPcompany.decodedName -HuduCompanies $huducompanies -deepCompanySearch $true) ?? $((Select-ObjectFromList -objects $runSummary.JobInfo.AttriutionOptions -message "Which Company would you like to attribute PassPortal Company $($PPcompany.id)- $($PPcompany.decodedName) to in Hudu?" -allowNull $false))

    if ($MatchedCompany.id -eq -1) {Set-PrintAndLog -message  "Skipping $($PPcompany.decodedName) per user request." -Color DarkCyan; continue}
    if ($MatchedCompany.id -eq  0) {
        Set-PrintAndLog -message  "Creating new Company, $($PPcompany.decodedName)" -Color DarkCyan
        try {
            $MatchedCompany = $(New-HuduCompany -Name $PPcompany.decodedName).company
            $CreatedCompanies += $MatchedCompany
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
        $MatchedCompanies+=@{PPcompany=$PPcompany; HuduCompany=$MatchedCompany}
    }
    # Migrate all doctypes for company, if no doctypes for company, skip for now
    foreach ($doctype in $passportalData.docTypes) {
        write-host "Starting doctype $doctype"
        $ObjectsForTransfer = @($passportaldata.Documents | Where-Object {
            $_.doctype -eq $doctype -and (Test-PassportalDocumentPageBelongsToCompany -DocumentPage $_ -PPCompany $PPcompany)
        })

        if ($ObjectsForTransfer.Count -lt 1) {
            $ObjectsForTransfer = @($passportaldata.Documents | Where-Object {
                if ($_.doctype -ne $doctype) { return $false }
                foreach ($dataRow in @($_.data)) {
                    if (Test-PassportalDocumentDataBelongsToCompany -Data $dataRow -PPCompany $PPcompany) { return $true }
                }
                return $false
            })
            if ($ObjectsForTransfer.Count -gt 0) {
                Set-PrintAndLog -message "Using row-level client ownership to find $doctype documents for $($PPcompany.decodedName)." -Color DarkYellow
            }
        }

        $transferDataCount = 0
        foreach ($transferPage in $ObjectsForTransfer) {
            $pageData = @($transferPage.data)
            $pageHasStrongCompanyReferences = @($pageData | Where-Object { Test-PassportalDocumentDataHasStrongCompanyReference -Data $_ }).Count -gt 0
            if ($pageHasStrongCompanyReferences) {
                $transferDataCount += @($pageData | Where-Object { Test-PassportalDocumentDataBelongsToCompany -Data $_ -PPCompany $PPcompany }).Count
            } else {
                $transferDataCount += $pageData.Count
            }
        }

        write-host "$transferDataCount objects found for $doctype doctype for $($PPcompany.decodedName)."
        if ($ObjectsForTransfer.Count -lt 1) { continue }
        if ($transferDataCount -lt 1) { continue }

        # Match layout in hudu to doctype in Passportal. Create if not in Hudu
        $layoutName = Set-Capitalized $doctype
        $matchedLayout = $HuduData.Data.assetlayouts | Where-Object { $_.name -eq $layoutName }
        $fieldMap = Get-PassportalFieldMapForType -Type $doctype
        if (-not $matchedLayout) {
            Set-PrintAndLog -message  "Creating new layout for $layoutName with fields $($($fieldMap | convertto-json -depth 66).ToString())" -Color DarkCyan
            try {
                $layoutDefault = $PassportalLayoutDefaults[$docType] ?? $PassportalLayoutDefaults.custom ?? @{ icon = "fas fa-puzzle-piece"; label = "Custom Docs" }
                $newLayout = New-HuduAssetLayout -name $layoutName -icon $layoutDefault.icon -color "#300797ff" -icon_color "#bed6a9ff" `
                    -include_passwords $true -include_photos $true -include_comments $true -include_files $true `
                    -fields $fieldMap
            } catch {
                Write-ErrorObjectsToFile -ErrorObject @{
                    Error = $_
                    During = "creating $($matchedLayout.name) layout to use with  $($doctype)"
                } -Name "LayoutCreate-$($layoutName ?? "$doctype")"
            }                
            $HuduData.Data.assetlayouts += $newLayout.asset_layout
            $CreatedLayouts += $newLayout.asset_layout
            $matchedLayout = $newLayout.asset_layout
        }
        if (-not $matchedLayout -or -not $matchedLayout.id) {
            Set-PrintAndLog -message "No usable Hudu layout was available for $layoutName; skipping $doctype assets for $($PPcompany.decodedName)." -Color DarkYellow
            continue
        }
        $existingAssetIndexes = Get-HuduAssetMigrationIndexes -CompanyId $MatchedCompany.id -LayoutId $matchedLayout.id
        

        # Create new asset for each doc in type
        foreach ($obj in $ObjectsForTransfer) {
            $detailById = @{}
            foreach ($detailItem in @($obj.details)) {
                if ($null -ne $detailItem -and $detailItem.ID) {
                    $detailById["$($detailItem.ID)"] = $detailItem
                }
            }

            $dataForTransfer = @($obj.data)
            if (@($dataForTransfer | Where-Object { Test-PassportalDocumentDataHasStrongCompanyReference -Data $_ }).Count -gt 0) {
                $dataForTransfer = @($dataForTransfer | Where-Object { Test-PassportalDocumentDataBelongsToCompany -Data $_ -PPCompany $PPcompany })
            }

            foreach ($data in $dataForTransfer) {
                if ($null -eq $data) { continue }

                $detail = $detailById["$($data.id)"]
                $fields = Get-PassportalDocumentFields -Detail $detail
                $fieldLookup = New-PassportalFieldLookup -ppFields $fields

                $newAsset = Get-TopLevelFieldforAsset -data $data `
                                                      -doctype $doctype `
                                                      -layoutId $matchedLayout.id `
                                                      -companyId $MatchedCompany.id `
                                                      -fields $fields `
                                                      -fieldLookup $fieldLookup
                $customFields = Get-NormalizedPassportalFields -ppFields $fields -fieldMap $fieldMap -passportalId $data.id -fieldLookup $fieldLookup
                if ($customFields -and $customFields.count -gt 0){
                    $newAsset["Fields"]=$customFields
                    Write-Host "$(Get-JsonString $customFields)"
                }

                $ExistingAsset = $null
                $existingMatchSource = $null
                $ppIdKey = "$($data.id)"
                if ($existingAssetIndexes.ByPassPortalId.ContainsKey($ppIdKey)) {
                    $matches = @($existingAssetIndexes.ByPassPortalId[$ppIdKey])
                    if ($matches.Count -eq 1) {
                        $ExistingAsset = $matches[0]
                        $existingMatchSource = "PassPortalID"
                    } elseif ($matches.Count -gt 1) {
                        Set-PrintAndLog -message "Multiple Hudu assets already have PassPortalID $ppIdKey for $($MatchedCompany.name) / $($matchedLayout.name). Skipping $($newAsset.Name) to avoid guessing." -Color DarkYellow
                        continue
                    }
                }

                if ($null -eq $ExistingAsset) {
                    $nameKey = "$($newAsset.Name)".Trim().ToLowerInvariant()
                    if ($existingAssetIndexes.ByName.ContainsKey($nameKey)) {
                        $matches = @($existingAssetIndexes.ByName[$nameKey])
                        if ($matches.Count -eq 1) {
                            $ExistingAsset = $matches[0]
                            $existingMatchSource = "name"
                        } elseif ($matches.Count -gt 1) {
                            Set-PrintAndLog -message "Multiple Hudu assets named $($newAsset.Name) already exist for $($MatchedCompany.name) / $($matchedLayout.name). Skipping because no unique PassPortalID match was found." -Color DarkYellow
                            continue
                        }
                    }
                }

                if ($null -ne $ExistingAsset) {
                    $newAsset["Id"] = Get-HuduAssetIdForMigration -Asset $ExistingAsset
                    Set-PrintAndLog -message "Existing asset matched by $existingMatchSource for Passportal doc $($data.id): $($newAsset.Name). Updating." -Color DarkCyan
                }

                try {
                    if ($null -ne $ExistingAsset -and $newAsset.Id -gt 0) {
                        $createdasset = $(Set-HuduAsset @newAsset)
                    } else {
                        $createdasset=$(New-HuduAsset @newAsset)
                    }
                    $createdasset=$createdasset.asset ?? $createdasset
                    if ($null -ne $createdasset){
                        Add-HuduAssetToMigrationIndexes -Indexes $existingAssetIndexes -Asset $createdasset
                        $CreatedAssets += @{
                            HuduAsset = $createdasset
                            PPasset   = @{Data = $data; Fields = $fields}
                            MatchedLayout = $matchedLayout
                            DocType = $doctype
                        }
                    } 
                } catch {
                    Write-ErrorObjectsToFile -ErrorObject @{
                        Error = $_
                        During = "creating $($matchedLayout.name) asset for $($MatchedCompany.name)"
                    } -Name "AssetCreate-$($data.label ?? "$doctype")"
                }
            }
        }
    }
}
