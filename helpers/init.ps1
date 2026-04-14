
# Define and set up some paths
$workdir = $workdir ?? $PSScriptRoot ?? $(resolve-path .).path


$logsFolder=$(join-path "$workdir" "logs")
$logFile=$(join-path "$logsFolder" "PassPortalLog")
$downloadsFolder=$(join-path "$workdir" "downloads")
$allSitesfolder=$(join-path "$workdir" "sites")
$tmpfolder=$(join-path "$workdir" "tmp")
$ErroredItemsFolder=$(join-path "$logsFolder" "errored")
$csvPath=$csvPath ?? $(join-path $workdir "exported-csvs")
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
$RunSummary=$RunSummary ?? @{
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
        Duration            = $null
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
    param(
        [string]$HuduBaseURL,
        [string]$HuduAPIKey
    )

    while ([string]::IsNullOrWhiteSpace($HuduBaseURL)) {
        $HuduBaseURL = (Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g. https://myinstance.huducloud.com)').Trim()
        $HuduBaseURL = $HuduBaseURL -replace '[\\/]+$', ''
        $HuduBaseURL = $HuduBaseURL -replace '^(?!https://)', 'https://'
    }

    while ([string]::IsNullOrWhiteSpace($HuduAPIKey) -or $HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API key from $HuduBaseURL/admin/api_keys").Trim()

        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }

    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}

function Set-HuduModuleInitialized {
    param (
            [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
            [bool]$use_hudu_fork = $true,
            [version]$RequiredHuduVersion = [version]"2.39.6",
            $DisallowedVersions = @([version]"2.37.0"),
            [string]$HuduApiRepositoryUrl = $($env:HUDUAPI_REPOSITORY_URL ?? "https://github.com/Hudu-Technologies-Inc/HuduAPI.git"),
            [string]$HuduApiBranch = $($env:HUDUAPI_REPOSITORY_BRANCH ?? "master"),
            [string]$HuduApiZipUrl = $env:HUDUAPI_ZIP_URL,
            [string]$BundledHuduApiZipPath = (
                Join-Path (
                    $(if ($PSScriptRoot) { $PSScriptRoot } else { (Resolve-Path .).Path })
                ) 'HAPI.zip'
            ),
            [string]$HuduBaseURL,
            [string]$HuduAPIKey
        )
    $AllowHuduGalleryFallback = $false

    function Test-HuduApiModuleLayout {
        param([Parameter(Mandatory)][string]$ModulePath)

        if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
            return $false
        }

        $moduleDirectory = Split-Path -Path $ModulePath -Parent
        return (
            (Test-Path -LiteralPath (Join-Path $moduleDirectory "Public") -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $moduleDirectory "Private") -PathType Container)
        )
    }

    function Get-GitHubRepositoryParts {
        param([Parameter(Mandatory)][string]$RepositoryUrl)

        if ($RepositoryUrl -notmatch 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$') {
            return $null
        }

        [PSCustomObject]@{
            Owner = $matches.owner
            Repo  = ($matches.repo -replace '\.git$', '')
        }
    }

    function New-HuduApiStagingRoot {
        $tempRoot = Join-Path $env:TEMP "HuduAPI-Fork-$([guid]::NewGuid().Guid)"
        New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction Stop | Out-Null
        return (Join-Path $tempRoot "HuduAPI")
    }

    function Unblock-HuduApiPath {
        param([Parameter(Mandatory)][string]$Path)

        try {
            if (Test-Path -LiteralPath $Path) {
                Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                    Unblock-File -ErrorAction SilentlyContinue
                Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    function Expand-HuduApiZipToStaging {
        param(
            [Parameter(Mandatory)][string]$ZipPath,
            [Parameter(Mandatory)][string]$StagingRepoRoot
        )

        $stagingParent = Split-Path -Path $StagingRepoRoot -Parent
        $extractRoot = Join-Path $stagingParent "zip-extract"

        Unblock-HuduApiPath -Path $ZipPath
        Expand-Archive -Path $ZipPath -DestinationPath $extractRoot -Force -ErrorAction Stop
        Unblock-HuduApiPath -Path $extractRoot

        $candidateRoots = @((Get-Item -LiteralPath $extractRoot -ErrorAction Stop))
        $candidateRoots += @(Get-ChildItem -LiteralPath $extractRoot -Directory -Recurse -ErrorAction Stop)
        $extracted = $candidateRoots |
            Where-Object { Test-HuduApiModuleLayout -ModulePath (Join-Path $_.FullName "HuduAPI\HuduAPI.psm1") } |
            Select-Object -First 1

        if (-not $extracted) {
            throw "Archive did not contain a complete HuduAPI module layout."
        }

        Move-Item -LiteralPath $extracted.FullName -Destination $StagingRepoRoot -Force -ErrorAction Stop
    }

    function Install-HuduApiForkSamuraiStyle {
        param(
            [Parameter(Mandatory)][string]$RepositoryUrl,
            [Parameter(Mandatory)][string]$Branch,
            [Parameter(Mandatory)][string]$StagingRepoRoot
        )

        $git = Get-Command git -ErrorAction SilentlyContinue
        if (-not $git) {
            throw "git was not found on this machine."
        }

        $oldGitPrompt = $env:GIT_TERMINAL_PROMPT
        $oldGitSshCommand = $env:GIT_SSH_COMMAND
        try {
            $env:GIT_TERMINAL_PROMPT = "0"
            $env:GIT_SSH_COMMAND = "ssh -o BatchMode=yes"
            & $git.Source clone --depth 1 --branch $Branch $RepositoryUrl $StagingRepoRoot 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "git clone exited with code $LASTEXITCODE."
            }
        } finally {
            $env:GIT_TERMINAL_PROMPT = $oldGitPrompt
            $env:GIT_SSH_COMMAND = $oldGitSshCommand
        }
    }

    function Install-HuduApiForkAshigaruStyle {
        param(
            [Parameter(Mandatory)][string]$RepositoryUrl,
            [Parameter(Mandatory)][string]$Branch,
            [Parameter(Mandatory)][string]$StagingRepoRoot,
            [string]$ZipUrl
        )

        if ([string]::IsNullOrWhiteSpace($ZipUrl)) {
            $repoParts = Get-GitHubRepositoryParts -RepositoryUrl $RepositoryUrl
            if (-not $repoParts) {
                throw "Ashigaru-Warrior-Style install only supports github.com repository URLs unless HuduApiZipUrl is set."
            }
            $ZipUrl = "https://codeload.github.com/$($repoParts.Owner)/$($repoParts.Repo)/zip/refs/heads/$Branch"
        }

        $stagingParent = Split-Path -Path $StagingRepoRoot -Parent
        $zip = Join-Path $stagingParent "HuduAPI.zip"
        $headers = @{ "User-Agent" = "ITGlue-Hudu-Migration" }

        Invoke-WebRequest -Uri $ZipUrl -Headers $headers -OutFile $zip -ErrorAction Stop | Out-Null
        Expand-HuduApiZipToStaging -ZipPath $zip -StagingRepoRoot $StagingRepoRoot
    }

    function Install-HuduApiForkBundledZipStyle {
        param(
            [Parameter(Mandatory)][string]$ZipPath,
            [Parameter(Mandatory)][string]$StagingRepoRoot
        )

        if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
            throw "Bundled HuduAPI zip was not found at $ZipPath."
        }

        Expand-HuduApiZipToStaging -ZipPath $ZipPath -StagingRepoRoot $StagingRepoRoot
    }

    function Install-HuduApiFork {
        param(
            [Parameter(Mandatory)][string]$ModulePath,
            [Parameter(Mandatory)][string]$RepositoryUrl,
            [Parameter(Mandatory)][string]$Branch,
            [string]$ZipUrl,
            [string]$BundledZipPath
        )

        $targetRepoRoot = Split-Path -Path (Split-Path -Path $ModulePath -Parent) -Parent
        $targetParent = Split-Path -Path $targetRepoRoot -Parent
        $stagingRepoRoot = $null
        $successfulMethod = $null

        $installMethods = @(
            @{
                Name = "Ashigaru-Warrior-Style"
                Script = {
                    param($repoUrl, $branchName, $stagingRoot, $directZipUrl)
                    Install-HuduApiForkAshigaruStyle -RepositoryUrl $repoUrl -Branch $branchName -StagingRepoRoot $stagingRoot -ZipUrl $directZipUrl
                }
            },
            @{
                Name = "Samurai-Style"
                Script = {
                    param($repoUrl, $branchName, $stagingRoot, $directZipUrl)
                    Install-HuduApiForkSamuraiStyle -RepositoryUrl $repoUrl -Branch $branchName -StagingRepoRoot $stagingRoot
                }
            },
            @{
                Name = "Bundled-Zip"
                Script = {
                    param($repoUrl, $branchName, $stagingRoot, $directZipUrl, $localZipPath)
                    Install-HuduApiForkBundledZipStyle -ZipPath $localZipPath -StagingRepoRoot $stagingRoot
                }
            }
        )

        foreach ($method in $installMethods) {
            $stagingRepoRoot = New-HuduApiStagingRoot
            $stagingContainer = Split-Path -Path $stagingRepoRoot -Parent

            try {
                $methodSource = if ($method.Name -eq "Bundled-Zip") { $BundledZipPath } else { "$RepositoryUrl ($Branch)" }
                Write-Host "Trying HuduAPI fork install via $($method.Name) from $methodSource." -ForegroundColor Cyan
                & $method.Script $RepositoryUrl $Branch $stagingRepoRoot $ZipUrl $BundledZipPath

                $stagedModulePath = Join-Path $stagingRepoRoot "HuduAPI\HuduAPI.psm1"
                if (-not (Test-HuduApiModuleLayout -ModulePath $stagedModulePath)) {
                    throw "Downloaded fork did not include a complete HuduAPI module layout."
                }

                $successfulMethod = $method.Name
                break
            } catch {
                Write-Warning "$($method.Name) HuduAPI fork install failed: $($_.Exception.Message)"
                if (Test-Path -LiteralPath $stagingContainer) {
                    Remove-Item -LiteralPath $stagingContainer -Recurse -Force -ErrorAction SilentlyContinue
                }
                $stagingRepoRoot = $null
            }
        }

        if (-not $successfulMethod) {
            throw "Unable to install HuduAPI fork from $RepositoryUrl ($Branch)."
        }

        New-Item -ItemType Directory -Path $targetParent -Force -ErrorAction Stop | Out-Null
        if (Test-Path -LiteralPath $targetRepoRoot) {
            $backupPath = "$targetRepoRoot.backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
            Move-Item -LiteralPath $targetRepoRoot -Destination $backupPath -Force -ErrorAction Stop
            Write-Warning "Existing incomplete HuduAPI path was moved to $backupPath."
        }

        $stagingGitPath = Join-Path $stagingRepoRoot ".git"
        if (Test-Path -LiteralPath $stagingGitPath) {
            Remove-Item -LiteralPath $stagingGitPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Unblock-HuduApiPath -Path $stagingRepoRoot

        $stagingContainer = Split-Path -Path $stagingRepoRoot -Parent
        New-Item -ItemType Directory -Path $targetRepoRoot -Force -ErrorAction Stop | Out-Null
        Get-ChildItem -LiteralPath $stagingRepoRoot -Force -ErrorAction Stop |
            Copy-Item -Destination $targetRepoRoot -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $stagingContainer) {
            Remove-Item -LiteralPath $stagingContainer -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Installed HuduAPI fork via $successfulMethod to $targetRepoRoot." -ForegroundColor Green
    }

    try {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop
        Write-Host "Process execution policy set to Bypass for this PowerShell session." -ForegroundColor DarkGray
    } catch {
        Write-Warning "Could not set process execution policy to Bypass: $($_.Exception.Message)"
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Warning "Could not force TLS 1.2 for this PowerShell session: $($_.Exception.Message)"
    }
    $ProgressPreference = 'SilentlyContinue'

    if ([string]::IsNullOrWhiteSpace($BundledHuduApiZipPath) -and -not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $BundledHuduApiZipPath = Join-Path $repoRoot "ExternalModules\HuduAPI.zip"
    }

    if ($true -eq $use_hudu_fork) {
        if (-not (Test-HuduApiModuleLayout -ModulePath $HAPImodulePath)) {
            Write-Host "Using latest $HuduApiBranch branch of HuduAPI fork." -ForegroundColor Cyan
            Install-HuduApiFork -ModulePath $HAPImodulePath -RepositoryUrl $HuduApiRepositoryUrl -Branch $HuduApiBranch -ZipUrl $HuduApiZipUrl -BundledZipPath $BundledHuduApiZipPath
        }
    } else {
        Write-Host "HuduAPI fork loading is disabled. PSGallery will only be used if AllowHuduGalleryFallback is true."
    }

    Remove-Module HuduAPI -Force -ErrorAction SilentlyContinue
    if (Test-HuduApiModuleLayout -ModulePath $HAPImodulePath) {
        $huduApiManifestPath = [System.IO.Path]::ChangeExtension($HAPImodulePath, ".psd1")
        $huduApiImportPath = if (Test-Path -LiteralPath $huduApiManifestPath -PathType Leaf) { $huduApiManifestPath } else { $HAPImodulePath }
        Import-Module $huduApiImportPath -Force -ErrorAction Stop
        Write-Host "Module imported from $huduApiImportPath"
    } elseif (-not $AllowHuduGalleryFallback) {
        write-host "Sorry, it seems we weren't able to load the Hudu-Fork of HuduAPI module, which is required for the latest features that this fork provides."
        write-host "You can manually download this project https://github.com/Hudu-Technologies-Inc/HuduAPI and extract it to Documents/GitHub folder."
        throw "HuduAPI fork was requested, but no complete fork module was available at $HAPImodulePath. PSGallery fallback is disabled."
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'3.1.1') {
        Import-Module HuduAPI -ErrorAction Stop
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 3.1.1 -Scope CurrentUser -Force -ErrorAction Stop
        Import-Module HuduAPI -ErrorAction Stop
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }

    #Login to Hudu
    Set-HuduInstance  -HuduBaseURL $HuduBaseURL -HuduAPIKey $HuduAPIKey

    # Check we have the correct version
    $CurrentVersion = [version]($(Get-HuduAppInfo).version)

    return $CurrentVersion
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