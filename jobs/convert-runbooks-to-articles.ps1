# Libre Set-Up
$portableLibreOffice=$false
$LibreFullInstall="https://www.nic.funet.fi/pub/mirrors/documentfoundation.org/libreoffice/stable/25.8.0/win/x86_64/LibreOffice_25.8.0_Win_x86-64.msi"
$LibrePortaInstall="https://download.documentfoundation.org/libreoffice/portable/25.2.3/LibreOfficePortable_25.2.3_MultilingualStandard.paf.exe"

# Poppler Setup
$includeHiddenText=$true
$includeComplexLayouts=$true


$workdir = $workdir ?? $(split-path $(resolve-path .))
$PopplerBins=$(join-path $workdir "tools\poppler")
$PDFToHTML=$(join-path $PopplerBins "pdftohtml.exe")

. "$workdir\helpers\html.ps1"
. "$workdir\helpers\fileconvert.ps1"
. "$workdir\helpers\general.ps1"

function Get-SafeFilename {
    param([string]$Name,
        [int]$MaxLength=25
    )

    # If there's a '?', take only the part before it
    $BaseName = $Name -split '\?' | Select-Object -First 1

    # Extract extension (including the dot), if present
    $Extension = [System.IO.Path]::GetExtension($BaseName)
    $NameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BaseName)

    # Sanitize name and extension
    $SafeName = $NameWithoutExt -replace '[\\\/:*?"<>|]', '_'
    $SafeExt = $Extension -replace '[\\\/:*?"<>|]', '_'

    # Truncate base name to 25 chars
    if ($SafeName.Length -gt $MaxLength) {
        $SafeName = $SafeName.Substring(0, $MaxLength)
    }

    return "$SafeName$SafeExt"
}

if (-not $PassportalDocsConvert -or -not $true -eq $PassportalDocsConvert){
    Write-host "Not set to convert passportal"; Exit 0;
}

if (-not $PassportalRubooksPath -or $([string]::IsNullOrEmpty($PassportalRubooksPath))){
    $PassportalRubooksPath = $(read-host "Please enter absolute path to your passportal runbooks")
}

if (test-path $PassportalRubooksPath){
    Write-host "PassportalRunbooksPath at $PassportalRunbooksPath is valid"
} else {
    Write-host "PassportalRunbooksPath at $PassportalRunbooksPath is not valid"
    exit 1
}

$ConvertDocsList = Get-ChildItem -Path $(resolve-path -path $PassportalRubooksPath).path `
            -Filter "*.pdf" `
            -File -Recurse -ErrorAction SilentlyContinue

if (-not $ConvertDocsList -or $ConvertDocsList.count -lt 1){
    Write-host "No eligible PDFS for convert."
    exit 1
} else {
    Write-host "$($ConvertDocsList.count) eligible PDFS for convert."
}

if (-not $(test-path $PDFToHTML)){
    write-host "pdf2html not found at $PDFToHTML"; exit 1;
}

write-host "pdf2html at $PDFToHTML"


$tmpfolder=$(join-path "$($workdir ?? $PSScriptRoot)" "tmp")
foreach ($folder in @($tmpfolder)) {
    if (!(Test-Path -Path "$folder")) { New-Item "$folder" -ItemType Directory }
    Get-ChildItem -Path "$folder" -File -Recurse -Force | Remove-Item -Force
}


$sofficePath=$(Get-LibreMSI -tmpfolder $tmpfolder)
write-host "libreoffice sofficepath $sofficepath"



$convertedDocs = @{}

foreach ($a in $ConvertDocsList){
    $Keyname = Get-Safefilename -Name "$([System.IO.Path]::GetFileNameWithoutExtension($a.Name))".trim()
    $extractPath = "$tmpfolder\$Keyname"
    if (!(Test-Path -Path "$extractPath")) { New-Item "$extractPath" -ItemType Directory }; Get-ChildItem -Path "$extractPath" -File -Recurse -Force | Remove-Item -Force;
    try {
        $HTMLoutput = Convert-PdfToSlimHtml -InputPdfPath $a.FullName -OutputDir $extractPath -PdfToHtmlPath $PDFToHTML
        $convertedDocs[$keyName]=@{
            ConvertedHTML=$HTMLoutput
            ExtractedImages=$($(Get-ChildItem -Path (Join-Path $extractPath '*') -Recurse -File -Include `
                *.png, *.jpg, *.jpeg, *.gif, *.bmp, *.tif, *.tiff, *.webp, *.heic, *.heif, *.svg, *.ico, *.avif, *.psd `
                | Select-Object -ExpandProperty FullName) ?? @())
            ExtractPath = $extractPath
        }
    } catch {
        Write-Error "Error during slim convert- $_"
    }
}