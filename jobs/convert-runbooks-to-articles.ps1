# Poppler Setup
$includeHiddenText=$true
$includeComplexLayouts=$true
$PassportalDocsConvert = $PassportalDocsConvert ?? $false
$runbooksCompanyName = $runbooksCompanyName ?? $null
if ([string]::IsNullOrEmpty($runbooksCompanyName)) { $internalCompanyForRunbooks = $null } else { $internalCompanyForRunbooks = get-huducompanies -name $runbooksCompanyName | select-object -first 1; $internalCompanyForRunbooks = $internalCompanyForRunbooks.company ?? $internalCompanyForRunbooks; }
# for testing
# $SingleDocumentTest = $false
$RBStartTime = Get-Date

if ($null -ne $internalCompanyForRunbooks){
  read-host "using internal company $($internalCompanyForRunbooks.id) $($internalCompanyForRunbooks.name) for all runbooks"
}

$workdir = $workdir ?? $(split-path $(resolve-path .))
foreach ($file in $(Get-ChildItem -Path ".\helpers" -Filter "*.ps1" -File | Sort-Object Name)) {
    Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
    . $file.FullName
}
if (-not (Get-Command -Name get-hudubaseurl -ErrorAction SilentlyContinue)) { Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance; Get-HuduVersionCompatible; }

if (-not $PassportalDocsConvert -or -not $true -eq $PassportalDocsConvert){
    Write-host "Not set to convert passportal"; Exit 0;
}

# validate runbooks path
while ($true) {
    if (-not $PassportalRunbooksPath -or $([string]::IsNullOrEmpty($PassportalRunbooksPath))){
      $PassportalRunbooksPath = $(read-host "Please enter absolute path to your passportal runbooks")
    } elseif (-not $(Test-Path $PassportalRunbooksPath)){
      Write-Host "Runbooks path (currently $PassportalRunbooksPath) doesnt appear to exist."
    } else {
      break
    }
    $PassportalRunbooksPath = read-host "Please enter valid runbooks Export path (containing PDF files)"
}
if (test-path $PassportalRunbooksPath){
    Write-host "PassportalRunbooksPath at $PassportalRunbooksPath is valid"
} else {
    Write-host "PassportalRunbooksPath at $PassportalRunbooksPath is not valid"
    exit 1
}

# # enumerate source runbooks
 $ConvertDocsList = Get-ChildItem -Path $(resolve-path -path $PassportalRunbooksPath).path -Filter "*.pdf" -File -Recurse -ErrorAction SilentlyContinue
 if (-not $ConvertDocsList -or $ConvertDocsList.count -lt 1){
     Write-host "No eligible PDFS for convert."
     exit 1
 } else {
     Write-host "$($ConvertDocsList.count) eligible PDFS for convert."
 }

# find pdftohtml
$PDFToHTML = $PDFToHTML ?? $(get-childitem -path "$workdir/.." -file -filter "pdftohtml.exe" -Recurse | Select-Object -First 1).FullName
if (-not $(test-path $PDFToHTML)){
    write-host "pdf2html not found at $PDFToHTML"; exit 1;
}
write-host "pdf2html at $PDFToHTML"


$tmpfolder=$(join-path "$($workdir ?? $PSScriptRoot)" "tmp")
foreach ($folder in @($tmpfolder)) {
    if (!(Test-Path -Path "$folder")) { New-Item "$folder" -ItemType Directory }
    Get-ChildItem -Path "$folder" -File -Recurse -Force | Remove-Item -Force
}

$convertedDocs = @{}

$RunbookPublicPhotoExtensions = @('.jpg', '.jpeg', '.png', '.gif')
$RunbookAttachmentImageExtensions = @('.svg')

function Test-RunbookPublicPhotoImage {
  param([Parameter(Mandatory)][string]$Path)
  return $RunbookPublicPhotoExtensions -icontains ([IO.Path]::GetExtension($Path))
}

function Test-RunbookAttachmentImage {
  param([Parameter(Mandatory)][string]$Path)
  return $RunbookAttachmentImageExtensions -icontains ([IO.Path]::GetExtension($Path))
}

function Get-HuduStoredFileName {
  param($StoredFile)
  if ($null -eq $StoredFile) { return $null }
  return $StoredFile.file_name ?? $StoredFile.name
}

#check RBStartTime and set it if its not set already
if ($null -eq $RBStartTime) {
    $RBStartTime = Get-Date
    Write-Host "RBStartTime was not set, setting it to $RBStartTime" -ForegroundColor Yellow
}

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
            HuduAttachments = @()
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

  # split docs by Header/Footer and other heuristics, then merge back non-article splits into nearest article
  $presplit = Split-FullHtmlIntoArticles -Path $doc.HtmlPath -AsObjects -CompanyHint $companyHint
  $split = Merge-NonArticleSplits -Articles $presplit -company $companyHint
  
  # Assign / Ensure company
  $doc['CompanyName'] = ($split | Select-Object -ExpandProperty Company -First 1)
  $matchedCompany = $internalCompanyForRunbooks ?? $null  
    $matchedCompany = $matchedCompany ?? $($huduCompanies | where-object {$_.name -eq $doc['CompanyName']})
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
    $createdcompany = $createdcompany.company ?? $createdcompany
    $matchedcompany = Get-HuduCompanies -id $createdcompany.id 
    $matchedcompany = $matchedCompany ?? $(Get-HuduCompanies -name "$($companyHint ?? $doc["CompanyName"])".Trim() | select-object -first 1)
    
    $matchedCompany = $matchedCompany.company ?? $matchedCompany
    write-host "created company $($matchedCompany)"
    $doc["HuduCompany"]=$matchedCompany
  }

  # stub each split article
  $doc['SplitDocs']   = @()
  $articleUsed = $null
  foreach ($sd in $split) {
    $matchedDocument = $null
    $newDocument = $null
    $matchedDocument = $allHududocuments | Where-Object {
        $_.company_id -eq $matchedCompany.id -and
            $(Test-Equiv -A $_.name -B $sd.Title)} | Select-Object -first 1
    $matchedDocument = $matchedDocument ?? $($(Get-HuduArticles -CompanyId $matchedCompany.id -name $sd.Title) | Select-Object -first 1)
    if (-not $matchedDocument){
        $newDocument = New-HuduArticle -name "$($sd.Title)" -Content "[transfer in-progress]" -CompanyId $matchedCompany.id
        $newDocument = $newDocument.article ?? $newDocument
    }
    if ($newDocument){Write-Host "Created article stub $($newDocument.name) $($newDocument.id)"}
    elseif ($matchedDocument){Write-Host "Matched exist article ($($matchedDocument.name)) $($matchedDocument.id)"}
    $articleUsed = $matchedDocument ?? $newDocument ?? $null; $articleUsed = $articleUsed.article ?? $articleUsed;
    if ($null -eq $articleUsed -or -not $articleUsed.id -or $articleUsed.id -lt 1) {Write-Error "could not match or create article $($sd.Title) for company $key"; continue;}
    Write-Host "Article stub is ready"
    $doc['SplitDocs'] += [pscustomobject]@{
      Title   = $sd.Title
      Article = $sd.Html
      HuduArticle = $articleUsed
    }
  }
  $HuduImages = @()
  $HuduAttachments = @()
  if ($null -eq $articleUsed -or -not $articleUsed.id) {
    Write-Warning "Skipping extracted image handling for $key because no article was matched or created."
    $doc['HuduImages'] = $HuduImages
    $doc['HuduAttachments'] = $HuduAttachments
    continue
  }

  $existingRelatedImages = Get-HuduUploads | Where-Object { $_.uploadable_type -ieq 'Article' }
  $existingPublicPhotos = Get-HuduPublicPhotos | Where-Object { $_.record_type -ieq 'Article' }

  # Process extracted files once with the last article for attribution.
  # JPG/JPEG/PNG/GIF become public photos for embeddable article URLs.
  # SVGs remain article attachments and are not used as embedded image sources.
  # Other extracted image formats keep the previous upload-backed behavior.
  foreach ($ImageFile in $doc.ExtractedImages) {
    $existingUpload = $null
    $existingPublicPhoto = $null
    $uploaded = $null
    $publicPhoto = $null

    $ImagefileName = ([IO.Path]::GetFileName($ImageFile)).Trim()

    if (Test-RunbookPublicPhotoImage -Path $ImageFile) {
      $existingPublicPhoto = $existingPublicPhotos | Where-Object {
        (Get-HuduStoredFileName $_) -eq $ImagefileName -and
          ($null -eq $_.record_id -or [int]$_.record_id -eq [int]$articleUsed.Id)
      } | Select-Object -First 1
      $existingPublicPhoto = $existingPublicPhoto.public_photo ?? $existingPublicPhoto

      if ($existingPublicPhoto) {
        Write-Host "ExistingPublicPhoto Match $((Get-HuduStoredFileName $existingPublicPhoto))"
      } else {
        Write-Host "No existing public photo, uploading file @ $ImageFile"
        $publicPhoto = New-HuduPublicPhoto -FilePath $ImageFile -RecordId $articleUsed.Id -RecordType 'Article'
        $publicPhoto = $publicPhoto.public_photo ?? $publicPhoto
      }

      $usingImage = $existingPublicPhoto ?? $publicPhoto
      $HuduImages += @{
        OriginalFilename = $ImageFile
        UsingImage       = $usingImage
      }

      continue
    }

    $existingUpload = $existingRelatedImages | Where-Object { (Get-HuduStoredFileName $_) -eq $ImagefileName } | Select-Object -First 1
    $existingUpload = $existingUpload.upload ?? $existingUpload

    if ($existingUpload) {
      Write-Host "ExistingUpload Match $((Get-HuduStoredFileName $existingUpload))"
    } else {
      Write-Host "No existing upload, uploading attachment @ $ImageFile"
      $uploaded = New-HuduUpload -FilePath $ImageFile -Uploadable_Id $articleUsed.Id -Uploadable_Type 'Article'
      $uploaded = $uploaded.upload ?? $uploaded
    }

    $usingAttachment = $existingUpload ?? $uploaded

    if (Test-RunbookAttachmentImage -Path $ImageFile) {
      $HuduAttachments += @{
        OriginalFilename = $ImageFile
        UsingAttachment  = $usingAttachment
      }
    } else {
      $HuduImages += @{
        OriginalFilename = $ImageFile
        UsingImage       = $usingAttachment
      }
    }
  }
  $doc['HuduImages'] = $HuduImages ?? @()  
  $doc['HuduAttachments'] = $HuduAttachments ?? @()
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
try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}

function Remove-DocVectorImageEmbeds {
  param([string]$Html)
  if ([string]::IsNullOrWhiteSpace($Html)) { return $Html }

  $tagPattern = '(?is)<(?<tag>img|embed|source)\b(?<attrs>[^>]*)>'
  return [regex]::Replace($Html, $tagPattern, {
    param($match)
    $attrs = $match.Groups['attrs'].Value

    foreach ($attr in $Script:RxAttr.Matches($attrs)) {
      $attrName = $attr.Groups['name'].Value.ToLowerInvariant()
      if ($attrName -notin @('src', 'data', 'poster')) { continue }

      $raw = ($attr.Groups['val'].Value -split '#')[0] -split '\?' | Select-Object -First 1
      $decoded = [System.Web.HttpUtility]::UrlDecode($raw)
      $leaf = Split-Path -Leaf ($decoded -replace '/', '\')

      if ([IO.Path]::GetExtension($leaf) -ieq '.svg') {
        return ''
      }
    }

    return $match.Value
  })
}

foreach ($key in $convertedDocs.Keys) {
  $doc = $convertedDocs[$key]

  # Build maps
# Build maps
$docImageMap   = New-DocImageMap  -HuduImages $($doc.HuduImages ?? @())
$docArticleMap = New-DocArticleMap -SplitDocs ($doc.SplitDocs ?? @()) -HuduBaseUrl $HuduBaseUrl
  for ($i = 0; $i -lt $doc.SplitDocs.Count; $i++) {
    $sd  = $doc.SplitDocs[$i]
    $ctx = @{ ImageMap = $docImageMap; ArticleMap = $docArticleMap }

    $localHtml = Remove-DocVectorImageEmbeds -Html $sd.Article
    $r = Rewrite-DocLinks -Html $localHtml -ImageResolver $ImageResolver -LinkResolver $LinkResolver -Context $ctx
$r.Unresolved | Select-Object -First 5 | Format-Table -AutoSize

"{0}: HuduImages={1}  SplitDocs={2}" -f $key, ($doc.HuduImages.Count), ($doc.SplitDocs.Count) | Write-Host
"{0}: ImageMap keys={1}  ArticleMap keys={2}" -f $key, ($docImageMap.Count), ($docArticleMap.Count) | Write-Host
    Set-HuduArticle -Id $sd.HuduArticle.Id -CompanyId $sd.HuduArticle.company_id -Content $r.Html
  }
}

get-huduarticles -updatedAfter $RBStartTime | foreach-object {$article = $_.article ?? $_;  set-huduarticle -id $article.id -name "$($article.name -replace "Articles ",'')";}

$imagesFromRunbooks = ($convertedDocs.Values | % { $_.HuduImages } | ? { $_ } | Measure-Object).Count

# total split articles
$splitArticlesFromRunbooks = ($convertedDocs.Values | % { $_.SplitDocs } | ? { $_ } | Measure-Object).Count

