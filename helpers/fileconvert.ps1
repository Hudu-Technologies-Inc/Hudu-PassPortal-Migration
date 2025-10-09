function Normalize-CompanyName([string]$s) {
  # strip leading digits + optional separators like '.', ')', '-', '_' and spaces
  return ($s -replace '^\s*\d+\s*[-._)\(]*\s*', '') -replace '\s{2,}', ' '
}
function Get-SafeFileBase {
  param([Parameter(Mandatory)][string]$Name)
  $s = $Name
  # normalize whitespace
  $s = $s -replace '\s+', ' '          # collapse
  $s = $s.Trim()                        # trim ends
  # replace risky punctuation
  $s = $s -replace '&', 'and'
  # remove Windows forbidden chars
  $s = $s -replace '[<>:"/\\|?*]', ''
  # remove control chars
  $s = ($s.ToCharArray() | Where-Object { [int]$_ -ge 32 }) -join ''
  # Windows hates trailing dots/spaces on file/dir names
  $s = $s -replace '[\s\.]+$', ''
  if ([string]::IsNullOrWhiteSpace($s)) { $s = 'untitled' }
  return $s
}
function Split-HtmlIntoArticles {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position=0)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$Path,

    # If you already know the company name, pass it to skip footer inference
    [string]$CompanyOverride,

    [switch]$AsObjects,
    [switch]$AsHtml
  )

  $html = [IO.File]::ReadAllText($Path)

  # Regexes
  $rxPage   = [regex]'(?is)<div[^>]*\bclass\s*=\s*([''"])page\1[^>]*>(?<content>.*?)</div>'
  $rxPTxt   = [regex]'(?is)<p[^>]*>(?<t>.*?)</p>'
  $rxNum    = [regex]'^\s*\d+(\.\d+)*\s*$'                  # 1, 1.2, 10.11.12
  $rxFooter = [regex]'(?is)<p[^>]*>[^<]*\|\s*(?<co>[^<]+)\s*</p>\s*$'  # "* | Company"

  # Helpers
  function Get-Ps([string]$block){
    ($rxPTxt.Matches($block) | ForEach-Object { $_.Groups['t'].Value.Trim() })
  }
  function Strip-FirstP([string]$block, [int]$n=1){
    $out = $block
    for ($i=0; $i -lt $n; $i++){
      $out = [regex]::Replace($out, '(?is)^\s*<p[^>]*>.*?</p>\s*', '', 1)
    }
    $out
  }
  function Strip-TrailingPageNumber([string]$block){
    [regex]::Replace($block, '(?is)\s*<p[^>]*>\s*\d+(\.\d+)*\s*</p>\s*$', '')
  }
  function Strip-Footer([string]$block, [string]$company){
    if (-not $company) { return $block }
    $co = [regex]::Escape($company)
    [regex]::Replace($block, "(?is)\s*<p[^>]*>[^<]*\|\s*$co\s*</p>\s*$", '')
  }

  # Collect pages
  $pageMatches = $rxPage.Matches($html)
  if ($pageMatches.Count -eq 0) {
    if ($AsObjects -or $AsHtml) { return @() } else { return '[]' }
  }
  $pages = @()
  foreach ($m in $pageMatches) { $pages += ,$m.Groups['content'].Value }

  # Infer company from footers if not provided
  $company = $CompanyOverride
  if (-not $company) {
    $footerCompanies = @()
    foreach ($p in $pages) {
      $fm = $rxFooter.Match($p)
      if ($fm.Success) { $footerCompanies += $fm.Groups['co'].Value.Trim() }
    }
    if ($footerCompanies.Count -gt 0) {
      $company = ($footerCompanies | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
    }
  }

  # Header page: if first page is a pure “doc header” (Company/Doc title),
  # we still rely on article pages that follow the {Title, Number} rule.
  $articles = New-Object System.Collections.Generic.List[object]
  $current  = $null

  for ($i=0; $i -lt $pages.Count; $i++) {
    $pg     = $pages[$i]
    $ptexts = Get-Ps $pg
    $first  = $ptexts | Select-Object -First 1
    $second = $ptexts | Select-Object -Skip 1 -First 1

    $looksLikeTitle = (-not [string]::IsNullOrWhiteSpace($first)) -and (-not $rxNum.IsMatch($first))
    $nextIsNumber   = ($second -and $rxNum.IsMatch($second))

    if ($looksLikeTitle -and $nextIsNumber) {
      # New article starts on this page
      if ($null -ne $current) {
        $current.Html = $current.Html.Trim()
        if ($current.Title -and $current.Html) { $articles.Add($current) }
      }

      # Remove the title line from this page’s body
      $body = Strip-FirstP $pg 1
      $body = Strip-TrailingPageNumber $body
      $body = Strip-Footer $body $company

      $current = [pscustomobject]@{
        Company = $company
        Title   = $first
        Html    = "<div class='page'>$body</div>`n"
      }
    }
    else {
      # Continuation (or preface pages before first article)
      $body = Strip-TrailingPageNumber $pg
      $body = Strip-Footer $body $company

      if ($null -eq $current) {
        # Buffer preface pages under a synthetic article until we hit the first real one
        $current = [pscustomobject]@{
          Company = $company
          Title   = 'Preface'
          Html    = ''
        }
      }
      $current.Html += "<div class='page'>$body</div>`n"
    }
  }

  # Commit last
  if ($null -ne $current) {
    $current.Html = $current.Html.Trim()
    if ($current.Title -and $current.Html) { $articles.Add($current) }
  }

  # If the first article is a 'Preface' and you don't want it, drop it:
  $articles = [System.Collections.Generic.List[object]]($articles | Where-Object { $_.Title -ne 'Preface' })

  if ($AsObjects) { return $articles }
  elseif ($AsHtml) {
    return ($articles | ForEach-Object { "<!-- $($_.Company) | $($_.Title) -->`n$($_.Html)" }) -join "`n`n"
  }
  else {
    return ($articles | ConvertTo-Json -Depth 10)
  }
}

function Get-AbsolutePath {
  param(
    [Parameter(Mandatory)]$PathOrInfo,
    [string]$BaseFolder  # e.g. $match.folder
  )
  if ($PathOrInfo -is [IO.FileInfo]) { return $PathOrInfo.FullName }

  $p = [string]$PathOrInfo
  if ([string]::IsNullOrWhiteSpace($p)) { return $null }

  if ([IO.Path]::IsPathRooted($p)) {
    try { return (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path } catch { return $p }
  }

  if ($BaseFolder) {
    $cand = Join-Path $BaseFolder $p
    if (Test-Path -LiteralPath $cand) { return (Resolve-Path -LiteralPath $cand).Path }
  }

  # last resort: try current location
  try { return (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path } catch { return $p }
}

function Get-NormalizedExtension {
  param([Parameter(Mandatory)]$PathOrExt)

  $name = if ($PathOrExt -is [IO.FileInfo]) { $PathOrExt.Name } else { [IO.Path]::GetFileName([string]$PathOrExt) }
  if ([string]::IsNullOrWhiteSpace($name)) { return $null }

  if ($name -match '\.(tar\.(?:gz|bz2|xz))$') { return ('.' + $Matches[1].ToLowerInvariant()) } # ".tar.gz"
  $ext = [IO.Path]::GetExtension($name)
  if ([string]::IsNullOrEmpty($ext)) { return $null }
  return $ext.ToLowerInvariant()
}

# --- categorizer (Disallowed > Image > Allowed > Unknown) ---
function Get-ExtensionCategory {
  param([Parameter(Mandatory)]$PathOrExt)
    $CanConvertExtensions = @('.pdf','.doc','.docx','.xls','.xlsx','.ppt','.htm','.html','.pptx','.txt','.rtf','.jpg','.jpeg','.png')
    $ImageTypes           = @('.png', '.jpeg', '.jpg', '.gif', '.svg', '.bmp')
    $Direct2Doc           = @('.html','.htm')   # both with leading dot

    $DisallowedForConvert = @(
      '.mp3','.wav','.flac','.aac','.ogg','.wma','.m4a',
      '.dll','.so','.lib','.bin','.class','.pyc','.pyo','.o','.obj',
      '.exe','.msi','.bat','.cmd','.sh','.jar','.app','.apk','.dmg','.iso','.img',
      '.zip','.rar','.7z','.tar','.gz','.bz2','.xz','.tgz','.lz',
      '.mp4','.avi','.mov','.wmv','.mkv','.webm','.flv',
      '.psd','.ai','.eps','.indd','.sketch','.fig','.xd','.blend',
      '.ds_store','.thumbs','.lnk','.heic'
    )

    # --- case-insensitive sets ---
    $cmp = [StringComparer]::OrdinalIgnoreCase

    $CanConvertSet     = [Collections.Generic.HashSet[string]]::new($cmp)
    $ImageSet          = [Collections.Generic.HashSet[string]]::new($cmp)
    $NonConvertableSet = [Collections.Generic.HashSet[string]]::new($cmp)
    $Direct2DocSet     = [Collections.Generic.HashSet[string]]::new($cmp)

    # CAST to [string[]] so the right overload is picked
    $CanConvertSet.UnionWith([string[]]$CanConvertExtensions)
    $ImageSet.UnionWith([string[]]$ImageTypes)
    $NonConvertableSet.UnionWith([string[]]$DisallowedForConvert)
    $Direct2DocSet.UnionWith([string[]]$Direct2Doc)  

  $ext = Get-NormalizedExtension $PathOrExt
  if (-not $ext) { return 'Unknown' }

  if ($NonConvertableSet.Contains($ext)) { return 'NoConvert' }
  if ($ImageSet.Contains($ext))      { return 'Image' }
  if ($Direct2DocSet.Contains($ext))    { return 'Web' }
  if ($CanConvertSet.Contains($ext))    { return 'Allowed' }
  return 'Unknown'
}

function Get-FileExt {
  param([Parameter(Mandatory)]$PathOrInfo)

  $name = if ($PathOrInfo -is [IO.FileInfo]) { $PathOrInfo.Name }
          else { [IO.Path]::GetFileName([string]$PathOrInfo) }

  if ($name -match '\.(tar\.(?:gz|bz2|xz))$') {
    return $Matches[1].ToLowerInvariant()            # "tar.gz" / "tar.bz2" / "tar.xz"
  }

  return ([IO.Path]::GetExtension($name)).TrimStart('.').ToLowerInvariant()
}


function Get-DocumentFilesForRow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object]$Row,                # expects .locator, .name
    [Parameter(Mandatory)][string]$RootDocs,           # e.g. Join-Path $ITBoostExportPath 'documents'
    [Parameter()][object[]]$FolderIndex,               # from Build-DocFolderIndex (optional)
    [int]$MaxFilesPerRow = 200,
    [int]$MinConfidence = 60
  )

  function _norm([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    (($s -replace '[^\p{L}\p{Nd}]+',' ') -replace '\s+',' ').Trim().ToLower()
  }

  $candidates = [System.Collections.Generic.List[object]]::new()

  # 1) Indexed resolve (if available)
  if ($FolderIndex -and (Get-Command Resolve-DocFolder -ErrorAction SilentlyContinue)) {
    $hit = Resolve-DocFolder -Row $Row -Index $FolderIndex
    if ($hit) {
      $candidates.add( [pscustomobject]@{ Path=$hit.Path; Score=[int]$hit.Confidence; Reason=$hit.Reason })
    }
  }

  # 2) Fallback scans (bounded to RootDocs)
  $loc  = [string]$Row.locator
  $name = [string]$Row.name

  function _safeLike([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    # replace wildcard-breaking chars with '?'
    "*$($s -replace '[\\/:*?""<>|]','?')*"
  }
  function _addMatches([string]$like, [int]$weight, [string]$reason) {
    if (-not $like) { return }
    $dirs = Get-ChildItem -Path $RootDocs -Recurse -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $like } |
            Select-Object -First 5
    foreach($d in $dirs){
      $candidates.add([pscustomobject]@{ Path=$d.FullName; Score=$weight; Reason=$reason })
    }
  }

  if ($loc) {
    _addMatches (_safeLike $loc)              90 'like:locator'
    _addMatches ("*DOC*$(( _safeLike $loc).Trim('*'))*") 88 'like:DOC+locator'
  }
  if ($name) {
    _addMatches ("*DOC*$(( _safeLike $name).Trim('*'))*") 82 'like:DOC+name'
    _addMatches (_safeLike $name)             78 'like:name'
  }

  # 3) De-dupe candidate folders
  $candidates = $candidates | Sort-Object Path -Unique
  if (-not $candidates) {
    return [pscustomobject]@{
      itb_id=$Row.id; name=$Row.name; locator=$Row.locator
      folder=$null; files=@(); confidence=0; reason='no-folders'
    }
  }

  # 4) Rank (THIS was missing in your code — emit an object!)
  $ranked = foreach ($c in $candidates) {
    $extra = 0
    $leaf = [IO.Path]::GetFileName($c.Path)
    if ($leaf -like 'doc*') { $extra += 5 }
    [pscustomobject]@{
      Path   = $c.Path
      Score  = [int]$c.Score + $extra
      Reason = $c.Reason + ($(if($extra){'+signal'}))
    }
  }

  $rankedWithFiles = foreach ($r in ($ranked | Sort-Object Score -Descending)) {
    $files = Get-ChildItem -Path $r.Path -File -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First $MaxFilesPerRow
    [pscustomobject]@{ Path=$r.Path; Score=$r.Score; Reason=$r.Reason; Files=$files }
  }

  $chosen = $rankedWithFiles | Where-Object { $_.Files.Count -gt 0 } | Select-Object -First 1
  if (-not $chosen) { $chosen = $rankedWithFiles | Select-Object -First 1 } # fallback even if no files

  if (-not $chosen -or $chosen.Score -lt $MinConfidence) {
    return [pscustomobject]@{
      itb_id=$Row.id; name=$Row.name; locator=$Row.locator
      folder=$chosen?.Path; files=@(); confidence=($chosen?.Score ?? 0)
      reason = if ($chosen) { 'below-min-confidence' } else { 'no-candidates' }
    }
  }

  [pscustomobject]@{
    itb_id     = $Row.id
    name       = $Row.name
    locator    = $Row.locator
    folder     = $chosen.Path
    files      = $chosen.Files
    confidence = $chosen.Score
    reason     = $chosen.Reason
  }
}


function Normalize-DocKey {
  param([string]$s, [switch]$StripDocPrefix, [switch]$StripNumericId)
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  $t = $s.Trim()

  if ($StripDocPrefix) { $t = ($t -replace '^(?i)doc[\s\-_]*', '') }
  if ($StripNumericId) { $t = ($t -replace '^(?i)(\d+)[\s\-_]*', '') }

  # keep letters/digits and spaces, collapse whitespace, lowercase
  $t = (($t -replace '[^\p{L}\p{Nd}]+', ' ') -replace '\s+', ' ').Trim().ToLower()
  return $t
}

function Build-DocFolderIndex {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Root)

  $dirs = Get-ChildItem -Path $Root -Recurse -Directory -ErrorAction SilentlyContinue

  foreach ($d in $dirs) {
    $name = $d.Name
    if ($name -notmatch '^(?i)doc[\s\-_]') { continue }  # only index "DOC-..." folders

    $normFull = Normalize-DocKey $name
    $noDoc    = Normalize-DocKey $name -StripDocPrefix
    # strip "DOC-" AND leading numeric id like "DOC-12609951-"
    $noDocId  = Normalize-DocKey ($name -replace '^(?i)doc[\s\-_]*', '') -StripNumericId

    [pscustomobject]@{
      Name        = $name
      FullName    = $d.FullName
      NormFull    = $normFull
      NormNoDoc   = $noDoc
      NormNoDocId = $noDocId
    }
  }
}

function Resolve-DocFolder {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object]$Row,    # expects fields: locator, name
    [Parameter(Mandatory)][object[]]$Index
  )

  $loc  = [string]$Row.locator
  $name = [string]$Row.name

  # Candidate normalized keys
  $keys = @()

  if ($loc) {
    # exact locator variants
    $keys += [pscustomobject]@{ Key = (Normalize-DocKey $loc);          Weight = 100; Field='locator:norm' }
    $keys += [pscustomobject]@{ Key = (Normalize-DocKey "DOC-$loc");     Weight = 95;  Field='locator:doc+' }
    $keys += [pscustomobject]@{ Key = (Normalize-DocKey $loc -StripDocPrefix); Weight = 90; Field='locator:nodoc' }
  }
  if ($name) {
    $keys += [pscustomobject]@{ Key = (Normalize-DocKey "DOC-$name");    Weight = 80;  Field='name:doc+' }
    $keys += [pscustomobject]@{ Key = (Normalize-DocKey $name);          Weight = 75;  Field='name:norm' }
  }

  # Exact matches first
  foreach ($cand in $keys) {
    $hit = $Index | Where-Object {
      $_.NormFull -eq $cand.Key -or
      $_.NormNoDoc -eq $cand.Key -or
      $_.NormNoDocId -eq $cand.Key
    } | Select-Object -First 1
    if ($hit) {
      return [pscustomobject]@{
        Path       = $hit.FullName
        Confidence = $cand.Weight
        Reason     = "exact:$($cand.Field)"
      }
    }
  }

  # Fuzzy contains (last resort)
  foreach ($cand in $keys) {
    if (-not $cand.Key) { continue }
    $hit = $Index | Where-Object {
      $_.NormFull    -like "*$($cand.Key)*" -or
      $_.NormNoDoc   -like "*$($cand.Key)*" -or
      $_.NormNoDocId -like "*$($cand.Key)*"
    } | Select-Object -First 1
    if ($hit) {
      return [pscustomobject]@{
        Path       = $hit.FullName
        Confidence = [math]::Max(50, $cand.Weight - 30)
        Reason     = "contains:$($cand.Field)"
      }
    }
  }

  return $null
}

function Convert-WithLibreOffice {
    param (
        [string]$inputFile,
        [string]$outputDir,
        [string]$sofficePath
    )

    try {
        $extension = [System.IO.Path]::GetExtension($inputFile).ToLowerInvariant()
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputFile)

        switch ($extension.ToLowerInvariant()) {
            # Word processors
            ".doc"      { $intermediateExt = "odt" }
            ".docx"     { $intermediateExt = "odt" }
            ".docm"     { $intermediateExt = "odt" }
            ".rtf"      { $intermediateExt = "odt" }
            ".txt"      { $intermediateExt = "odt" }
            ".md"       { $intermediateExt = "odt" }
            ".wpd"      { $intermediateExt = "odt" }

            # Spreadsheets
            ".xls"      { $intermediateExt = "ods" }
            ".xlsx"     { $intermediateExt = "ods" }
            ".csv"      { $intermediateExt = "ods" }

            # Presentations
            ".ppt"      { $intermediateExt = "odp" }
            ".pptx"     { $intermediateExt = "odp" }
            ".pptm"     { $intermediateExt = "odp" }

            # Already OpenDocument
            ".odt"      { $intermediateExt = $null }
            ".ods"      { $intermediateExt = $null }
            ".odp"      { $intermediateExt = $null }

            default { $intermediateExt = $null }
        }
        if ($intermediateExt) {
            $intermediatePath = Join-Path $outputDir "$baseName.$intermediateExt"
            write-host "Step 1: Converting to .$intermediateExt..." -Color DarkCyan

            Start-Process -FilePath "$sofficePath" `
                -ArgumentList "--headless", "--convert-to", $intermediateExt, "--outdir", "`"$outputDir`"", "`"$inputFile`"" `
                -Wait -NoNewWindow

            if (-not (Test-Path $intermediatePath)) {
                throw "$intermediateExt conversion failed for $inputFile"
            }
        } else {
            # No conversion needed
            $intermediatePath = $inputFile
        }

        write-host  "Step $(if ($intermediateExt) {'2'} else {'1'}): Converting .$intermediateExt to XHTML..." -Color DarkCyan

        Start-Process -FilePath "$sofficePath" `
            -ArgumentList "--headless", "--convert-to", "xhtml", "--outdir", "`"$outputDir`"", "`"$intermediatePath`"" `
            -Wait -NoNewWindow

        $htmlPath = Join-Path $outputDir "$baseName.xhtml"

        if (-not (Test-Path $htmlPath)) {
            throw "XHTML conversion failed for $intermediatePath"
        }

        return $htmlPath
    }
    catch {
        Write-ErrorObjectsToFile -ErrorObject @{
            fileconversionError = @{
                error      = $_
                file       = $inputFile
                officepath = $sofficePath
                outdir     = $outputDir
            }
        }
        return $null
    }
}

function Get-EmbeddedFilesFromHtml {
    param (
        [string]$htmlPath,
        [int32]$resolution=5
    )

    if (-not (Test-Path $htmlPath)) {
        Write-Warning "HTML file not found: $htmlPath"
        return @{}
    }

    $htmlContent = Get-Content $htmlPath -Raw
    $baseDir = Split-Path -Path $htmlPath
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($htmlPath)
    $trimmedBaseName = if ($baseName.Length -gt $resolution) {
        $baseName.Substring(0, $baseName.Length - $resolution).ToLower()
    } else {
        $baseName.ToLower()
    }
    $results = @{
        ExternalFiles        = @()
        Base64Images         = @()
        Base64ImagesWritten  = @()
        UpdatedHTMLContent   = $null
    }

    $guid = [guid]::NewGuid().ToString()
    $uuidSuffix = ($guid -split '-')[0]

    $counter = 0
    $htmlContent = [regex]::Replace($htmlContent, '(?i)<img([^>]+?)src\s*=\s*["'']data:image/(?<type>[a-z]+);base64,(?<b64data>[^"'']+)["'']', {
        param($match)

        $type = $match.Groups["type"].Value
        $b64  = $match.Groups["b64data"].Value

        $ext = switch ($type) {
            'png'  { 'png' }
            'jpeg' { 'jpg' }
            'jpg'  { 'jpg' }
            'gif'  { 'gif' }
            'svg'  { 'svg' }
            'bmp'  { 'bmp' }
            default { 'bin' }
        }

        $counter++
        $filename = "${baseName}_embedded_${uuidSuffix}_$counter.$ext"
        $filepath = Join-Path $baseDir $filename

        try {
            [IO.File]::WriteAllBytes($filepath, [Convert]::FromBase64String($b64))
            $results.ExternalFiles += $filepath
            $results.Base64Images  += "data:image/$type;base64,..."
            $results.Base64ImagesWritten += $filepath

            return "<img$($match.Groups[1].Value)src='$filename'"
        } catch {
            Write-Warning "Failed to decode embedded image: $($_.Exception.Message)"
            return "<img$($match.Groups[1].Value)src='$filename'"
        }
    })
    $skipExts = @(
        ".doc", ".docx", ".docm", ".rtf", ".txt", ".md", ".wpd",
        ".xls", ".xlsx", ".csv", ".ppt", ".pptx", ".pptm",
        ".odt", ".ods", ".odp", ".xhtml", ".xml", ".html", ".json", ".htm"
    )

    $allFiles = Get-ChildItem -Path $baseDir -File
    foreach ($file in $allFiles) {
        $fullFilePath = [IO.Path]::GetFullPath($file.FullName).ToLowerInvariant()
        $htmlPathNormalized = [IO.Path]::GetFullPath($htmlPath).ToLowerInvariant()

        if ($fullFilePath -eq $htmlPathNormalized) {
            continue
        }

        if ($file.Extension.ToLowerInvariant() -in $skipExts) {
            continue
        }

        $otherBaseName = $file.BaseName.ToLower()
        if ($otherBaseName.StartsWith($trimmedBaseName)) {
            $results.ExternalFiles += "$fullFilePath"
        }
    }
        
        
    $results.UpdatedHTMLContent = $htmlContent
    return $results
}

# TODO: DRY this up later.
function Convert-PdfToHtml {
  param(
    [Parameter(Mandatory)][string]$InputPdfPath,
    [Parameter(Mandatory)][string]$OutputDir,
    [string]$PdftoHtmlPath = "$PSScriptRoot\tools\poppler\pdftohtml.exe"
  )
  if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
  $outHtml = Join-Path $OutputDir ( [IO.Path]::GetFileNameWithoutExtension($InputPdfPath) + '.html' )
  $args = @('-s','-noframes','-enc','UTF-8','-c','-fmt','png', $InputPdfPath, $outHtml)
  Start-Process -FilePath $PdftoHtmlPath -ArgumentList $args -NoNewWindow -Wait
  return $outHtml
}

function Convert-PdfXmlToHtml {
    param (
        [Parameter(Mandatory)][string]$XmlPath,
        [string]$OutputHtmlPath = "$XmlPath.html"
    )

    if (-not (Test-Path $XmlPath)) {
        throw "Input XML not found: $XmlPath"
    }

    [xml]$doc = Get-Content $XmlPath
    $html = @()
    $html += '<!DOCTYPE html>'
    $html += '<html><head><meta charset="UTF-8">'
    $html += '<style>body{font-family:sans-serif;font-size:12pt;line-height:1.4}</style></head><body>'

    foreach ($page in $doc.pdf2xml.page) {
        $html += "<div class='page' style='margin-bottom:2em'>"
        foreach ($text in $page.text) {
            $content = ($text.'#text' -replace '\s+', ' ').Trim()
            if ($content) {
                $html += "<p>$content</p>"
            }
        }
        $html += "</div>"
    }

    $html += '</body></html>'
    Set-Content -Path $OutputHtmlPath -Value ($html -join "`n") -Encoding UTF8
    write-host  "Generated slim HTML: $OutputHtmlPath" -Color Green
}

function Convert-PdfToSlimHtml {
    param (
        [Parameter(Mandatory)][string]$InputPdfPath,
        [string]$OutputDir = (Split-Path -Path $InputPdfPath),
        [string]$PdfToHtmlPath = "C:\tools\poppler\bin\pdftohtml.exe"
    )

    if (-not (Test-Path $InputPdfPath)) {
        throw "PDF not found: $InputPdfPath"
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputPdfPath)
    $xmlOutput = Join-Path $OutputDir "$baseName.xml"
    $htmlOutput = Join-Path $OutputDir "$baseName.slim.html"

    $args = @(
        # "-xml"            # XML format
        "-p"              # Extract images
        "-zoom", "1.0"    # No zoom distortion
        "-noframes"       # Single output file
        "-nomerge"        # Keep layout simple
        "-enc", "UTF-8"
        "-nodrm"
        "`"$InputPdfPath`"",
        "`"$htmlOutput`""
    )

    # # Run conversion to XML
    Start-Process -FilePath $PdfToHtmlPath -ArgumentList $args -NoNewWindow -Wait

    # if (-not (Test-Path $xmlOutput)) {
    #     throw "XML output was not created."
    # }

    # Convert XML to lightweight HTML
    # Convert-PdfXmlToHtml -XmlPath $xmlOutput -OutputHtmlPath $htmlOutput
    return $htmlOutput
}
function Convert-PdfToHtml {
    param (
        [string]$inputPath,
        [string]$outputDir = (Split-Path $inputPath),
        [string]$pdftohtmlPath = "C:\tools\poppler\bin\pdftohtml.exe",
        [bool]$includeHiddenText = $true,
        [bool]$complexLayoutMode = $true
    )

    $filename = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
    $outputHtml = Join-Path $outputDir "$filename.html"

    $popplerArgs = @()

    # Preserve layout with less nesting
    if ($complexLayoutMode) {
        $popplerArgs += "-c"            # complex layout mode
    }

    # Enable image extraction
    $popplerArgs += "-p"                # extract images
    $popplerArgs += "-zoom 1.0"         # avoid automatic zoom bloat

    # Output options
    $popplerArgs += "-noframes"        # single HTML file instead of one per page
    $popplerArgs += "-nomerge"         # don't merge text blocks (more control)
    $popplerArgs += "-enc UTF-8"       # UTF-8 encoding
    $popplerArgs += "-nodrm"           # ignore any DRM restrictions

    if ($includeHiddenText) {
        $popplerArgs += "-hidden"
    }

    # Wrap file paths
    $popplerArgs += "`"$inputPath`""
    $popplerArgs += "`"$outputHtml`""

    Start-Process -FilePath $pdftohtmlPath `
        -ArgumentList $popplerArgs -Wait -NoNewWindow

    return (Test-Path $outputHtml) ? $outputHtml : $null
}


function Save-Base64ToFile {
    param (
        [Parameter(Mandatory)]
        [string]$Base64String,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    # Remove data URI prefix if present (e.g., "data:image/png;base64,...")
    if ($Base64String -match '^data:.*?;base64,') {
        $Base64String = $Base64String -replace '^data:.*?;base64,', ''
    }

    $bytes = [System.Convert]::FromBase64String($Base64String)
    [System.IO.File]::WriteAllBytes($OutputPath, $bytes)

    write-host  "Saved Base64 content to: $OutputPath" -Color Cyan
}


function Stop-LibreOffice {
    Get-Process | Where-Object { $_.Name -like "soffice*" } | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Get-LibreMSI {
    param ([string]$tmpfolder)
    if (Test-Path "C:\Program Files\LibreOffice\program\soffice.exe") {
        return "C:\Program Files\LibreOffice\program\soffice.exe"
    }
    $downloadUrl = "$LibreFullInstall"
    $downloadPath = Join-Path $tmpfolder "LibreOffice.msi"

    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath

    # Attempt to install
    Start-Process msiexec.exe -ArgumentList "/i `"$downloadPath`" /qn" -Wait

    # Look for default install path
    $sofficePath = "C:\Program Files\LibreOffice\program\soffice.exe"
    if (Test-Path $sofficePath) {
        return $sofficePath
    } else {
        $sofficePath=$(read-host "Sorry, but we couldnt find libreoffice install. What we need is soffice.exe, usually at '$sofficePath'. Please enter the path for this manually now.")
    }
    return $sofficePath
}
function Get-LibrePortable {
    param (
        [string]$tmpfolder
    )

    $downloadUrl = "$LibrePortaInstall"
    $downloadPath = Join-Path $tmpfolder "LibreOfficePortable.paf.exe"
    $extractPath = Join-Path $tmpfolder "LibreOfficePortable"

    if (!(Test-Path $extractPath)) {
        New-Item -ItemType Directory -Path $extractPath | Out-Null
    }

    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath

    Start-Process -FilePath $downloadPath -ArgumentList "/SILENT", "/NORESTART", "/SUPPRESSMSGBOXES", "/DIR=`"$extractPath`"" -Wait

    $sofficePath = Join-Path $extractPath "App\libreoffice\program\soffice.exe"
    if (Test-Path $sofficePath) {
        return $sofficePath
    } else {
        $sofficePath=$(read-host "Sorry, but we couldnt find your poratable libreoffice install. What we need is soffice.exe, usually at $sofficePath")
        $env:PATH = "$(Split-Path $sofficePath);$env:PATH"
    }
    return $sofficePath
}