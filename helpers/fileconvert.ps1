function Normalize-TitleText([string]$s) {
  if ($null -eq $s) { return $null }
  $s = $s -replace '&#160;|&nbsp;', ' '
  $s = $s -replace '&gt;', '>' -replace '&lt;', '<' -replace '&amp;', '&'
  $s = $s -replace '&quot;','"' -replace '&#34;','"' -replace '&#39;',"'" 
  $s = $s -replace "[\u00A0\u2007\u202F]", ' '
  $s = $s -replace "[\uFEFF\u200B\u200C\u200D\u2060]", ''
  ($s -replace '\s+', ' ').Trim()
}
function Strip-TrailingPageNumber([string]$block){
  [regex]::Replace($block, '(?is)\s*<p[^>]*>\s*\d+(\.\d+)*\s*</p>\s*$', '')
}
function Strip-Footer([string]$block, [string]$company){
  if (-not $company) { return $block }
  $co = [regex]::Escape($company)
  [regex]::Replace($block, "(?is)\s*<p[^>]*>[^<]*\|\s*$co\s*</p>\s*$", '')
}
function Strip-TagsInner([string]$s) {
  if ($null -eq $s) { return $null }
  ([regex]::Replace($s, '(?is)<[^>]+>', '') -replace '\s+',' ').Trim()
}  
function Strip-Tags([string]$s) {
  if ($null -eq $s) { return $null }
  ($s -replace '(?is)<[^>]+>', '')
}  
$rxPage   = [regex]'(?is)<div[^>]*\bclass\s*=\s*([''"])page\1[^>]*>(?<content>.*?)</div>'
$rxNum    = [regex]'^\s*\d+(\.\d+)*\s*$'
$rxFooter = [regex]'(?is)<p[^>]*>[^<]*\|\s*(?<co>[^<]+)\s*</p>\s*$'

$rxArticleStart = [regex]'(?isx)
<hr\s*/?>\s*
<a\s+name\s*=\s*(?<anchor>\d+)\s*></a>\s*
<a\s+href\s*=\s*["''][^"'']*#(?<toc>\d+)["''][^>]*>\s*Articles(?:&#160;|&nbsp;|\s)*</a>
\s*(?<title>.*?)\s*<br\s*/?>\s*
(?<idx>1\.\d{1,4}(?:\.\d{1,4})?)\s*<br\s*/?>
'
$rxSplit = [regex]::new('(?is)(?<!\w)Articles(?:&#160;|&nbsp;|\s)+(?<title>[^<\r\n]{8,}?)\s*(?:<br\s*/?>\s*|\s{2,})(?<idx>1\.\d{1,4}(?:\.\d{1,4})?)\s*(?:<br\s*/?>|$)')

function Strip-LeadingOutlineMarkerP([string]$pageHtml) {
  # note- seperate tag stripping from marker detection, since some exports have the marker inside the first <p> while others have it outside

  while ($true) {
    $m = [regex]::Match($pageHtml, '(?is)^\s*(?<p><p\b[^>]*>.*?</p>)\s*(?<rest>.*)$')
    if (-not $m.Success) { break }

    $pInner = [regex]::Replace($m.Groups['p'].Value, '(?is)^<p\b[^>]*>|</p>$', '')
    $pText  = Normalize-TitleText (Strip-TagsInner $pInner)

    $isMarkerOnly =
      $pText -match '^(?i)\s*\d{1,3}(?:\.\d+)*[a-z]?\s*\.?\s*$' -or
      $pText -match '^(?i)\s*[ivxlcdm]{1,8}\s*\.?\s*$' -or
      $pText -match '^(?i)\s*[a-z]\s*\.?\s*$'

    if ($isMarkerOnly) {
      $pageHtml = $m.Groups['rest'].Value
      continue
    }
    break
  }
  $pageHtml
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
function Get-Ps([string]$block){
    $rxPTxt   = [regex]'(?is)<p[^>]*>(?<t>.*?)</p>'
  ($rxPTxt.Matches($block) | ForEach-Object { $_.Groups['t'].Value.Trim() })
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
  $raw = [IO.File]::ReadAllText($Path)
  $matches = $rxArticleStart.Matches($raw)

  if ($matches.Count -eq 0) {
    if ($AsObjects -or $AsHtml) { return @() } else { return '[]' }
  }

  $articles = New-Object System.Collections.Generic.List[object]

  for ($i = 0; $i -lt $matches.Count; $i++) {
    $m = $matches[$i]

    # Chunk bounds: from this header to right before the next header
    $chunkStart = $m.Index
    $chunkEnd   = if ($i -lt $matches.Count - 1) { $matches[$i+1].Index } else { $raw.Length }

    $bodyStart = $m.Index + $m.Length
    $htmlBody  = $raw.Substring($bodyStart, $chunkEnd - $bodyStart)

    $title = Normalize-TitleText (Strip-Tags $m.Groups['title'].Value)
    $idx   = $m.Groups['idx'].Value

    # remove "Company | Company" + page-number at the end of the chunk
    if ($CompanyOverride) {
      $co = [regex]::Escape($CompanyOverride)
      $htmlBody = [regex]::Replace($htmlBody, "(?is)\s*$co\s*\|\s*$co\s*<br/>\s*\d+\s*<br/>\s*$", '')
    }

    $articles.Add([pscustomobject]@{
      Company = $CompanyOverride
      Title   = "Articles $title"
      Index   = $idx
      Html    = $htmlBody.Trim()
      Anchor  = $m.Groups['anchor'].Value
      Toc     = $m.Groups['toc'].Value
    })
  }

  # If the first article is a 'Preface' and you don't want it, drop it:
  if ($AsObjects) { return $articles }
  elseif ($AsHtml) {
    return ($articles | ForEach-Object { "<!-- $($_.Company) | $($_.Title) -->`n$($_.Html)" }) -join "`n`n"
  }
  else {
    return ($articles | ConvertTo-Json -Depth 10)
  }
}

function Merge-NonArticleSplits {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [object[]]$Articles,

    [string]$Company
  )

  # Always construct regex objects (can't be $null)
  $rxGoodTitle = [regex]::new('(?i)^\s*articles?\b')

  $coEsc = if ([string]::IsNullOrWhiteSpace($Company)) { '' } else { [regex]::Escape($Company) }

  # Bad "titles" that should be merged into previous
$alts = @(
  'articles\s*$'
  'additional\ (?:information|resources)'
  'not\ applicable'
  'n/?a'
  '(?:\d{1,3}|[a-z]|[ivxlcdm]{1,8})\.\s+'
  '\*important:'
)

if ($coEsc) {
  $alts += "$coEsc\s*\|\s*$coEsc\s*"
}

$badPattern = '(?ix)^\s*(?:' + ($alts -join '|') + ')\s*$'
$rxBadTitle = [regex]::new($badPattern)

  $merged = New-Object System.Collections.Generic.List[object]
  $prev = $null

  foreach ($a in $Articles) {
    # safely extract title
    $t = ''
    if ($null -ne $a -and ($a.PSObject.Properties.Name -contains 'Title')) {
      $t = [string]$a.Title
    }

    $isGood = $false
    if (-not [string]::IsNullOrWhiteSpace($t)) {
      $isGood = ($t -match '^(?i)\s*articles?\b') -and ($t -notmatch $badPattern)
    }

    if ($isGood -or -not $prev) {
      $merged.Add($a)
      $prev = $a
      continue
    }
    if ($null -eq $rxGoodTitle) { throw "rxGoodTitle is null (scope/init issue)" }
if ($null -eq $rxBadTitle)  { throw "rxBadTitle is null (pattern/init issue)" }

    # merge body/html into previous
    $htmlToAdd = $null
    if ($a.PSObject.Properties.Name -contains 'Html') {
      $htmlToAdd = [string]$a.Html
    } elseif ($a.PSObject.Properties.Name -contains 'Text') {
      $htmlToAdd = [string]$a.Text
    }

    if (-not [string]::IsNullOrWhiteSpace($htmlToAdd)) {
      $prev.Html = ([string]$prev.Html) + "`n" + $htmlToAdd
    }
  }

  ,$merged.ToArray()
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

