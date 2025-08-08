
# Define and set up some paths
$logsFolder=$(join-path "$workdir" "logs")
$logFile=$(join-path "$logsFolder" "PassPortalLog")
$downloadsFolder=$(join-path "$workdir" "downloads")
$allSitesfolder=$(join-path "$workdir" "sites")
$tmpfolder=$(join-path "$workdir" "tmp")
$ErroredItemsFolder=$(join-path "$logsFolder" "errored")
$csvPath=$(join-path $workdir "exported-csvs")
Write-Host "Hudu Max Docsize: $HUDU_MAX_DOCSIZE"
$PPBaseURIs = @(
    @{APIBase="us-clover"
    name="United States"},
    @{APIBase="ca-clover"
    name="Canada"},
    @{APIBase="uk-clover"
    name="United Kingdom"},
    @{APIBase="us-clover"
    name="Germany"},
    @{APIBase="au-clover"
    name="Australia"}
)
# foreach ($folder in @($logsFolder, $downloadsFolder, $tmpfolder, $allSitesfolder, $ErroredItemsFolder)) {
#     if (!(Test-Path -Path "$folder")) { Set-PrintAndLog -message  "Making dir... $(New-Item "$folder" -ItemType Directory)" -Color DarkCyan }
#         Set-PrintAndLog -message "Clearing $folder... $(Get-ChildItem -Path "$folder" -File -Recurse -Force | Remove-Item -Force)" -Color DarkCyan
# }

# Set up logging object
$RunSummary=@{
    State="Set-Up"
    CompletedStates=@()
    OutputJsonFiles = @{
        SelectedSites    =   "$(join-path $logsFolder -ChildPath "sites.json")"
        SelectedFiles    =   "$(join-path $logsFolder -ChildPath "files.json")"
        SelectedFolders  =   "$(join-path $logsFolder -ChildPath "folders.json")"
        ConvertedFiles   =   "$(join-path $logsFolder -ChildPath "converted.json")"
        SummaryPath      =   "$(join-path $logsFolder -ChildPath "job-summary.json")"
    }
    SetupInfo=@{
        HuduDestination     = $HuduBaseUrl
        HuduMaxContentLength= 4500
        HuduVersion         = [version]$HuduAppInfo.version
        PowershellVersion   = [version]$PowershellVersion
        project_workdir     = $project_workdir
        StartedAt           = $(get-date)
        FinishedAt          = $null
    }
    JobInfo=@{
        MigrationSource     = [System.Collections.ArrayList]@()
        MigrationDest       = [PSCustomObject]@{}
        AttriutionOptions   = [System.Collections.ArrayList]@(
            @{id=-1; name="Skip (Don't Import)"; decodedName="Skip (Don't Import)"}
            @{id= 0; name="Create New"; decodedName="Create New"}
        )
    }
    Errors                  = [System.Collections.ArrayList]@()
    Warnings                = [System.Collections.ArrayList]@()
}

function Set-IncrementedState {
    param (
        [string]$newstate,
        [bool]$pausable=$false
    )
    $RunSummary.CompletedStates += "$($RunSummary.State) finished At $($($(Get-Date) - $RunSummary.SetupInfo.StartedAt).ToString())"
    $RunSummary.State="$newstate"
    if ($pausable){
        if ($NonInteractive) {Set-PrintAndLog -message  "Noninteractive-Mode enabled. Proceeding to $($RunSummary.State)" -Color Green} else {Set-PrintandLog -message "Next Step: $($RunSummary.State)"; read-host "Prese Enter to proceed."}
    }
}

function Set-HuduInstance {
    $HuduBaseURL = $HuduBaseURL ?? 
        $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $HuduAPIKey = $HuduAPIKey ?? "$(read-host "Please Enter Hudu API Key")"
    while ($HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys").Trim()
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }
    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}

function Get-HuduModule {
    param (
        [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1"
    )
    if (Test-Path $HAPImodulePath) {
        Import-Module $HAPImodulePath -Force
        Write-Host "Module imported from $HAPImodulePath"
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'2.4.4') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser -Force
        Import-Module HuduAPI
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}
function Get-HuduVersionCompatible {
    param (
        [version]$RequiredHuduVersion = [version]"2.38.0",
        $DisallowedVersions = @([version]"2.37.0")
    )

    Write-Host "Required Hudu version: $($RequiredHuduVersion.ToString())" -ForegroundColor Blue
    try {
        $HuduAppInfo = Get-HuduAppInfo
        $CurrentHuduVersion = [version]$HuduAppInfo.version

        if ($DisallowedVersions -contains $CurrentHuduVersion) {
            Write-Host "Hudu version $CurrentHuduVersion is explicitly disallowed." -ForegroundColor Red
            return $false
        }

        if ($CurrentHuduVersion -lt $RequiredHuduVersion) {
            Write-Host "This script requires at least version $RequiredHuduVersion and cannot run with version $CurrentHuduVersion. Please update your version of Hudu." -ForegroundColor Red
            return $false
        }

        Write-Host "Hudu Version $CurrentHuduVersion is compatible" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "Error encountered when checking Hudu version for $(Get-HuduBaseURL): $_" -ForegroundColor Yellow
        return $false
    }
}

function Get-PSVersionCompatible {
    param (
        [version]$RequiredPSversion = [version]"7.5.1"
    )

    $currentPSVersion = (Get-Host).Version
    Write-Host "Required PowerShell version: $RequiredPSversion" -ForegroundColor Blue

    if ($currentPSVersion -lt $RequiredPSversion) {
        Write-Host "PowerShell $RequiredPSversion or higher is required. You have $currentPSVersion." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "PowerShell version $currentPSVersion is compatible." -ForegroundColor Green
    }
}