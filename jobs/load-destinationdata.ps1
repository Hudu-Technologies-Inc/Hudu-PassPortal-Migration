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