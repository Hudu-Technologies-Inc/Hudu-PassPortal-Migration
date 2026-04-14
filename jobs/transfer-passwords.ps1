$passportalData.csvData = $passportalData.csvData ?? $(Get-CSVExportData -exportsFolder $(if ($(test-path $csvPath)) {$csvPath} else {Read-Host "Folder for CSV exports from Passportal?"}))
if ($null -eq $passportalData.csvData) {
    Set-Prontandlog -message "Sorry, we dont have any CSV data in your exports directory needed to migrate passwords..."
} else { write-host "CSV data loaded!"}
$PasswordIDX=0
$passwordsToProcess = @($passportalData.csvData.passwords) + @($passportalData.csvData.vault)

$internalCompany = select-objectfromlist -objects $(get-huducompanies) -message "Please select your internal company in Hudu for passwords that may not be directly associated with a company in Passportal"; $internalCompany = $internalCompany.company ?? $internalCompany;

foreach ($newCredential in $passwordsToProcess) {
    $credentialName = $(if (-not [string]::IsNullOrEmpty($newCredential.Description)) {$newCredential.Description} else {"$($newCredential.Credential) - $($newCredential.Username)"})
    $clientName = $newCredential.'Client Name' ?? "Vault"
    Write-Host "Starting $($credentialName) for $($clientName)"
    
    # Match Company
    $MatchedCompany = $null; $MatchedCompany = $($MatchedCompanies | Where-Object {@($_.PPcompany.name, $_.PPcompany.decodedName) -contains $clientName} | Select-Object -First 1).HuduCompany
    $MatchedCompany = $MatchedCompany ?? $internalCompany
    $MatchedCompany = $MatchedCompany.company ?? $MatchedCompany

    Write-Host "Matched Credential $($newCredential) to company $($MatchedCompany.name)"
    
    $matchedAsset = $null
    if ($true -eq $AssociatePassowrdsAssets){
        # Match Asset or Object
        $companyAssets = $CreatedAssets | Where-Object {$_.HuduAsset.Value.company_id -eq $MatchedCompany.id}
        $MatchableAssets = $companyAssets | Where-Object {$(Get-StringVariants $_.DocType) -contains $newCredential.Credential}
        if ($MatchableAssets.count -lt 1) {
            $MatchableAssets = $(if ($companyAssets.count -gt 1) {$companyAssets} else {$CreatedAssets})
        } elseif ($MatchableAssets.count -eq 1){
            $matchedAsset = $MatchableAssets | Select-Object -First 1
        }
        $MatchedAsset = $MatchedAsset ?? $(Select-ObjectFromList -objects $MatchableAssets.HuduAsset -message "Which asset to match for new credential $(Get-JsonString $newCredential)? Select 0/skip to just attribute to company" -allowNull $true -inspectObjects $true)
    }

    $NewPassSplat= @{
        CompanyId               = $matchedCompany.Id
        Name                    = $credentialName
        Password                = "$($newCredential.Password)"
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

    if ($null -ne $MatchedAsset){
        $NewPassSplat["PasswordableId"] = $MatchedAsset.Id
        $NewPassSplat["PasswordableType"] = 'Asset'
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

