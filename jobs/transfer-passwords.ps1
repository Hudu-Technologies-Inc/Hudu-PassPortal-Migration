$passportalData.csvData = $passportalData.csvData ?? $(Get-CSVExportData -exportsFolder $(if ($(test-path $csvPath)) {$csvPath} else {Read-Host "Folder for CSV exports from Passportal?"}))
if ($null -eq $passportalData.csvData) {
    Set-Prontandlog -message "Sorry, we dont have any CSV data in your exports directory needed to migrate passwords..."
} else { write-host "CSV data loaded!"}
$PasswordIDX=0
foreach ($password in $passportalData.csvData.passwords) {
    $newCredential   = $passportalData.csvData.passwords[$PasswordIDX]
    $credentialName = $(if (-not [string]::IsNullOrEmpty($newCredential.Description)) {$newCredential.Description} else {"$($newCredential.Credential) - $($newCredential.Username)"})
    Write-Host "Starting $($credentialName) for $($newCredential.'Client Name')"
    
    # Match Companyu
    $MatchedCompany = $($MatchedCompanies | Where-Object {@($_.PPcompany.name, $_.PPcompany.decodedName) -contains $newCredential.'Client Name'} | Select-Object -First 1).HuduCompany
    if (-not $MatchedCompany) {
        $MatchedCompany = Select-ObjectFromList -objects $Hududata.Data.companies -message "Which company to match for new credential $(Get-JsonString $newCredential)"
    }
    Write-Host "Matched Credential $($newCredential) to company $($MatchedCompany.name)"
    
    # Match Asset or Object
    $matchedAsset = $null
    $companyAssets = $CreatedAssets | Where-Object {$_.HuduAsset.Value.company_id -eq $MatchedCompany.id}
    $MatchableAssets = $companyAssets | Where-Object {$(Get-StringVariants $_.DocType) -contains $newCredential.Credential}
    if ($MatchableAssets.count -lt 1) {
        $MatchableAssets = $(if ($companyAssets.count -gt 1) {$companyAssets} else {$CreatedAssets})
    } elseif ($MatchableAssets.count -eq 1){
        $matchedAsset = $MatchableAssets | Select-Object -First 1
    }
    $MatchedAsset = $MatchedAsset ?? $(Select-ObjectFromList -objects $MatchableAssets -message "Which asset to match for new credential $(Get-JsonString $newCredential)? Select 0/skip to just attribute to company" -allowNull $true -inspectObjects $true)

    $NewPassSplat= @{
        CompanyId               = $matchedCompany.Id
        Name                    = $credentialName
        Password                = "$($newCredential.Password)"
    }
    if (-not [string]::IsNullOrEmpty($newCredential.URL)){
        $NewPassSplat["URL"] = $newCredential.URL
    }
    if (-not [string]::IsNullOrEmpty($newCredential.Username)){
        $NewPassSplat["Username"] = $newCredential.Username
    }
    if (-not [string]::IsNullOrEmpty($($newCredential.Description ?? $newCredential.Notes))){
        $NewPassSplat["Description"] = $($newCredential.Description ?? $newCredential.Notes)
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

