$TransferIDX=0
$TransferredTotal = $passportalData.Clients.count
foreach ($PPcompany in $PassportalData.Clients) {
    $TransferIDX = $SourceDataIDX+1
    $completionPercentage = Get-PercentDone -current $TransferIDX -Total $TransferredTotal
    Write-Progress -Activity "Transferring items for $($PPcompany.decodedName)" -Status "$completionPercentage%" -PercentComplete $completionPercentage

    # Set, Match, Create, or Skip company
    $MatchedCompany=$(if ($true -eq $alwaysCreateCompanies) {@{Id= 0; Name="Create New"}} else {$(Select-ObjectFromList -objects $runSummary.JobInfo.AttriutionOptions -message "Which Company would you like to attribute PassPortal Company $($PPcompany.id)- $($PPcompany.decodedName) to in Hudu?" -allowNull $false)})
    if ($MatchedCompany.id -eq -1) {Set-PrintAndLog -message  "Skipping $($PPcompany.decodedName) per user request." -Color DarkCyan; continue}
    if ($MatchedCompany.id -eq  0) {
        Set-PrintAndLog -message  "Creating new Company, $($PPcompany.decodedName)" -Color DarkCyan
        try {
            $MatchedCompany = $(New-HuduCompany -Name $PPcompany.decodedName).company
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

            $fields = $obj.details[0].Fields ?? @()

            $newAsset = Get-TopLevelFieldforAsset -data $data `
                                                  -doctype $doctype `
                                                  -layoutId $matchedLayout.id `
                                                  -companyId $MatchedCompany.id `
                                                  -fields $fields
            $customFields = Get-NormalizedPassportalFields -ppFields $fields -fieldMap $fieldMap -passportalId $data.id
            if ($customFields -and $customFields.count -gt 0){
                $newAsset["Fields"]=$customFields
                Write-Host "$(Get-JsonString $customFields)"
            }


            try {
                $createdasset=$(New-HuduAsset @newAsset)
                if ($null -ne $createdasset){
                    $CreatedAssets += @{
                        HuduAsset = $($createdasset).asset
                        PPasset   = @{Data = $data; Fields = $fields}
                        MatchedLayout = $matchedLayout
                        DocType = $doctype
                    }
                } 
            } catch {
                Write-ErrorObjectsToFile -ErrorObject @{
                    Error = $_
                    During = "creating $($matchedLayout.name) asset for $($MatchedCompany.name)"
                } -Name "AssetCreate-$($obj.data[0].label ?? "$doctype")"
            }
        }
    }
}
