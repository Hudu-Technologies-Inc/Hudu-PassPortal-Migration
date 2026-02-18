$convertedDocs = $convertedDocs ?? @{}

$RunSummary.SetupInfo.FinishedAt = $(get-date)
$RunSummary.SetupInfo.Duration = $RunSummary.SetupInfo.FinishedAt - $RunSummary.SetupInfo.StartedAt
$ResultOverview=@"
Hudu Instance - $(Get-HuduBaseURL)
Passportal Instance - $($passportalData.BaseURL)
"@

$DurationInfo = "Migration Completed $($RunSummary.CompletedStates.count) Major Tasks with $($(Get-ChildItem -path $(Join-Path $workdir "logs\errored\")).count) Errors in $($RunSummary.SetupInfo.Duration.Hours) Hours, $($RunSummary.SetupInfo.Duration.Minutes) Minutes, and $($RunSummary.SetupInfo.Duration.Seconds) Seconds"

$CompaniesResults=@"
$($CreatedCompanies.Count) New Companies created in Hudu from $($passportalData.clients.Count) Clients found in Passportal.
Your Hudu instance now has a total of $($(Get-HuduCompanies).Count) companies total
"@

$LayoutsResults=@"
$($CreatedLayouts.Count) New Layouts created in Hudu from $($passportalData.docTypes.Count) possible Doctypes in Passportal.
Your Hudu instance now has a total of $($(Get-HuduAssetLayouts).Count) active layouts total
"@

$assetResults=@"
Created $($CreatedAssets.Count) Assets in Hudu from $foundDocs Docs Found in Passportal
Your Hudu instance now has a total of $($(Get-HuduAssets).Count) assets
"@

$passwordCsvCount = [int]$(if ($passportalData.csvData.passwords) { $passportalData.csvData.passwords.count } else { 0 })
$vaultCsvCount = [int]$(if ($passportalData.csvData.vault) { $passportalData.csvData.vault.count } else { 0 })
$totalCsvPasswordCount = $passwordCsvCount + $vaultCsvCount

$Passwordsresults=@"
$($CreatedPasswords.count) were created in Hudu from $totalCsvPasswordCount Passwords were found via CSV
Your hudu instance now has a total of $($(Get-HuduPasswords).count) passwords available
"@

if (-not $PassportalDocsConvert -or $false -eq $PassportalDocsConvert){
    $RunbookResults = "Not configured to - or configured not to process Runbook PDFs into individual articles. you can always run this after-the-fact, however."
} else {
    $imagesFromRunbooks = $imagesFromRunbooks ?? 0
    $splitArticlesFromRunbooks = $splitArticlesFromRunbooks ?? 0
    $RBtotals = 
    if ($convertedDocs){
    $convertedDocs.GetEnumerator() | Select Name,
       @{n='Articles';e={ ($_.Value.SplitDocs | Measure-Object).Count }}        
    } else {0}

    $RunbookResults=@"
    $($splitArticlesFromRunbooks) were created in Hudu from $($($convertedDocs.GetEnumerator()).count) Original Docs.
    $($imagesFromRunbooks) images were extracted and relinked to articles.
    Article Totals: $RBtotals
"@
}


$SummaryIDX=0
foreach ($summaryItem in @($ResultOverview, $DurationInfo, $CompaniesResults, $LayoutsResults, $assetResults, $Passwordsresults, $RunbookResults)){
    $SummaryIDX = $SummaryIDX+1
    Set-PrintAndLog -message "$summaryItem" -Color $(if ($SummaryIDX % 2 -eq 0) { 'DarkGreen' } else { 'DarkCyan' })
}
