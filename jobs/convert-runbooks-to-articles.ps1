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
    $KeyName     = Get-SafeFileBase -Name $a.BaseName
    $extractPath = Join-Path $tmpfolder $KeyName

    if (Test-Path $extractPath) {
    Get-ChildItem -Path $extractPath -File -Recurse -Force | Remove-Item -Force -ErrorAction SilentlyContinue
    } else {
    New-Item -ItemType Directory -Path $extractPath | Out-Null
    }

    try {
        $HTMLoutput = Convert-PdfToSlimHtml -InputPdfPath $a.FullName -OutputDir $extractPath -PdfToHtmlPath $PDFToHTML
        $convertedDocs[$keyName]=@{
            HTMLpath = $(resolve-path $HTMLoutput)
            ExtractedImages=$($(Get-ChildItem -Path (Join-Path $extractPath '*') -Recurse -File -Include `
                *.png, *.jpg, *.jpeg, *.gif, *.bmp, *.tif, *.tiff, *.webp, *.heic, *.heif, *.svg, *.ico, *.avif, *.psd `
                | Select-Object -ExpandProperty FullName) ?? @())
            ExtractPath = $extractPath
            FoundLinks = @()
            SplitDocs = @()
            HuduCompany = $null
            HuduImages = @()
            CompanyName = ""
        }
    } catch {
        Write-Error "Error during slim convert- $_"
    }
}

write-host "Successfully converted $($convertedDocs.count) runbook docs. Now to specially parse them into individual docs."

$huduCompanies = Get-HuduCompanies
$allHududocuments = Get-HuduArticles

foreach ($key in $convertedDocs.Keys) {
  $doc = $convertedDocs[$key]
  $split = Split-HtmlIntoArticles -Path $doc.HtmlPath -AsObjects
  $matchedCompany = $null  
    $matchedCompany = $huduCompanies | where-object {
        ($_.name -eq $company) -or
        [bool]$(Test-Equiv -A $_.name -B "*$($company)*") -or
        [bool]$(Test-Equiv -A $_.nickname -B "*$($company)*")} | Select-Object -First 1

    $matchedCompany = $matchedCompany ?? (Get-HuduCompanies -Name $company | Select-Object -First 1)

  if ($matchedCompany){
    $doc["HuduCompany"]=$matchedCompany
    Write-Host "$($key) attributed to company $($matchedCompany.name) in Hudu."
  } else {
    Write-Host "Could not match $key to company. skipping"
    continue
  }

  $doc['CompanyName'] = ($split | Select-Object -ExpandProperty Company -First 1)
  $doc['SplitDocs']   = @()
  $HuduImages = @()
    $existingRelatedImages = Get-Huduuploads | where-object {$_.uploadable_type -eq "Company" -and $_.uploadable_id -eq $matchedCompany.Id}
    foreach ($ImageFile in $doc.ExtractedImages){
        $existingUpload = $null
        $ImagefileName = "$([IO.Path]::GetFileName($ImageFile))".trim
        $existingupload = $existingRelatedImages | where-object {$_.name -eq $ImagefileName} | select-object -first 1
        $existingupload = $existingupload ?? ($existingRelatedImages | where-object {$(Test-Equiv -A $_.name -B $ImagefileName)} | select-object -first 1)
        $existingupload = $existingupload.upload ?? $existingupload
        if ($existingUpload) {
            write-host "ExistingUpload Match $existingupload"
        } else {
            Write-Host "No existing upload, uploading file @ $($ImageFile)"
            $uploaded = New-HuduUpload -FilePath $ImageFile `
                -Uploadable_Id $matchedCompany.Id `
                -Uploadable_Type 'Company'
            $uploaded = $uploaded.upload ?? $uploaded
        }
        $usingImage = $existingUpload ?? $uploaded ?? $null
        if ($usingImage){
            write-host "set to use $($usingImage) for $ImageFile"
        }
        $HuduImages+=@{
            OriginalFilename = $ImageFile
            UsingImage = $usingImage
        }
    }
    $doc['HuduImages'] = $HuduImages


  foreach ($sd in $split) {
    $matchedDocument = $null
    $newDocument = $null
    $uploaded = $null
    $matchedDocument = $allHududocuments | Where-Object {
        $_.company_id -eq $matchedCompany.id -and
            $(Test-Equiv -A $_.name -B $sd.Title)} | Select-Object -first 1
    $matchedDocument = $matchedDocument ?? $($(Get-HuduArticles -CompanyId $matchedCompany.id -name $sd.Title) | Select-Object -first 1)
    if (-not $matchedDocument){
        $newDocument = New-HuduArticle -name "$($sd.Title)" -Content "[transfer in-progress]" -CompanyId $matchedCompany.id
        $newDocument = $newDocument.article ?? $newDocument
    }
    if ($newDocument){Write-Host "Created article stub $($newDocument.id)"}
    elseif ($matchedDocument){Write-Host "Matched exist article $($matchedDocument.id)"}
    $articleUsed = $matchedDocument ?? $newDocument ?? $null
    if ($null -eq $articleUsed -or -not $articleUsed.id -or $articleUsed.id -lt 1) {Write-Error "could not match or create article $($sd.Title) for company $key"; continue;}
    Write-Host "Checking for or creating existing image embeds"


    $doc['SplitDocs'] += [pscustomobject]@{
      Title   = $sd.Title
      Article = $sd.Html
      HuduArticle = $articleUsed
    }
  }
}

Write-Host "All Articles created or stubbed; time to rewrite image sources and anchors"

$ImageResolver = {
  param([string]$src, [hashtable]$ctx)
  if ([string]::IsNullOrWhiteSpace($src)) { return $null }
  if ($src -match '^(?i)(https?:|data:)') { return $src }

  $leaf = Split-Path -Leaf $src
  if ($ctx.ImageMap.ContainsKey($leaf)) { return $ctx.ImageMap[$leaf] }

  # Sometimes exports reference "file:///C:/.../foo.png" or "./img/foo.png"
  $try = $leaf
  if ($ctx.ImageMap.ContainsKey($try)) { return $ctx.ImageMap[$try] }

  return $null
}

$LinkResolver = {
  param([string]$href, [hashtable]$ctx)
  if ([string]::IsNullOrWhiteSpace($href)) { return $null }
  if ($href -match '^(?i)https?:') { return $href }    # already absolute; leave
  if ($href.StartsWith('#')) { return $null }          # in-doc anchors (optional)

  $leaf     = Split-Path -Leaf $href
  $leafNoEx = [IO.Path]::GetFileNameWithoutExtension($leaf)
  $norm     = Get-NormalizedTitle $leafNoEx
  $slug     = Get-TitleSlug $leafNoEx

  foreach ($k in @($leafNoEx,$norm,$slug)) {
    if ($k -and $ctx.ArticleMap.ContainsKey($k)) { return $ctx.ArticleMap[$k] }
  }
  return $null
}

foreach ($key in $convertedDocs.Keys) {
  $doc = $convertedDocs[$key]

  $docImageMap   = New-DocImageMap -HuduImages $doc.SplitDocs.HuduImages | ForEach-Object { $_ }
  $docArticleMap = New-DocArticleMap -SplitDocs $doc.SplitDocs -HuduBaseUrl $HuduBaseUrl

  for ($i = 0; $i -lt $doc.SplitDocs.Count; $i++) {
    Write-Host "Replacing links for article $($i) of $($doc.SplitDocs.Count) for $($doc.CompanyName)"

    $sd  = $doc.SplitDocs[$i]
    $ctx = @{
      ImageMap   = $docImageMap
      ArticleMap = $docArticleMap
    }

    $r = Rewrite-DocLinks -Html $sd.Article -ImageResolver $ImageResolver -LinkResolver $LinkResolver -Context $ctx

    # Save rewritten HTML back
    $doc.SplitDocs[$i] = [pscustomobject]@{
      Title       = $sd.Title
      Article     = $r.Html
      HuduArticle = $sd.HuduArticle
      HuduImages  = $sd.HuduImages
      # Optional for logging:
      Rewrites    = $r.Rewrites
      Unresolved  = $r.Unresolved
    }
  }
}
