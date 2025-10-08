using namespace System.Text.RegularExpressions

# <img|embed|a|iframe|source|video|audio ...>
$Script:RxTag = [Regex]::new(@'
<(img|embed|a|iframe|source|video|audio)\b(?<attrs>[^>]*)>
'@,
  [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline
)

# src|href|data|poster="..."/'...'
$Script:RxAttr = [Regex]::new(@'
\b(?<name>src|href|data|poster)\s*=\s*(?<q>["'])(?<val>.*?)\k<q>
'@,
  [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline
)

# style="...url(...)"    (first grab the whole style attr)
$Script:RxStyleAttr = [Regex]::new(@'
\bstyle\s*=\s*(["'])(?<style>.*?)\1
'@,
  [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline
)

# url(...) inside a style string
$Script:RxCssUrl = [Regex]::new(@'
url\(\s*(["']?)(?<u>[^)"']+)\1\s*\)
'@,
  [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline
)
function Get-NormalizedTitle {
  param([string]$s)
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  $s = [System.Web.HttpUtility]::HtmlDecode($s)
  $s = $s -replace '\s+', ' '
  $s = $s.Trim()
  $s.ToLowerInvariant()
}

function Rewrite-DocLinks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Html,
    [Parameter(Mandatory)][scriptblock]$ImageResolver, # param([string]$src,[hashtable]$ctx)->[string] or $null
    [Parameter(Mandatory)][scriptblock]$LinkResolver,  # param([string]$href,[hashtable]$ctx)->[string] or $null
    [hashtable]$Context = @{}
  )

  $rewrites  = New-Object System.Collections.Generic.List[object]
  $unresolved = New-Object System.Collections.Generic.List[object]

  $html1 = $Script:RxTag.Replace($Html, {
    param([Match]$m)
    $tagName = $m.Groups[1].Value.ToLowerInvariant()
    $attrs   = $m.Groups['attrs'].Value

    $newAttrs = $Script:RxAttr.Replace($attrs, {
      param([Match]$ma)
      $name = $ma.Groups['name'].Value.ToLowerInvariant()
      $q    = $ma.Groups['q'].Value
      $val  = $ma.Groups['val'].Value

      $newVal = if ($name -eq 'href') { & $LinkResolver $val $Context } else { & $ImageResolver $val $Context }

      if ($newVal -and $newVal -ne $val) {
        $rewrites.Add([pscustomobject]@{ Tag=$tagName; Attr=$name; From=$val; To=$newVal }) | Out-Null
        return "$name=$q$newVal$q"
      } else {
        if (-not $newVal) { $unresolved.Add([pscustomobject]@{ Tag=$tagName; Attr=$name; Value=$val }) | Out-Null }
        return $ma.Value
      }
    })
    "<$tagName$newAttrs>"
  })

  $html2 = $Script:RxStyleAttr.Replace($html1, {
    param([Match]$m)
    $q     = $m.Groups[1].Value
    $style = $m.Groups['style'].Value

    $newStyle = $Script:RxCssUrl.Replace($style, {
      param([Match]$mu)
      $u    = $mu.Groups['u'].Value
      $newU = & $ImageResolver $u $Context
      if ($newU -and $newU -ne $u) {
        $rewrites.Add([pscustomobject]@{ Tag='style'; Attr='url'; From=$u; To=$newU }) | Out-Null
        return "url($newU)"
      } else {
        if (-not $newU) { $unresolved.Add([pscustomobject]@{ Tag='style'; Attr='url'; Value=$u }) | Out-Null }
        return $mu.Value
      }
    })
    " style=$q$newStyle$q"
  })

  [pscustomobject]@{
    Html       = $html2
    Rewrites   = $rewrites
    Unresolved = $unresolved
  }
}

function Get-SimilaritySafe { param([string]$A,[string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return 0.0 }
    Get-Similarity $A $B
}

function As-HtmlString {
  param($Value)
  if ($Value -is [string]) { return $Value }
  if ($Value -is [System.Array]) {
    # keep only strings; drop non-strings like {}
    return (($Value | Where-Object { $_ -is [string] }) -join '')
  }
  return [string]$Value
}
function Normalize-Text {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $s = $s.Trim().ToLowerInvariant()
    $s = [regex]::Replace($s, '[\s_-]+', ' ')  # "primary_email" -> "primary email"
    # strip diacritics (prénom -> prenom)
    $formD = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()){
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne
            [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    ($sb.ToString()).Normalize([System.Text.NormalizationForm]::FormC)
}
function Test-Equiv {
    param([string]$A, [string]$B)
    $a = Normalize-Text $A; $b = Normalize-Text $B
    if (-not $a -or -not $b) { return $false }
    if ($a -eq $b) { return $true }
    $reA = "(^| )$([regex]::Escape($a))( |$)"
    $reB = "(^| )$([regex]::Escape($b))( |$)"
    if ($b -match $reA -or $a -match $reB) { return $true } 
    if ($a.Replace(' ', '') -eq $b.Replace(' ', '')) { return $true }
    return $false
}
function Get-Similarity {
    param([string]$A, [string]$B)

    $a = [string](Normalize-Text $A)
    $b = [string](Normalize-Text $B)
    if ([string]::IsNullOrEmpty($a) -and [string]::IsNullOrEmpty($b)) { return 1.0 }
    if ([string]::IsNullOrEmpty($a) -or  [string]::IsNullOrEmpty($b))  { return 0.0 }

    $n = [int]$a.Length
    $m = [int]$b.Length
    if ($n -eq 0) { return [double]($m -eq 0) }
    if ($m -eq 0) { return 0.0 }

    $d = New-Object 'int[,]' ($n+1), ($m+1)
    for ($i = 0; $i -le $n; $i++) { $d[$i,0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0,$j] = $j }

    for ($i = 1; $i -le $n; $i++) {
        $im1 = ([int]$i) - 1
        $ai  = $a[$im1]
        for ($j = 1; $j -le $m; $j++) {
            $jm1 = ([int]$j) - 1
            $cost = if ($ai -eq $b[$jm1]) { 0 } else { 1 }

            $del = [int]$d[$i,  $j]   + 1
            $ins = [int]$d[$i,  $jm1] + 1
            $sub = [int]$d[$im1,$jm1] + $cost

            $d[$i,$j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }
    }

    $dist   = [double]$d[$n,$m]
    $maxLen = [double][Math]::Max($n,$m)
    return 1.0 - ($dist / $maxLen)
}
function Normalize-KeyForLookup {
  param(
    [Parameter(Mandatory)][string]$Raw,
    [string]$BaseUrl
  )
  if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }

  # protocol-relative //host/path → https:
  $r = $Raw -replace '^(?i)//','https://'

  try {
    $uri = if ($r -match '^(?i)https?://') { [Uri]$r } elseif ($BaseUrl) { [Uri]::new([Uri]$BaseUrl,$r) }
    if ($uri) {
      $b = [UriBuilder]$uri
      $b.Fragment = $null
      $b.Query    = $null
      return $b.Uri.AbsoluteUri
    }
  } catch {}

  # Fallback for non-URL strings: strip ? and # directly
  return ($Raw -split '[?#]',2)[0]
}

function Get-ReplacementUrl {
  param(
    [string]$RawUrl,
    [string]$BaseUrl,
    [hashtable]$Lookup,
    [string]$FallbackLocalPath
  )
  $absNoQ = Normalize-KeyForLookup -Raw $RawUrl -BaseUrl $BaseUrl
  if ($absNoQ -and $Lookup.ContainsKey($absNoQ)) { return $Lookup[$absNoQ] }

  $fname = if ($absNoQ) {
    [IO.Path]::GetFileName(([Uri]$absNoQ).AbsolutePath)
  } else {
    [IO.Path]::GetFileName(($RawUrl -split '[?#]',2)[0])
  }
  if ($fname -and $Lookup.ContainsKey($fname)) { return $Lookup[$fname] }

  if ($FallbackLocalPath) {
    $lfn = [IO.Path]::GetFileName($FallbackLocalPath)
    if ($lfn -and $Lookup.ContainsKey($lfn)) { return $Lookup[$lfn] }
  }
  return $null
}

# Build maps for a single $doc
function New-DocImageMap {
  param([Parameter(Mandatory)][object[]]$HuduImages)
  $map = @{}
  foreach ($h in $HuduImages) {
    $orig = [string](Split-Path -Leaf $h.OriginalFilename)
    $url  = $h.UsingImage.url ?? $h.UsingImage.public_url ?? $h.UsingImage.file_url ?? $h.UsingImage.cdn_url
    if ($orig -and $url) { $map[$orig] = $url }
  }
  $map
}

function New-DocArticleMap {
  param(
    [Parameter(Mandatory)][object[]]$SplitDocs,  # each has Title, HuduArticle
    [string]$HuduBaseUrl
  )
  $map = @{}
  foreach ($sd in $SplitDocs) {
    $url = $sd.HuduArticle.url
    if (-not $url) { continue }
    $t    = [string]$sd.Title
    $norm = Get-NormalizedTitle $t
    $slug = Get-TitleSlug $t
    $keys = @($t, $norm, $slug) | Where-Object { $_ }
    foreach ($k in $keys) { if (-not $map.ContainsKey($k)) { $map[$k] = $url } }
  }
  $map
}
function Get-NormalizedTitle {
  param([string]$s)
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  $s = [System.Web.HttpUtility]::HtmlDecode($s)
  $s = $s -replace '\s+', ' '
  $s = $s.Trim()
  $s.ToLowerInvariant()
}

function Get-TitleSlug {
  param([string]$s)
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  ($s -replace '[^\p{L}\p{Nd}]+','-').Trim('-').ToLowerInvariant()
}
function Rewrite-DocLinks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position=0)][string]$Html,
    [Parameter(Mandatory)][scriptblock]$ImageResolver, # param([string]$src,[hashtable]$ctx) -> [string] or $null
    [Parameter(Mandatory)][scriptblock]$LinkResolver,  # param([string]$href,[hashtable]$ctx) -> [string] or $null
    [hashtable]$Context = @{}
  )

  $rewrites  = New-Object System.Collections.Generic.List[object]
  $unresolved = New-Object System.Collections.Generic.List[object]

  # 1) tag attributes (src/href/data/poster)
  $html1 = $Script:RxTag.Replace($Html, {
    param([Match]$m)

    $tagName = $m.Groups[1].Value.ToLowerInvariant()
    $attrs   = $m.Groups['attrs'].Value

    $newAttrs = $Script:RxAttr.Replace($attrs, {
      param([Match]$ma)
      $name = $ma.Groups['name'].Value.ToLowerInvariant()
      $q    = $ma.Groups['q'].Value
      $val  = $ma.Groups['val'].Value

      $newVal = $null
      switch ($name) {
        'href' { $newVal = & $LinkResolver  $val $Context }
        default { $newVal = & $ImageResolver $val $Context } # src/data/poster
      }

      if ($newVal -and $newVal -ne $val) {
        $rewrites.Add([pscustomobject]@{ Tag=$tagName; Attr=$name; From=$val; To=$newVal }) | Out-Null
        return "$name=$q$newVal$q"
      } else {
        if (-not $newVal) { $unresolved.Add([pscustomobject]@{ Tag=$tagName; Attr=$name; Value=$val }) | Out-Null }
        return $ma.Value
      }
    })

    "<$tagName$newAttrs>"
  })

  # 2) inline style url(...) occurrences
  $html2 = $Script:RxStyleAttr.Replace($html1, {
    param([Match]$m)
    $q     = $m.Groups[1].Value
    $style = $m.Groups['style'].Value

    $newStyle = $Script:RxCssUrl.Replace($style, {
      param([Match]$mu)
      $u    = $mu.Groups['u'].Value
      $newU = & $ImageResolver $u $Context
      if ($newU -and $newU -ne $u) {
        $rewrites.Add([pscustomobject]@{ Tag='style'; Attr='url'; From=$u; To=$newU }) | Out-Null
        return "url($newU)"
      } else {
        if (-not $newU) { $unresolved.Add([pscustomobject]@{ Tag='style'; Attr='url'; Value=$u }) | Out-Null }
        return $mu.Value
      }
    })

    " style=$q$newStyle$q"
  })

  [pscustomobject]@{
    Html       = $html2
    Rewrites   = $rewrites
    Unresolved = $unresolved
  }
}

function Get-LinksFromHTML {
    param (
        [string]$htmlContent,
        [string]$title,
        [bool]$includeImages = $true,
        [bool]$suppressOutput = $false

    )

    $allLinks = @()

    # Match all href attributes inside anchor tags
    $hrefPattern = '<a\s[^>]*?href=["'']([^"'']+)["'']'
    $hrefMatches = [regex]::Matches($htmlContent, $hrefPattern, 'IgnoreCase')
    foreach ($match in $hrefMatches) { 
        $allLinks += $match.Groups[1].Value
    }

    if ($includeImages) {
        # Match all src attributes inside img tags
        $srcPattern = '<img\s[^>]*?src=["'']([^"'']+)["'']'
        $srcMatches = [regex]::Matches($htmlContent, $srcPattern, 'IgnoreCase')
        foreach ($match in $srcMatches) {
            $allLinks += $match.Groups[1].Value
        }
    }
    if ($false -eq $suppressOutput){
        $linkidx=0
        foreach ($link in $allLinks) {
            $linkidx=$linkidx+1
            Set-PrintAndLog -message "link $linkidx of $($allLinks.count) total found for $title - $link" -Color Blue
        }
    }

    return $allLinks | Sort-Object -Unique
}
function Resolve-AbsoluteUrl {
  param([string]$Url, [string]$BaseUrl)
  if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
  $u = $Url.Trim()
  if ($u -match '^(?i)(data:|about:blank|javascript:|#)') { return $null }
  if ($u -match '^(?i)//') { $u = 'https:' + $u }
  try {
    $abs = if ($BaseUrl) { [Uri]::new([Uri]$BaseUrl, $u) } else { [Uri]$u }
    if (-not $abs.IsAbsoluteUri) { return $null }
    $b = [UriBuilder]$abs; $b.Fragment = $null
    # $b.Query = $null  # uncomment if queries should be ignored for matching
    $b.Uri.AbsoluteUri
  } catch { $null }
}

function Rewrite-SrcSet {
  param([string]$SrcSet, [hashtable]$Lookup)
  if ([string]::IsNullOrWhiteSpace($SrcSet)) { return $SrcSet }
  ($SrcSet -split '\s*,\s*' | ForEach-Object {
    if ($_ -match '^\s*(\S+)(\s+.+)?$'){
      $u = $Matches[1]; $desc = $Matches[2]
      $keyName = [IO.Path]::GetFileName($u)
      $rep = $Lookup[$u] ?? $Lookup[$keyName]
      if ($rep) { "$rep$desc" } else { $_ }
    } else { $_ }
  }) -join ', '
}

function Get-ReplacementUrl {
  param(
    [string]$RawUrl,            # src / href as found
    [string]$BaseUrl,           # page/base for relative resolution
    [hashtable]$Lookup,         # keys: absolute urls and/or filenames; values: replacement urls
    [string]$FallbackLocalPath  # optional: absolute file path on disk to derive filename
  )
  # try absolute url
  $abs = Resolve-AbsoluteUrl $RawUrl $BaseUrl
  if ($abs -and $Lookup.ContainsKey($abs)) { return $Lookup[$abs] }

  # try filename from URL
  $nameFromUrl = if ($abs) { [IO.Path]::GetFileName(([Uri]$abs).AbsolutePath) } else { [IO.Path]::GetFileName($RawUrl) }
  if ($nameFromUrl -and $Lookup.ContainsKey($nameFromUrl)) { return $Lookup[$nameFromUrl] }

  # try filename from local path (e.g., after you resolved a thumbnail/full path on disk)
  if ($FallbackLocalPath) {
    $nameFromPath = [IO.Path]::GetFileName($FallbackLocalPath)
    if ($nameFromPath -and $Lookup.ContainsKey($nameFromPath)) { return $Lookup[$nameFromPath] }
  }

  $null
}

function Rewrite-InlineLinksAndImages {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$InFile,
    [string]$BaseUrl,
    [Parameter(Mandatory)][hashtable]$Lookup,
    [string]$OnlyIfHostMatches = 'itboost',  # treat relatives as internal; absolutes must match this
    [switch]$KeepOriginals
  )

  # --- helpers (URL normalize, srcset, etc.) --------------------------------
  function _NormalizeUrl {
    param([Parameter(Mandatory)][string]$Raw,[string]$Base)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $r = $Raw -replace '^(?i)//','https://'
    try {
      $uri = if ($r -match '^(?i)https?://') { [Uri]$r } elseif ($Base) { [Uri]::new([Uri]$Base,$r) }
      if ($uri) {
        $b = [UriBuilder]$uri; $b.Query=$null; $b.Fragment=$null
        return $b.Uri.AbsoluteUri
      }
    } catch {}
    ($Raw -split '[?#]',2)[0]
  }
  function _Eligible {
    param([string]$Raw,[string]$Base,[string]$Needle)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $false }
    if ($Raw -match '^(?i)(data:|javascript:|mailto:|tel:|#)') { return $false }
    $r = $Raw -replace '^(?i)//','https://'
    if ($r -match '^(?i)https?://') { return ($r -match $Needle) }
    return $true  # relative = internal
  }
  function _FindReplacement {
    param([string]$RawUrl,[string]$Base,[hashtable]$Map,[string]$LocalPath)
    $k = _NormalizeUrl -Raw $RawUrl -Base $Base
    if ($k -and $Map.ContainsKey($k)) { return $Map[$k] }
    $fn = if ($k) { [IO.Path]::GetFileName(([Uri]$k).AbsolutePath) } else { [IO.Path]::GetFileName(($RawUrl -split '[?#]',2)[0]) }
    if ($fn -and $Map.ContainsKey($fn)) { return $Map[$fn] }
    if ($LocalPath) {
      $lfn = [IO.Path]::GetFileName($LocalPath)
      if ($lfn -and $Map.ContainsKey($lfn)) { return $Map[$lfn] }
    }
    $null
  }
  function _RewriteSrcSet {
    param([string]$SrcSet,[hashtable]$Map,[string]$Base)
    if ([string]::IsNullOrWhiteSpace($SrcSet)) { return $SrcSet }
    ($SrcSet -split '\s*,\s*' | ForEach-Object {
      if ($_ -match '^\s*(\S+)(\s+.+)?$') {
        $u=$Matches[1]; $d=$Matches[2]
        $k  = _NormalizeUrl -Raw $u -Base $Base
        $fn = [IO.Path]::GetFileName(($k ?? $u))
        $rep = $Map[$k] ?? $Map[$fn]
        if ($rep) { "$rep$d" } else { $_ }
      } else { $_ }
    }) -join ', '
  }

  # --- read HTML as string ---
  $html = Get-Content -LiteralPath $InFile -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($html)) { return $html }
  $html = [regex]::Replace($html, '\xa0+', ' ')

  # --- try COM (mshtml) first ------------------------------------------------
  $doc = $null
  try {
    $doc = New-Object -ComObject 'HTMLFile'
    $doc.Open()
    try {
      # 1) direct
      $doc.write([string[]]@($html))
    } catch {
      # 2) InvokeMember fallback
      [void]$doc.GetType().InvokeMember('write','InvokeMethod',$null,$doc,@([string[]]@($html)))
    }
    $doc.Close()

    # effective base (prefer <base>, else caller’s)
    $baseNode = @($doc.getElementsByTagName('base'))[0]
    $effectiveBase = if ($baseNode -and $baseNode.href) { $baseNode.href } else { $BaseUrl }

    $baseFolder = Split-Path -LiteralPath $InFile

    # IMGs
    foreach ($img in @($doc.getElementsByTagName('img'))) {
      $srcRaw = $img.getAttribute('src'); if (-not (_Eligible $srcRaw $effectiveBase $OnlyIfHostMatches)) { continue }
      $fullRaw = $img.getAttribute('data-src-original')
      # resolve local thumbnail/full (../ handled)
      $localPath = $null
      foreach ($rel in @($fullRaw,$srcRaw)) {
        if ($rel) {
          $p = Join-Path $baseFolder ($rel -replace '/','\')
          try { $p=(Resolve-Path -LiteralPath $p -EA Stop).Path } catch {}
          if (Test-Path -LiteralPath $p) { $localPath = (Get-Item -LiteralPath $p).FullName; break }
        }
      }
      $rep = _FindReplacement -RawUrl $srcRaw -Base $effectiveBase -Map $Lookup -LocalPath $localPath
      if ($rep) {
        if ($KeepOriginals) { $img.setAttribute('data-original-src', $srcRaw) }
        $img.setAttribute('src', $rep)
        $srcset = $img.getAttribute('srcset')
        if ($srcset) {
          $newSet = _RewriteSrcSet -SrcSet $srcset -Map $Lookup -Base $effectiveBase
          if ($newSet -ne $srcset) {
            if ($KeepOriginals) { $img.setAttribute('data-original-srcset', $srcset) }
            $img.setAttribute('srcset', $newSet)
          }
        }
      }
    }

    # Anchors
    foreach ($a in @($doc.getElementsByTagName('a'))) {
      $hrefRaw = $a.getAttribute('href'); if (-not (_Eligible $hrefRaw $effectiveBase $OnlyIfHostMatches)) { continue }
      $rep = _FindReplacement -RawUrl $hrefRaw -Base $effectiveBase -Map $Lookup -LocalPath $null
      if ($rep) {
        if ($KeepOriginals) { $a.setAttribute('data-original-href', $hrefRaw) }
        $a.setAttribute('href', $rep)
        $a.setAttribute('target','_blank'); $a.setAttribute('rel','noopener')
      }
    }

    # output
    $root = @($doc.getElementsByTagName('html'))[0]
    $updated = if ($root) { $root.outerHTML }
               elseif ($doc.body -and $doc.body.parentElement) { $doc.body.parentElement.outerHTML }
               else { $doc.documentElement.outerHTML }
    return $updated
  } catch {
    # --- hard fallback: REGEX-based rewrite (no COM) -------------------------
    # auto-detect base from first absolute “itboost”-ish URL if none provided
    if (-not $BaseUrl) {
      $abs = [regex]::Matches($html, '(?is)\b(?:src|href)\s*=\s*["'']?\s*(?<u>(?:https?:)?//[^"''\s>]+|https?://[^"''\s>]+)') |
             ForEach-Object { $_.Groups['u'].Value -replace '^(?i)//','https://' } |
             Where-Object { $_ -match $OnlyIfHostMatches } |
             Select-Object -First 1
      if ($abs) {
        try {
          $u = [Uri]$abs
          $BaseUrl = "$($u.Scheme)://$($u.Authority)/"
        } catch {}
      }
    }

    # IMG src
$imgSrcPattern = @'
(?is)(<img\b[^>]*\bsrc\s*=\s*["']?)([^"'\s>]+)([^>]*>)
'@    
    $html = [regex]::Replace($html, $imgSrcPattern, {
      param($m)
      $pre = $m.Groups[1].Value; $url = $m.Groups[2].Value; $post = $m.Groups[3].Value
      if (-not (_Eligible $url $BaseUrl $OnlyIfHostMatches)) { return $m.Value }
      $norm = _NormalizeUrl -Raw $url -Base $BaseUrl
      $fn   = [IO.Path]::GetFileName(($norm ?? $url) -split '[?#]',2)[0]
      $rep  = $Lookup[$norm] ?? $Lookup[$fn]
      if ($rep) {
        if ($KeepOriginals) { return "$pre$rep$post".Replace('>', " data-original-src=""$url"">") }
        return "$pre$rep$post"
      }
      $m.Value
    })

    # IMG srcset
$srcsetPat = @'
'(?is)(<img\b[^>]*\bsrcset\s*=\s*["''])([^"']+)(["''])'
'@
    $html = [regex]::Replace($html, $srcsetPat, {
      param($m)
      $pre=$m.Groups[1].Value; $set=$m.Groups[2].Value; $suf=$m.Groups[3].Value
      $new = _RewriteSrcSet -SrcSet $set -Map $Lookup -Base $BaseUrl
      if ($KeepOriginals -and $new -ne $set) { return "$pre$new$suf data-original-srcset=""$set""" }
      "$pre$new$suf"
    })

    # <a href>

$anchorpat = @'
'(?is)(<a\b[^>]*\bhref\s*=\s*["'']?)([^"'\s>]+)([^>]*>)'
'@
    $html = [regex]::Replace($html, $anchorpat, {
      param($m)
      $pre=$m.Groups[1].Value; $url=$m.Groups[2].Value; $post=$m.Groups[3].Value
      if (-not (_Eligible $url $BaseUrl $OnlyIfHostMatches)) { return $m.Value }
      $norm=_NormalizeUrl -Raw $url -Base $BaseUrl
      $fn  = [IO.Path]::GetFileName(($norm ?? $url) -split '[?#]',2)[0]
      $rep = $Lookup[$norm] ?? $Lookup[$fn]
      if ($rep) {
        $postFixed = if ($post -notmatch '(?i)\btarget=') { $post -replace '>$',' target="_blank" rel="noopener">' } else { $post }
        if ($KeepOriginals) { return "$pre$rep$postFixed".Replace('>', " data-original-href=""$url"">") }
        return "$pre$rep$postFixed"
      }
      $m.Value
    })

    return $html
  } finally {
    if ($doc -ne $null) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($doc) } catch {} }
  }
}