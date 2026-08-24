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

try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}

$RunbookPublicPhotoExtensions = @('.jpg', '.jpeg', '.png', '.gif')
function Test-RunbookPublicPhotoImage {
  param([Parameter(Mandatory)][string]$Path)
  return $RunbookPublicPhotoExtensions -icontains ([IO.Path]::GetExtension($Path))
}

function Get-HuduStoredFileName {
  param($StoredFile)
  if ($null -eq $StoredFile) { return $null }
  return $StoredFile.file_name ?? $StoredFile.name
}

function Get-RunbookDecodedName {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }

  $decoded = $Name
  for ($i = 0; $i -lt 3; $i++) {
    $decoded = $decoded -replace 'and(?=(?:amp|apos|quot|lt|gt|#\d+);)', '&'
    $decoded = [System.Web.HttpUtility]::HtmlDecode($decoded)
  }
  return ($decoded -replace '\s+', ' ').Trim()
}

function Get-RunbookCompanyName {
  param([string]$Name)
  $decoded = Get-RunbookDecodedName $Name
  if ([string]::IsNullOrWhiteSpace($decoded)) { return $decoded }

  $decoded = $decoded -replace '\s+-\s+\d{4}-\d{2}-\d{2}\s+\d{1,2}[_:.-]\d{2}(?:[_:.-]\d{2})?\s*$', ''
  $decoded = $decoded -replace '\s+\d{4}-\d{2}-\d{2}\s+\d{1,2}[_:.-]\d{2}(?:[_:.-]\d{2})?\s*$', ''
  return ($decoded -replace '\s+', ' ').Trim()
}

function Get-RunbookFinalArticleName {
  param([string]$Name)
  $decoded = Get-RunbookDecodedName $Name
  if ([string]::IsNullOrWhiteSpace($decoded)) { return $decoded }
  return ($decoded -replace '^(?i)Articles\s+', '').Trim()
}

function Get-HuduFileUrl {
  param(
    $StoredFile,
    [string]$BaseUrl
  )

  if ($null -eq $StoredFile) { return $null }

  $file = $StoredFile
  for ($i = 0; $i -lt 4; $i++) {
    $nested = $null
    foreach ($prop in @('public_photo', 'upload', 'file')) {
      if ($file.PSObject.Properties.Name -contains $prop -and $null -ne $file.$prop) {
        $nested = $file.$prop
        break
      }
    }
    if ($null -eq $nested -or [object]::ReferenceEquals($nested, $file)) { break }
    $file = $nested
  }

  $url = $null
  foreach ($prop in @('url', 'public_url', 'file_url', 'cdn_url', 'download_url')) {
    if ($file.PSObject.Properties.Name -contains $prop -and -not [string]::IsNullOrWhiteSpace([string]$file.$prop)) {
      $url = [string]$file.$prop
      break
    }
  }
  if ([string]::IsNullOrWhiteSpace($url)) { return $null }

  $url = [System.Web.HttpUtility]::HtmlDecode($url).Trim()
  if ($url.StartsWith('/')) { return $url }
  if ($url -match '^(?i)//') { $url = "https:$url" }
  if ($url -match '^(?i)https?:') {
    try {
      $uri = [Uri]$url
      if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
        $baseUri = [Uri]$BaseUrl
        if ($uri.Host -ieq $baseUri.Host) { return $uri.PathAndQuery }
      }
      if ($uri.AbsolutePath -match '^/(?:public_photo|public_photos)/') { return $uri.PathAndQuery }
    } catch {}
  }
  return $url
}

function New-RunbookImageFileLookup {
  param([object[]]$ImageFiles)

  $lookup = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($imageFile in @($ImageFiles)) {
    if ([string]::IsNullOrWhiteSpace($imageFile)) { continue }

    $leaf = Split-Path -Leaf $imageFile
    $base = [IO.Path]::GetFileNameWithoutExtension($leaf)
    $htmlDecodedLeaf = [System.Web.HttpUtility]::HtmlDecode($leaf)
    $htmlDecodedBase = [System.Web.HttpUtility]::HtmlDecode($base)
    foreach ($key in @($imageFile, $leaf, $base, $htmlDecodedLeaf, $htmlDecodedBase, [uri]::EscapeDataString($leaf), [uri]::EscapeDataString($base))) {
      if ($key -and -not $lookup.ContainsKey($key)) { $lookup[$key] = $imageFile }
    }
  }

  return $lookup
}

function Resolve-RunbookLocalImageFile {
  param(
    [string]$Source,
    [Parameter(Mandatory)]$ImageLookup
  )

  if ([string]::IsNullOrWhiteSpace($Source)) { return $null }

  $raw = ($Source -split '#')[0] -split '\?' | Select-Object -First 1
  $decoded = [System.Web.HttpUtility]::HtmlDecode([System.Web.HttpUtility]::UrlDecode($raw))

  if ($decoded -match '^(?i)file:///') {
    $decoded = $decoded -replace '^file:///', ''
    $decoded = $decoded -replace '/', '\'
  }

  $leaf = Split-Path -Leaf ($decoded -replace '/', '\')
  $base = [IO.Path]::GetFileNameWithoutExtension($leaf)
  $rawLeaf = Split-Path -Leaf $raw
  $htmlDecodedRawLeaf = [System.Web.HttpUtility]::HtmlDecode($rawLeaf)
  foreach ($key in @($decoded, $leaf, $base, $raw, $rawLeaf, $htmlDecodedRawLeaf)) {
    if ($key -and $ImageLookup.ContainsKey($key)) { return $ImageLookup[$key] }
  }

  return $null
}

function Get-RunbookLocalImageFilesFromHtml {
  param(
    [string]$Html,
    [Parameter(Mandatory)]$ImageLookup
  )

  $files = New-Object System.Collections.Generic.List[string]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  if ([string]::IsNullOrWhiteSpace($Html)) { return @() }

  foreach ($tag in $Script:RxTag.Matches($Html)) {
    $attrs = $tag.Groups['attrs'].Value
    foreach ($attr in $Script:RxAttr.Matches($attrs)) {
      $attrName = $attr.Groups['name'].Value.ToLowerInvariant()
      if ($attrName -eq 'href') { continue }

      $file = Resolve-RunbookLocalImageFile -Source $attr.Groups['val'].Value -ImageLookup $ImageLookup
      if ($file -and $seen.Add($file)) { $files.Add($file) | Out-Null }
    }
  }

  foreach ($style in $Script:RxStyleAttr.Matches($Html)) {
    foreach ($cssUrl in $Script:RxCssUrl.Matches($style.Groups['style'].Value)) {
      $file = Resolve-RunbookLocalImageFile -Source $cssUrl.Groups['u'].Value -ImageLookup $ImageLookup
      if ($file -and $seen.Add($file)) { $files.Add($file) | Out-Null }
    }
  }

  return @($files)
}

function Get-MatchingHuduPublicPhoto {
  param(
    [Parameter(Mandatory)][string]$ImageFile,
    [Parameter(Mandatory)][int]$ArticleId,
    [object[]]$ExistingPublicPhotos
  )

  $imageItem = Get-Item -LiteralPath $ImageFile -ErrorAction SilentlyContinue
  if (-not $imageItem) { return $null }

  $imageFileName = $imageItem.Name
  $articlePhotos = @($ExistingPublicPhotos | Where-Object {
    $_.record_type -ieq 'Article' -and [int]$_.record_id -eq $ArticleId
  })

  $nameMatch = $articlePhotos | Where-Object { (Get-HuduStoredFileName $_) -eq $imageFileName } | Select-Object -First 1
  if ($nameMatch) { return ($nameMatch.public_photo ?? $nameMatch) }

  $sizeMatches = @($articlePhotos | Where-Object { [int64]$_.file_size -eq [int64]$imageItem.Length })
  if ($sizeMatches.Count -eq 1) { return ($sizeMatches[0].public_photo ?? $sizeMatches[0]) }

  return $null
}

function New-RunbookArticlePublicPhotoMap {
  param(
    [string]$Html,
    [Parameter(Mandatory)]$ImageLookup,
    [Parameter(Mandatory)]$Article,
    [object[]]$ExistingPublicPhotos,
    [string]$HuduBaseUrl
  )

  $huduImages = @()
  $article = $Article.article ?? $Article
  if ($null -eq $article -or -not $article.id) { return @() }

  $localFiles = Get-RunbookLocalImageFilesFromHtml -Html $Html -ImageLookup $ImageLookup |
    Where-Object { Test-RunbookPublicPhotoImage -Path $_ }

  foreach ($imageFile in @($localFiles)) {
    $publicPhoto = Get-MatchingHuduPublicPhoto -ImageFile $imageFile -ArticleId ([int]$article.id) -ExistingPublicPhotos $ExistingPublicPhotos

    if ($publicPhoto) {
      Write-Host "ExistingPublicPhoto Match for article $($article.id): $((Get-HuduStoredFileName $publicPhoto) ?? $publicPhoto.id)"
    } else {
      Write-Host "No existing public photo for article $($article.id), uploading file @ $imageFile"
      $publicPhoto = New-HuduPublicPhoto -FilePath $imageFile -RecordId $article.Id -RecordType 'Article'
      $publicPhoto = $publicPhoto.public_photo ?? $publicPhoto
    }

    $publicPhotoUrl = Get-HuduFileUrl -StoredFile $publicPhoto -BaseUrl $HuduBaseUrl
    if (-not $publicPhotoUrl) {
      Write-Warning "Public photo upload for $imageFile did not return a usable URL."
      continue
    }

    $huduImages += @{
      OriginalFilename = $imageFile
      UsingImage       = $publicPhoto
      Url              = $publicPhotoUrl
    }
  }

  return @($huduImages)
}

function Get-MatchingHuduUpload {
  param(
    [Parameter(Mandatory)][string]$ImageFile,
    [Parameter(Mandatory)][int]$ArticleId,
    [object[]]$ExistingUploads
  )

  $imageItem = Get-Item -LiteralPath $ImageFile -ErrorAction SilentlyContinue
  if (-not $imageItem) { return $null }

  $imageFileName = $imageItem.Name
  $articleUploads = @($ExistingUploads | Where-Object {
    $_.uploadable_type -ieq 'Article' -and [int]$_.uploadable_id -eq $ArticleId
  })

  $nameMatch = $articleUploads | Where-Object { (Get-HuduStoredFileName $_) -eq $imageFileName } | Select-Object -First 1
  if ($nameMatch) { return ($nameMatch.upload ?? $nameMatch) }

  return $null
}

function New-RunbookArticleUploadMap {
  param(
    [string]$Html,
    [Parameter(Mandatory)]$ImageLookup,
    [Parameter(Mandatory)]$Article,
    [object[]]$ExistingUploads,
    [string]$HuduBaseUrl
  )

  $huduImages = @()
  $article = $Article.article ?? $Article
  if ($null -eq $article -or -not $article.id) { return @() }

  $localFiles = Get-RunbookLocalImageFilesFromHtml -Html $Html -ImageLookup $ImageLookup |
    Where-Object { -not (Test-RunbookPublicPhotoImage -Path $_) }

  foreach ($imageFile in @($localFiles)) {
    $upload = Get-MatchingHuduUpload -ImageFile $imageFile -ArticleId ([int]$article.id) -ExistingUploads $ExistingUploads

    if ($upload) {
      Write-Host "ExistingUpload Match for article $($article.id): $((Get-HuduStoredFileName $upload) ?? $upload.id)"
    } else {
      Write-Host "No existing upload for article $($article.id), uploading attachment @ $imageFile"
      $upload = New-HuduUpload -FilePath $imageFile -Uploadable_Id $article.Id -Uploadable_Type 'Article'
      $upload = $upload.upload ?? $upload
    }

    $uploadUrl = Get-HuduFileUrl -StoredFile $upload -BaseUrl $HuduBaseUrl
    if (-not $uploadUrl) {
      Write-Warning "Upload for $imageFile did not return a usable URL."
      continue
    }

    $huduImages += @{
      OriginalFilename = $imageFile
      UsingImage       = $upload
      Url              = $uploadUrl
    }
  }

  return @($huduImages)
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
            ImageFileLookup = $null
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
  $companyHint = Get-RunbookCompanyName ([IO.Path]::GetFileName($doc.extractPath.TrimEnd('\')))

  # split docs by Header/Footer and other heuristics, then merge back non-article splits into nearest article
  $presplit = Split-FullHtmlIntoArticles -Path $doc.HtmlPath -AsObjects -CompanyHint $companyHint
  $split = Merge-NonArticleSplits -Articles $presplit -company $companyHint
  
  # Assign / Ensure company
  $doc['CompanyName'] = Get-RunbookCompanyName ($split | Select-Object -ExpandProperty Company -First 1)
  if ([string]::IsNullOrWhiteSpace($doc['CompanyName'])) { $doc['CompanyName'] = $companyHint }
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
    $finalArticleName = Get-RunbookFinalArticleName $sd.Title
    $matchedDocument = $allHududocuments | Where-Object {
        $_.company_id -eq $matchedCompany.id -and
            ($(Test-Equiv -A $_.name -B $sd.Title) -or $(Test-Equiv -A $_.name -B $finalArticleName))} | Select-Object -first 1
    $matchedDocument = $matchedDocument ?? $($(Get-HuduArticles -CompanyId $matchedCompany.id -name $sd.Title) | Select-Object -first 1)
    $matchedDocument = $matchedDocument ?? $($(Get-HuduArticles -CompanyId $matchedCompany.id -name $finalArticleName) | Select-Object -first 1)
    if (-not $matchedDocument){
        $newDocument = New-HuduArticle -name "$finalArticleName" -Content "[transfer in-progress]" -CompanyId $matchedCompany.id
        $newDocument = $newDocument.article ?? $newDocument
    }
    if ($newDocument){Write-Host "Created article stub $($newDocument.name) $($newDocument.id)"}
    elseif ($matchedDocument){Write-Host "Matched exist article ($($matchedDocument.name)) $($matchedDocument.id)"}
    $articleUsed = $matchedDocument ?? $newDocument ?? $null; $articleUsed = $articleUsed.article ?? $articleUsed;
    if ($null -eq $articleUsed -or -not $articleUsed.id -or $articleUsed.id -lt 1) {Write-Error "could not match or create article $($sd.Title) for company $key"; continue;}
    Write-Host "Article stub is ready"
    $doc['SplitDocs'] += [pscustomobject]@{
      Title   = $sd.Title
      FinalName = $finalArticleName
      Article = $sd.Html
      HuduArticle = $articleUsed
    }
  }
  $HuduImages = @()
  if ($null -eq $articleUsed -or -not $articleUsed.id) {
    Write-Warning "Skipping extracted image handling for $key because no article was matched or created."
    $doc['HuduImages'] = $HuduImages
    $doc['ImageFileLookup'] = New-RunbookImageFileLookup -ImageFiles @()
    continue
  }

  $doc['ImageFileLookup'] = New-RunbookImageFileLookup -ImageFiles $doc.ExtractedImages
  $doc['HuduImages'] = $HuduImages
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
  $dec = [System.Web.HttpUtility]::HtmlDecode([System.Web.HttpUtility]::UrlDecode($raw))

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
  $leaf2Decoded = [System.Web.HttpUtility]::HtmlDecode($leaf2)
  $base2 = [IO.Path]::GetFileNameWithoutExtension($leaf2)
  $base2Decoded = [IO.Path]::GetFileNameWithoutExtension($leaf2Decoded)
  foreach ($k in @($leaf2, $base2, $leaf2Decoded, $base2Decoded)) {
    if ($k -and $ctx.ImageMap.ContainsKey($k)) {
      return $ctx.ImageMap[$k]
    }
  }

  return $null
}
try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}

function Test-RunbookResolvedImageSource {
  param([string]$Source)
  if ([string]::IsNullOrWhiteSpace($Source)) { return $false }

  $value = [System.Web.HttpUtility]::HtmlDecode($Source).Trim()
  return [bool]($value -match '^(?i)(https?:|data:|/(?:public_photo|public_photos)/)')
}

function Test-RunbookResolvedLinkTarget {
  param([string]$Href)
  if ([string]::IsNullOrWhiteSpace($Href)) { return $false }

  $value = [System.Web.HttpUtility]::HtmlDecode($Href).Trim()
  return [bool]($value -match '^(?i)(https?:|mailto:|tel:)')
}

function Get-RunbookBlockingRewriteIssues {
  param($RewriteResult)

  $issues = @()
  if ($null -eq $RewriteResult) { return @([pscustomobject]@{ Tag='article'; Attr='content'; Value='<null rewrite result>'; Reason='No rewritten HTML was produced' }) }

  $unresolvedItems = @()
  if ($RewriteResult.PSObject.Properties['Unresolved'] -and $null -ne $RewriteResult.Unresolved) {
    $unresolvedItems = @($RewriteResult.Unresolved | Where-Object { $_ })
  }

  foreach ($unresolved in $unresolvedItems) {
    $reason = if ($unresolved.Attr -ieq 'href') {
      'Link target was not resolved to a Hudu or absolute URL'
    } else {
      'Image source was not resolved to a Hudu URL'
    }

    $issues += [pscustomobject]@{
      Tag    = $unresolved.Tag
      Attr   = $unresolved.Attr
      Value  = $unresolved.Value
      Reason = $reason
    }
  }

  $rewrittenHtml = [string]($RewriteResult.Html ?? '')
  foreach ($tag in $Script:RxTag.Matches($rewrittenHtml)) {
    $tagName = $tag.Groups[1].Value.ToLowerInvariant()
    $attrs = $tag.Groups['attrs'].Value

    foreach ($attr in $Script:RxAttr.Matches($attrs)) {
      $attrName = $attr.Groups['name'].Value.ToLowerInvariant()
      $value = $attr.Groups['val'].Value

      if ($attrName -eq 'href') {
        if (-not (Test-RunbookResolvedLinkTarget -Href $value)) {
          $issues += [pscustomobject]@{
            Tag    = $tagName
            Attr   = $attrName
            Value  = $value
            Reason = 'Rewritten HTML still contains a local, anchor-only, or empty link target'
          }
        }
        continue
      }

      if (-not (Test-RunbookResolvedImageSource -Source $value)) {
        $issues += [pscustomobject]@{
          Tag    = $tagName
          Attr   = $attrName
          Value  = $value
          Reason = 'Rewritten HTML still contains a local or empty image source'
        }
      }
    }
  }

  foreach ($style in $Script:RxStyleAttr.Matches($rewrittenHtml)) {
    foreach ($cssUrl in $Script:RxCssUrl.Matches($style.Groups['style'].Value)) {
      $value = $cssUrl.Groups['u'].Value
      if (-not (Test-RunbookResolvedImageSource -Source $value)) {
        $issues += [pscustomobject]@{
          Tag    = 'style'
          Attr   = 'url'
          Value  = $value
          Reason = 'Rewritten HTML still contains a local or empty CSS image URL'
        }
      }
    }
  }

  return $issues
}

$existingPublicPhotos = Get-HuduPublicPhotos | Where-Object { $_.record_type -ieq 'Article' }
$existingArticleUploads = Get-HuduUploads | Where-Object { $_.uploadable_type -ieq 'Article' }

foreach ($key in $convertedDocs.Keys) {
  $doc = $convertedDocs[$key]

  $docArticleMap = New-DocArticleMap -SplitDocs ($doc.SplitDocs ?? @()) -HuduBaseUrl $HuduBaseUrl

  for ($i = 0; $i -lt $doc.SplitDocs.Count; $i++) {
    $sd  = $doc.SplitDocs[$i]

    $articlePublicPhotos = New-RunbookArticlePublicPhotoMap `
      -Html $sd.Article `
      -ImageLookup $doc.ImageFileLookup `
      -Article $sd.HuduArticle `
      -ExistingPublicPhotos $existingPublicPhotos `
      -HuduBaseUrl $HuduBaseUrl

    $articleUploads = New-RunbookArticleUploadMap `
      -Html $sd.Article `
      -ImageLookup $doc.ImageFileLookup `
      -Article $sd.HuduArticle `
      -ExistingUploads $existingArticleUploads `
      -HuduBaseUrl $HuduBaseUrl

    $existingPublicPhotos += @($articlePublicPhotos | ForEach-Object { $_.UsingImage } | Where-Object { $_ })
    $existingArticleUploads += @($articleUploads | ForEach-Object { $_.UsingImage } | Where-Object { $_ })

    $segmentImagesForMap = @($articlePublicPhotos) + @($articleUploads) | Where-Object { $_ }
    $doc['HuduImages'] = @($doc.HuduImages) + @($segmentImagesForMap) | Where-Object { $_ }
  }

  $docImageMap = if (@($doc.HuduImages).Count -gt 0) {
    New-DocImageMap -HuduImages @($doc.HuduImages) -BaseUrl $HuduBaseUrl
  } else {
    New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
  }

  $rewrittenArticles = @()
  for ($i = 0; $i -lt $doc.SplitDocs.Count; $i++) {
    $sd  = $doc.SplitDocs[$i]
    $ctx = @{ ImageMap = $docImageMap; ArticleMap = $docArticleMap }

    $r = Rewrite-DocLinks -Html $sd.Article -ImageResolver $ImageResolver -LinkResolver $LinkResolver -Context $ctx
    $blockingRewriteIssues = @(Get-RunbookBlockingRewriteIssues -RewriteResult $r)
    if ($blockingRewriteIssues.Count -gt 0) {
      Write-Warning "Article '$($sd.Title)' ($($sd.HuduArticle.Id)) has $($blockingRewriteIssues.Count) unresolved link/image target(s) after local rewrite; updating anyway so resolved images and links are preserved."
      $blockingRewriteIssues | Select-Object -First 5 | Format-Table -AutoSize
    }

    $rewrittenArticles += [pscustomobject]@{
      SplitDoc = $sd
      Rewrite = $r
      Issues = $blockingRewriteIssues
    }
  }

  "{0}: HuduImages={1}  SplitDocs={2}" -f $key, (@($doc.HuduImages).Count), (@($doc.SplitDocs).Count) | Write-Host
  "{0}: ImageMap keys={1}  ArticleMap keys={2}" -f $key, ($docImageMap.Count), ($docArticleMap.Count) | Write-Host

  foreach ($item in $rewrittenArticles) {
    $sd = $item.SplitDoc
    Set-HuduArticle -Id $sd.HuduArticle.Id -CompanyId $sd.HuduArticle.company_id -Name $sd.FinalName -Content $item.Rewrite.Html
  }
}

$imagesFromRunbooks = ($convertedDocs.Values | % { $_.HuduImages } | ? { $_ } | Measure-Object).Count

# total split articles
$splitArticlesFromRunbooks = ($convertedDocs.Values | % { $_.SplitDocs } | ? { $_ } | Measure-Object).Count

