

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

$Passwordsresults=@"
$($CreatedPasswords.count) were created in Hudu from $($passportalData.csvData.passwords.count) Passwords were found via CSV
Your hudu instance now has a total of $($(Get-HuduPasswords).count) passwords available
"@

$SummaryIDX=0
foreach ($summaryItem in @($ResultOverview, $DurationInfo, $CompaniesResults, $LayoutsResults, $assetResults, $Passwordsresults)){
    $SummaryIDX = $SummaryIDX+1
    Set-PrintAndLog -message "$summaryItem" -Color $(if ($SummaryIDX % 2 -eq 0) { 'DarkGreen' } else { 'DarkCyan' })
}