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

