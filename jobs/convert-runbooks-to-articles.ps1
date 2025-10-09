# Poppler Setup
$includeHiddenText=$true
$includeComplexLayouts=$true

# for testing
# $SingleDocumentTest = $false

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
    Write-host "Not set to convert passportal";x Exit 0;
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
    if ($true -eq $SingleDocumentTest){break}
}

write-host "Successfully converted $($convertedDocs.count) runbook docs. Now to specially parse them into individual docs."

$huduCompanies = Get-HuduCompanies
$allHududocuments = Get-HuduArticles

foreach ($key in $convertedDocs.Keys) {
  $doc = $convertedDocs[$key]
  $companyHint = [IO.Path]::GetFileName($doc.extractPath.TrimEnd('\'))
  $split = Split-FullHtmlIntoArticles -Path $doc.HtmlPath -AsObjects -CompanyHint $companyHint
  $doc['CompanyName'] = ($split | Select-Object -ExpandProperty Company -First 1)

  $matchedCompany = $null  
    $matchedCompany = $huduCompanies | where-object {$_.name -eq $doc['CompanyName']}
    $matchedCompany = $matchedCompany ?? $($huduCompanies | where-object {
        [bool]$(Test-Equiv -A $_.name -B "$($doc['CompanyName'])") -or
        [bool]$(Test-Equiv -A $_.nickname -B "$($doc['CompanyName'])")} | Select-Object -First 1)

    $matchedCompany = $matchedCompany ?? (Get-HuduCompanies -Name $($doc['CompanyName']) | Select-Object -First 1)
  if ($matchedCompany){
    $doc["HuduCompany"]=$matchedCompany
    Write-Host "$($key) attributed to company $($matchedCompany.name) in Hudu."
  } else {
    Write-Host "Could not match $key to company. creating"
    $createdcompany = New-HuduCompany -Name "$($companyHint ?? $doc["CompanyName"])".Trim()
    $matchedcompany = Get-HuduCompanies -id $createdcompany.id 
    $matchedcompany = $matchedCompany ?? $(Get-HuduCompanies -name "$($companyHint ?? $doc["CompanyName"])".Trim() | select-object -first 1)
    
    $matchedCompany = $matchedCompany.company ?? $matchedCompany
    write-host "created company $($matchedCompany)"
    $doc["HuduCompany"]=$matchedCompany
  }

  $doc['SplitDocs']   = @()
$HuduImages = @()
$existingRelatedImages = Get-HuduUploads | Where-Object { $_.uploadable_type -eq 'Company' -and $_.uploadable_id -eq $matchedCompany.Id }

foreach ($ImageFile in $doc.ExtractedImages) {
  $existingUpload = $null
  $uploaded = $null                # reset per file

  $ImagefileName = ([IO.Path]::GetFileName($ImageFile)).Trim()

  $existingUpload = $existingRelatedImages |
    Where-Object { $_.name -eq $ImagefileName } | Select-Object -First 1
  if (-not $existingUpload) {
    $existingUpload = $existingRelatedImages |
      Where-Object { Test-Equiv -A $_.name -B $ImagefileName } | Select-Object -First 1
  }
  $existingUpload = $existingUpload.upload ?? $existingUpload

  if ($existingUpload) {
    Write-Host "ExistingUpload Match $($existingUpload.name)"
  } else {
    Write-Host "No existing upload, uploading file @ $ImageFile"
    $uploaded = New-HuduUpload -FilePath $ImageFile -Uploadable_Id $matchedCompany.Id -Uploadable_Type 'Company'
    $uploaded = $uploaded.upload ?? $uploaded
  }

  $usingImage = $existingUpload ?? $uploaded
  $HuduImages += @{
    OriginalFilename = $ImageFile
    UsingImage       = $usingImage
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
    Write-Host "Article and Uploads are complete"


    $doc['SplitDocs'] += [pscustomobject]@{
      Title   = $sd.Title
      Article = $sd.Html
      HuduArticle = $articleUsed
    }
  }
}

Write-Host "All Articles created or stubbed; time to rewrite image sources and anchors"

function New-DocArticleMap {
  param([Parameter(Mandatory)][object[]]$SplitDocs, [string]$HuduBaseUrl)

  $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($sd in $SplitDocs) {
    # use each split doc’s HuduArticle
    $url = $sd.HuduArticle.article.url ?? $sd.HuduArticle.url
    if (-not $url) { continue }

    $t    = [string]$sd.Title
    $norm = Get-NormalizedTitle $t
    $slug = Get-TitleSlug $t

    $keys = @(
      $t, $norm, $slug,
      "$t.html","$t.htm","$slug.html","$slug.htm",
      ($t -replace '\s+','_') + '.html',
      ($t -replace '\s+','_') + '.htm'
    ) | Where-Object { $_ }

    foreach ($k in $keys) { if (-not $map.ContainsKey($k)) { $map[$k] = $url } }
  }
  $map
}

$LinkResolver = {
  param([string]$href, [hashtable]$ctx)
  if ([string]::IsNullOrWhiteSpace($href)) { return $null }
  if ($href -match '^(?i)https?:') { return $href }
  if ($href.StartsWith('#')) { return $null }

  $raw  = $href.Split('#')[0].Split('?')[0]
  try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}
  $leaf     = Split-Path -Leaf ([System.Web.HttpUtility]::UrlDecode($raw))
  $leafNoEx = [IO.Path]::GetFileNameWithoutExtension($leaf)
  $norm     = Get-NormalizedTitle $leafNoEx
  $slug     = Get-TitleSlug $leafNoEx

  foreach ($k in @($leaf, $leafNoEx, $norm, $slug, "$leafNoEx.html", "$leafNoEx.htm", "$slug.html", "$slug.htm")) {
    if ($k -and $ctx.ArticleMap.ContainsKey($k)) { return $ctx.ArticleMap[$k] }
  }
  return $null
}
# Requires: $ctx.ImageMap is a case-insensitive dictionary keyed by leaf names (foo.png, foo)
try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}

$ImageResolver = {
  param([string]$src, [hashtable]$ctx)
  if ([string]::IsNullOrWhiteSpace($src)) { return $null }

  # already absolute web/data? keep it
  if ($src -match '^(?i)(https?:|data:)') { return $src }

  # 1) strip fragment/query, 2) URL-decode (%20 -> space), 3) normalize file:/// to Windows path
  $raw = ($src -split '#')[0] -split '\?' | Select-Object -First 1
  $dec = [System.Web.HttpUtility]::UrlDecode($raw)

  if ($dec -match '^(?i)file:///') {
    $dec = $dec -replace '^file:///', ''      # drop scheme
    $dec = $dec -replace '/', '\'             # to Windows separators
  }

  # Now $dec might be C:\path\to\foo.png or a relative path ./img/foo.png
  # Always resolve by LEAF name (what you uploaded)
  $leaf = Split-Path -Leaf $dec
  $base = [IO.Path]::GetFileNameWithoutExtension($leaf)

  foreach ($k in @($leaf, $base)) {
    if ($k -and $ctx.ImageMap.ContainsKey($k)) {
      return $ctx.ImageMap[$k]
    }
  }

  # As a last try, if it's a relative path with subfolders, also check the undecoded leaf
  $leaf2 = Split-Path -Leaf $raw
  $base2 = [IO.Path]::GetFileNameWithoutExtension($leaf2)
  foreach ($k in @($leaf2, $base2)) {
    if ($k -and $ctx.ImageMap.ContainsKey($k)) {
      return $ctx.ImageMap[$k]
    }
  }

  return $null
}

foreach ($key in $convertedDocs.Keys) {
  $doc = $convertedDocs[$key]

  # Build maps
# Build maps
$docImageMap   = New-DocImageMap  -HuduImages $doc.HuduImages
$docArticleMap = New-DocArticleMap -SplitDocs $doc.SplitDocs -HuduBaseUrl $HuduBaseUrl
  for ($i = 0; $i -lt $doc.SplitDocs.Count; $i++) {
    $sd  = $doc.SplitDocs[$i]
    $ctx = @{ ImageMap = $docImageMap; ArticleMap = $docArticleMap }

    $r = Rewrite-DocLinks -Html $sd.Article -ImageResolver $ImageResolver -LinkResolver $LinkResolver -Context $ctx
$r.Unresolved | Select-Object -First 5 | Format-Table -AutoSize

"{0}: HuduImages={1}  SplitDocs={2}" -f $key, ($doc.HuduImages.Count), ($doc.SplitDocs.Count) | Write-Host
"{0}: ImageMap keys={1}  ArticleMap keys={2}" -f $key, ($docImageMap.Count), ($docArticleMap.Count) | Write-Host
    Set-HuduArticle -Id $sd.HuduArticle.Id -CompanyId $sd.HuduArticle.company_id -Content $r.Html
  }
}
