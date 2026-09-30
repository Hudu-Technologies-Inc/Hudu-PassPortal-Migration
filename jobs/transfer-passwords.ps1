$passportalData.csvData = $passportalData.csvData ?? $(Get-CSVExportData -exportsFolder $(if ($(test-path $csvPath)) {$csvPath} else {Read-Host "Folder for CSV exports from Passportal?"}))
if ($null -eq $passportalData.csvData) {
    Set-Printandlog -message "Sorry, we dont have any CSV data in your exports directory needed to migrate passwords..."
} else { write-host "CSV data loaded!"}
$PasswordIDX=0
$passwordsToProcess = @($passportalData.csvData.passwords) + @($passportalData.csvData.vault)

function ConvertTo-PassportalPasswordCompanyMatchName {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    return (normalize-companyName (Get-HTTPDecodedString $Text)).ToLowerInvariant()
}

function Get-PassportalPasswordClientName {
    param([AllowNull()]$Credential)

    if ($null -eq $Credential) { return $null }

    foreach ($propertyName in @('Client Name', 'clientName', 'ClientName', 'Company Name', 'companyName', 'Organization Name', 'organizationName')) {
        $value = Get-PPPropertyValue -Object $Credential -Name $propertyName
        if (Test-PassportalMeaningfulValue $value) { return "$(Get-HTTPDecodedString $value)".Trim() }
    }

    foreach ($bagName in @('client', 'organization', 'company')) {
        $bag = Get-PPPropertyValue -Object $Credential -Name $bagName
        foreach ($propertyName in @('decodedName', 'name', 'clientName')) {
            $value = Get-PPPropertyValue -Object $bag -Name $propertyName
            if (Test-PassportalMeaningfulValue $value) { return "$(Get-HTTPDecodedString $value)".Trim() }
        }
    }

    return $null
}

function Get-PassportalPasswordCompanyNameCandidates {
    param([AllowNull()]$Credential)

    $clientName = Get-PassportalPasswordClientName -Credential $Credential
    if (-not (Test-PassportalMeaningfulValue $clientName)) { return @() }

    $candidates = @("$clientName".Trim())

    if ($clientName -match '\s+-\s+') {
        $candidates += (($clientName -replace '\s+-\s+', ' ').Trim())
        $candidates += (($clientName -split '\s+-\s+', 2)[0]).Trim()
    }

    if ($clientName -match '^(.*?)\s+\(') {
        $candidates += $Matches[1].Trim()
    }

    $seenCandidates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $orderedCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        if (-not (Test-PassportalMeaningfulValue $candidate)) { continue }
        if ($seenCandidates.Add($candidate)) { [void]$orderedCandidates.Add($candidate) }
    }

    return $orderedCandidates.ToArray()
}

function Get-MatchedHuduCompanyForPassportalPassword {
    param(
        [AllowNull()]$Credential,
        [array]$HuduCompanies
    )

    $candidateNames = @(Get-PassportalPasswordCompanyNameCandidates -Credential $Credential)
    if ($candidateNames.Count -lt 1) { return $null }

    foreach ($candidateName in $candidateNames) {
        $candidateMatchName = ConvertTo-PassportalPasswordCompanyMatchName $candidateName
        $matchedFromPreviousCompanyStep = @($MatchedCompanies | Where-Object {
            $ppCompany = $_.PPcompany
            $ppNames = @(
                (Get-PPPropertyValue -Object $ppCompany -Name 'decodedName')
                (Get-PPPropertyValue -Object $ppCompany -Name 'name')
                (Get-PPPropertyValue -Object $ppCompany -Name 'Client Name')
            ) | ForEach-Object { ConvertTo-PassportalPasswordCompanyMatchName $_ } | Where-Object { $_ }

            $ppNames -contains $candidateMatchName
        } | Select-Object -First 1)

        if ($matchedFromPreviousCompanyStep.Count -gt 0) {
            $matchedCompany = $matchedFromPreviousCompanyStep[0].HuduCompany ?? $matchedFromPreviousCompanyStep[0].company ?? $matchedFromPreviousCompanyStep[0]
            $matchedCompany = $matchedCompany.company ?? $matchedCompany
            if ($null -ne $matchedCompany) {
                Write-Host "Matched company using previous Passportal client mapping: $($matchedCompany.name)"
                return $matchedCompany
            }
        }
    }

    foreach ($candidateName in $candidateNames) {
        $matchedCompany = Get-HuduCompanyFromName -CompanyName $candidateName -HuduCompanies $HuduCompanies -deepCompanySearch $true
        $matchedCompany = $matchedCompany.company ?? $matchedCompany
        if ($null -ne $matchedCompany) { return $matchedCompany }
    }

    return $null
}

function Get-PassportalPasswordFolderName {
    param([AllowNull()]$Credential)

    if ($null -eq $Credential) { return $null }

    foreach ($propertyName in @('Folder(Optional)', 'Folder (Optional)', 'Folder', 'Folder Name', 'folder', 'folderName', 'passwordFolder', 'Password Folder')) {
        $value = Get-PPPropertyValue -Object $Credential -Name $propertyName
        if (Test-PassportalMeaningfulValue $value) {
            $folderName = "$(Get-HTTPDecodedString $value)"
            $folderName = ($folderName -replace "\r\n?", "`n").Trim()
            $folderName = ($folderName -replace '\s+', ' ').Trim(' ', '/', '\')
            if (Test-PassportalMeaningfulValue $folderName) { return $folderName }
        }
    }

    return $null
}

function Get-PassportalPasswordFolderKey {
    param([AllowNull()][string]$FolderName)

    if (-not (Test-PassportalMeaningfulValue $FolderName)) { return $null }
    return (($FolderName -replace '\s+', ' ').Trim()).ToLowerInvariant()
}

$script:PassportalPasswordFolderIndexes = @{}
$script:PassportalPasswordFolderIndexLoadFailures = @{}
$PassportalPasswordFolderScope = $PassportalPasswordFolderScope ?? 'Global'

function Get-PassportalPasswordFolderScope {
    $scope = "$PassportalPasswordFolderScope".Trim()
    if ($scope -in @('Global', 'Company', 'None')) { return $scope }

    Set-PrintAndLog -message "Unknown PassportalPasswordFolderScope '$PassportalPasswordFolderScope'; defaulting to Global." -Color DarkYellow
    return 'Global'
}

function Test-HuduPasswordFolderIsGlobal {
    param([AllowNull()]$Folder)

    if ($null -eq $Folder) { return $false }
    $hasCompanyId = (Test-PPProperty -Object $Folder -Name 'company_id') -or (Test-PPProperty -Object $Folder -Name 'companyId')
    $hasCompany = Test-PPProperty -Object $Folder -Name 'company'
    $companyId = (Get-PPPropertyValue -Object $Folder -Name 'company_id') ?? (Get-PPPropertyValue -Object $Folder -Name 'companyId')
    $company = Get-PPPropertyValue -Object $Folder -Name 'company'
    if ($hasCompanyId) { return (-not (Test-PassportalMeaningfulValue $companyId)) }
    if ($hasCompany) { return $null -eq $company }
    return $false
}

function Get-HuduPasswordFolderIndex {
    param(
        [Parameter(Mandatory)][string]$IndexKey,
        [AllowNull()][int]$CompanyId,
        [bool]$Global
    )

    if ($script:PassportalPasswordFolderIndexes.ContainsKey($IndexKey)) {
        return $script:PassportalPasswordFolderIndexes[$IndexKey]
    }

    $index = @{}
    if (Get-Command -Name Get-HuduPasswordFolders -ErrorAction SilentlyContinue) {
        $folders = @()
        try {
            $folders = if ($Global) {
                @(Get-HuduPasswordFolders)
            } else {
                @(Get-HuduPasswordFolders -CompanyId $CompanyId)
            }
        } catch {
            $script:PassportalPasswordFolderIndexLoadFailures[$IndexKey] = $true
            Write-ErrorObjectsToFile -ErrorObject @{
                Error = $_
                During = if ($Global) { "loading global password folders" } else { "loading password folders for company $CompanyId" }
            } -Name "PasswordFolderLoad-$IndexKey"
        }

        foreach ($folderItem in $folders) {
            $folder = $folderItem.password_folder ?? $folderItem
            if ($Global -and -not (Test-HuduPasswordFolderIsGlobal -Folder $folder)) { continue }

            $folderName = $folder.name ?? $folder.Name
            $folderKey = Get-PassportalPasswordFolderKey $folderName
            if ($folderKey -and -not $index.ContainsKey($folderKey)) {
                $index[$folderKey] = $folder
            }
        }
    } else {
        $script:PassportalPasswordFolderIndexLoadFailures[$IndexKey] = $true
    }

    $script:PassportalPasswordFolderIndexes[$IndexKey] = $index
    return $index
}

function Get-HuduPasswordFolderIndexForCompany {
    param(
        [Parameter(Mandatory)]$Company
    )

    $companyId = [int]($Company.id ?? $Company.Id)
    if ($companyId -lt 1) { return @{} }
    return Get-HuduPasswordFolderIndex -IndexKey "company:$companyId" -CompanyId $companyId -Global:$false
}

function Get-HuduPasswordFolderForPassportalPassword {
    param(
        [AllowNull()]$Credential,
        [Parameter(Mandatory)]$Company
    )

    $folderName = Get-PassportalPasswordFolderName -Credential $Credential
    if (-not (Test-PassportalMeaningfulValue $folderName)) { return $null }

    $scope = Get-PassportalPasswordFolderScope
    if ($scope -eq 'None') { return $null }

    if (-not (Get-Command -Name Get-HuduPasswordFolders -ErrorAction SilentlyContinue) -or
        -not (Get-Command -Name New-HuduPasswordFolder -ErrorAction SilentlyContinue)) {
        Set-PrintAndLog -message "Passportal password folder '$folderName' found, but Hudu password-folder commands are not available. Creating password without folder." -Color DarkYellow
        return $null
    }

    $companyId = [int]($Company.id ?? $Company.Id)
    $globalScope = $scope -eq 'Global'
    $indexKey = if ($globalScope) { 'global' } else { "company:$companyId" }
    $folderDescription = if ($globalScope) { 'global password folders' } else { "password folders for $($Company.name ?? $companyId)" }
    $folderKey = Get-PassportalPasswordFolderKey $folderName
    $folderIndex = if ($globalScope) {
        Get-HuduPasswordFolderIndex -IndexKey $indexKey -Global:$true
    } else {
        Get-HuduPasswordFolderIndexForCompany -Company $Company
    }
    if ($script:PassportalPasswordFolderIndexLoadFailures.ContainsKey($indexKey)) {
        Set-PrintAndLog -message "Could not verify existing $folderDescription. Creating password without folder '$folderName' to avoid duplicates." -Color DarkYellow
        return $null
    }
    if ($folderIndex.ContainsKey($folderKey)) { return $folderIndex[$folderKey] }

    try {
        Set-PrintAndLog -message "Creating $(if ($globalScope) { 'global ' } else { '' })password folder '$folderName'$(if ($globalScope) { '' } else { " for $($Company.name ?? $companyId)" })." -Color DarkCyan
        $newFolder = if ($globalScope) {
            New-HuduPasswordFolder -Name $folderName
        } else {
            New-HuduPasswordFolder -Name $folderName -CompanyId $companyId
        }
        $newFolder = $newFolder.password_folder ?? $newFolder
        if ($null -ne $newFolder -and ($newFolder.id ?? $newFolder.Id)) {
            $folderIndex[$folderKey] = $newFolder
            return $newFolder
        }
    } catch {
        Write-ErrorObjectsToFile -ErrorObject @{
            Error = $_
            During = "creating $(if ($globalScope) { 'global ' } else { '' })password folder '$folderName'$(if ($globalScope) { '' } else { " for $($Company.name ?? $companyId)" })"
        } -Name "PasswordFolderCreate-$($Company.Name)-$folderName"
    }

    Set-PrintAndLog -message "Could not create $(if ($globalScope) { 'global ' } else { '' })password folder '$folderName'$(if ($globalScope) { '' } else { " for $($Company.name ?? $companyId)" }). Creating password without folder." -Color DarkYellow
    return $null
}

$huducompanies = Get-HuduCompanies
$internalCompany = select-objectfromlist -objects $(get-huducompanies) -message "Please select your internal company in Hudu for passwords that may not be directly associated with a company in Passportal"; $internalCompany = $internalCompany.company ?? $internalCompany;
$AssociatePassowrdsAssets = $AssociatePassowrdsAssets ?? $false
foreach ($newCredential in $passwordsToProcess) {
    $credentialName = $(if (-not [string]::IsNullOrEmpty($newCredential.Description)) {$newCredential.Description} else {"$($newCredential.Credential) - $($newCredential.Username)"})
    $clientName = Get-PassportalPasswordClientName -Credential $newCredential
    $clientName = $clientName ?? "Vault"
    Write-Host "Starting $($credentialName) for $($clientName)"
    
    # Match Company
    $MatchedCompany = $null; 
    $ClientName = Get-PassportalPasswordClientName -Credential $newCredential
    if ([string]::IsNullOrEmpty($ClientName)){
        write-warning "No client name for credential $($credentialName), attempting to match company from credential name and other attributes"
    }
    
    $MatchedCompany = Get-MatchedHuduCompanyForPassportalPassword -Credential $newCredential -HuduCompanies $huducompanies

    if ($null -eq $MatchedCompany) {
        Write-Warning "Could not match '$($ClientName ?? 'Vault')' for credential '$credentialName'; using internal company '$($internalCompany.name)'."
        $MatchedCompany = $internalCompany
    }
    $MatchedCompany = $MatchedCompany.company ?? $MatchedCompany

    Write-Host "Matched Credential $($newCredential) to company $($MatchedCompany.name)"
    
    $matchedAsset = $null
    # Match Asset or Object
    $companyAssets = $CreatedAssets | Where-Object {$_.HuduAsset.Value.company_id -eq $MatchedCompany.id}
    $MatchableAssets = $companyAssets | Where-Object {$(Get-StringVariants $_.DocType) -contains $newCredential.Credential}
    if ($MatchableAssets.count -lt 1) {
        $MatchableAssets = $(if ($companyAssets.count -gt 1) {$companyAssets} else {$CreatedAssets})
    } elseif ($MatchableAssets.count -eq 1){
        $matchedAsset = $MatchableAssets | Select-Object -First 1
    }
    if ($true -eq $AssociatePassowrdsAssets){
        $MatchedAsset = $MatchedAsset ?? $(Select-ObjectFromList -objects $MatchableAssets.HuduAsset -message "Which asset to match for new credential $(Get-JsonString $newCredential)? Select 0/skip to just attribute to company" -allowNull $true -inspectObjects $true)
    }
    $NewPassSplat= @{
        CompanyId               = $MatchedCompany.Id
        Name                    = $credentialName
        Password                = "$($newCredential.Password)"
    }
    $matchedPasswordFolder = Get-HuduPasswordFolderForPassportalPassword -Credential $newCredential -Company $MatchedCompany
    if ($null -ne $matchedPasswordFolder -and ($matchedPasswordFolder.id ?? $matchedPasswordFolder.Id)) {
        $NewPassSplat["PasswordFolderId"] = [int]($matchedPasswordFolder.id ?? $matchedPasswordFolder.Id)
        Write-Host "Matched Credential $($newCredential) to password folder $($matchedPasswordFolder.name)"
    }
    if ($null -ne $matchedAsset){
        Write-Host "Matched Credential $($newCredential) to asset $($matchedAsset.HuduAsset.name)"
        $NewPassSplat["PasswordableId"] = $matchedAsset.HuduAsset.Id
        $NewPassSplat["PasswordableType"] = 'Asset'
    }


    $TOTP = $null; $TOTP = $newcredential.'TOTP Secret' ?? $null;
    if (-not [string]::IsNullOrWhiteSpace($TOTP)) {
        $TOTP = "$TOTP".Trim().ToUpper()
        $isValidBase32 = $TOTP -match '^[A-Z2-7]+$'
        $lengthOK = $TOTP.Length -ge 16 -and $TOTP.Length -le 80

        $TOTP = if ($isValidBase32 -and $lengthOK) { $TOTP } else { $null }

        if (-not ($isValidBase32 -and $lengthOK)) {
            Write-Warning "Invalid OTP secret for $($unmatchedPassword.ITGObject.attributes.name): $($unmatchedPassword.ITGObject.attributes.otp_secret)... valid base32? $isValidBase32 length ok? $lengthOK (min / max is 16 / 80 chars)"
        } else {
            Write-Host "Valid TOTP secret found for $($credentialName)"
        }
        $NewPassSplat.OTPSecret = $TOTP
    } else {write-host "No TOTP secret for $($credentialName)"}

    if (-not [string]::IsNullOrEmpty($newCredential.URL)){
        $NewPassSplat["URL"] = $newCredential.URL
    }
    if (-not [string]::IsNullOrEmpty($newCredential.Username)){
        $NewPassSplat["Username"] = $newCredential.Username
    }
    $Description_or_Notes = ""
    if (-not [string]::IsNullOrEmpty($($newCredential.Description))){
        $Description_or_Notes = $($newCredential.Description)
    }
    if (-not [string]::IsNullOrEmpty($($newCredential.Notes))){
        if (-not [string]::IsNullOrEmpty($Description_or_Notes)){$Description_or_Notes += "`n`n"}
        $Description_or_Notes += $($newCredential.Notes)
    }
    if (-not [string]::IsNullOrEmpty($Description_or_Notes)){
        $NewPassSplat["Description"] = $Description_or_Notes
    }


    try {

        $NewPassword = New-HuduPassword @NewPassSplat
        if ($null -ne $NewPassword){
            $CreatedPasswords+=@{
                HuduPassword        = $NewPassword
                SourcePassword      = $newCredential
                MatchedCompany      = $MatchedCompany
                MatchedAsset        = $MatchedAsset
                MatchedPasswordFolder = $matchedPasswordFolder
            }
        }
    } catch {
        Write-ErrorObjectsToFile -ErrorObject @{
            Error = $_
            During = "creating Password for $($MatchedCompany.name ?? "Not-Matched-Company")"
        } -Name "PasswordCreate-$($MatchedCompany.Name)-$($NewCredential)"        
    }
    $PasswordIDX=$PasswordIDX+1
}

