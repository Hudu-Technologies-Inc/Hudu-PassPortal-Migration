
function Get-PassportalAuthToken {
    param (
        [string]$scope = 'docs_api',
        [string]$presharedSecret = "aUa&&XUQBJXz2x&"
    )
    $SHAObject = New-Object System.Security.Cryptography.HMACSHA256
    $SHAObject.key = [Text.Encoding]::ASCII.GetBytes($passportalData.APIkeyId)
    $signature = $SHAObject.ComputeHash([Text.Encoding]::ASCII.GetBytes($PresharedSecret))
    $StringifiedHash = [System.BitConverter]::ToString($signature).Replace('-', '').ToLower()
    $response = Invoke-RestMethod -Headers @{'X-KEY'  = $passportalData.APIkey; 'X-HASH' = $StringifiedHash} `
                -Uri "https://$($selectedLocation.APIBase).passportalmsp.com/api/v2/auth/client_token" -Method POST `
                -Body @{'content' = $PresharedSecret; 'scope'   = "$scope"} `
                -ContentType "application/x-www-form-urlencoded"
    Set-PrintAndLog -message "Authentication Result $(if ($response -and $response.success -and $true -eq $response.success) {'Successful'} else {'Failure'})"  -Color DarkBlue

    return @{
        token   = $response.access_token
        refresh_token = $response.refresh_token
        headers = @{ 'x-access-token' = $response.access_token }
    }
}

function ConvertTo-QueryString {
    param (
        [Parameter(Mandatory)]
        [hashtable]$QueryParams
    )

    return ($QueryParams.GetEnumerator() | ForEach-Object {
        "$([uri]::EscapeDataString($_.Key))=$([uri]::EscapeDataString($_.Value))"
    }) -join '&'
}

function Get-PassportalObjects {
    param (
        [Parameter(Mandatory)][string]$resource
    )

    $uri = "$($passportalData.BaseURL)api/v2/$resource"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $passportalData.Headers
        return $response
    } catch {
        # Write-Warning "Error fetching $uri $($_.Exception.Message)"
        return $null
    }
}

function Test-CSVHasHeader {
    param([string]$Path, [string[]]$ExpectedCols)
    $first = (Get-Content -Path $Path -TotalCount 1) -replace '^\uFEFF',''  # strip BOM
    # case-insensitive check that at least one of expected columns is present
    foreach ($col in $ExpectedCols) {
        if ($first -match [regex]::Escape($col)) { return $true }
    }
    return $false
}
function Get-CSVExportData {
    param(
        [Parameter(Mandatory)][string]$exportsFolder
    )

    Set-PrintAndLog -message "Checking $exportsFolder for Passportal exports..." -Color DarkBlue

    $csvData = [ordered]@{
        clients   = @()
        passwords = @()
        users     = @()
        vault     = @()
    }

    Get-ChildItem -Path $exportsFolder -Filter '*.csv' -File | Sort-Object Name | ForEach-Object {
        $fullPath = $_.FullName
        Set-PrintAndLog -message "Importing: $($_.Name)" -Color DarkBlue

        switch -Wildcard ($_.Name.ToLower()) {
            '*client*.csv' {
                $expected = @('Passportal ID','Client Name','Phone','Email')
                $hasHeader = Test-CSVHasHeader -Path $fullPath -ExpectedCols $expected
                $csv = if ($hasHeader) {
                    Import-Csv -Path $fullPath
                } else {
                    Import-Csv -Path $fullPath -Header $expected
                }
                $csvData.clients = $csv
            }
            '*password*.csv' {
                $expected = @('Passportal ID (BLANK)','Credential','Username','Password','Description','Expires (Yes/No)','Notes','URL','Folder(Optional)','TOTP Secret')
                $hasHeader = Test-CSVHasHeader -Path $fullPath -ExpectedCols $expected
                $csv = if ($hasHeader) {
                    Import-Csv -Path $fullPath
                } else {
                    Import-Csv -Path $fullPath -Header $expected
                }
                $csvData.passwords = $csv
            }
            '*user*.csv' {
                $expected = @('Passportal ID (BLANK)','Last Name','First Name','Email','Phone')
                $hasHeader = Test-CSVHasHeader -Path $fullPath -ExpectedCols $expected
                $csv = if ($hasHeader) {
                    Import-Csv -Path $fullPath
                } else {
                    Import-Csv -Path $fullPath -Header $expected
                }
                $csvData.users = $csv
            }
            '*vault*.csv' {
                $expected = @('Passportal ID (BLANK)','Credential','Username','Password','Description','Expires (Yes/No)','Notes','URL','Folder(Optional)','TOTP Secret')
                $hasHeader = Test-CSVHasHeader -Path $fullPath -ExpectedCols $expected
                $csv = if ($hasHeader) {
                    Import-Csv -Path $fullPath
                } else {
                    Import-Csv -Path $fullPath -Header $expected
                }
                $csvData.vault = $csv
            }
            Default {
                Set-PrintAndLog -message "Skipping unknown CSV: $($_.Name)" -Color DarkYellow
            }
        }
    }

    return $csvData
}

function Get-PPPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ("$key" -ieq $Name) { return $Object[$key] }
        }
        return $null
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Test-PPProperty {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ("$key" -ieq $Name) { return $true }
        }
        return $false
    }

    return $null -ne $Object.PSObject.Properties[$Name]
}

function ConvertTo-PassportalLookupKey {
    param(
        [AllowNull()]$Text
    )

    if ($null -eq $Text) { return "" }
    if (-not $script:PassportalLookupKeyCache) { $script:PassportalLookupKeyCache = @{} }
    $cacheKey = "$Text"
    if ($script:PassportalLookupKeyCache.ContainsKey($cacheKey)) { return $script:PassportalLookupKeyCache[$cacheKey] }

    $s = [System.Net.WebUtility]::HtmlDecode([System.Net.WebUtility]::UrlDecode("$Text"))
    $s = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $s.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }

    $s = $sb.ToString().ToLowerInvariant()
    $s = $s -replace '&', ' and '
    $s = $s -replace '\((?:yyyy|yy|mm|dd|[-/ ]|\d){2,}\)', ' '
    $s = $s -replace '\(s\)', 's'
    $s = $s -replace '[^a-z0-9]+', ' '
    $s = ($s -replace '\s+', ' ').Trim()
    $script:PassportalLookupKeyCache[$cacheKey] = $s
    return $s
}

function Get-PassportalLookupKeys {
    param(
        [AllowNull()]$Text
    )

    $key = ConvertTo-PassportalLookupKey $Text
    if ([string]::IsNullOrWhiteSpace($key)) { return @() }
    if (-not $script:PassportalLookupKeysCache) { $script:PassportalLookupKeysCache = @{} }
    if ($script:PassportalLookupKeysCache.ContainsKey($key)) { return $script:PassportalLookupKeysCache[$key] }

    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @(
        $key
        ($key -replace '\burl\b', 'website')
        ($key -replace '\bwebsite\b', 'url')
        ($key -replace '\bip address(es)?\b', 'ip')
        ($key -replace '\bip addresses\b', 'ip')
        ($key -replace '\bmac address(es)?\b', 'mac address')
        ($key -replace '\bgateways\b', 'gateway')
        ($key -replace '\bservers\b', 'server')
        ($key -replace '\bdomains\b', 'domain')
        ($key -replace '\bcurrent\b', '')
        ($key -replace '\bprimary\b', '')
        ($key -replace '\bdefault\b', '')
    )) {
        $candidate = ($candidate -replace '\s+', ' ').Trim()
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $keys.Contains($candidate)) {
            [void]$keys.Add($candidate)
        }
    }

    $singular = (($key -split '\s+') | ForEach-Object {
        if ($_.Length -gt 3 -and $_.EndsWith('s')) { $_.Substring(0, $_.Length - 1) } else { $_ }
    }) -join ' '
    if (-not [string]::IsNullOrWhiteSpace($singular) -and -not $keys.Contains($singular)) {
        [void]$keys.Add($singular)
    }

    $result = $keys.ToArray()
    $script:PassportalLookupKeysCache[$key] = $result
    return $result
}

function Get-PassportalFieldAliases {
    param(
        [Parameter(Mandatory)][string]$Label
    )

    if (-not $script:PassportalFieldAliases) {
        $script:PassportalFieldAliases = @{
            "Asset Name" = @("Name", "Device Name", "Hostname")
            "Device Name" = @("Name", "Asset Name", "Hostname")
            "Application Name" = @("Name", "Title", "Software", "Software Name")
            "Folder Name" = @("Name", "Share Name", "Path")
            "Share Name" = @("Name", "Folder Name")
            "Software" = @("Software Name", "Application Name", "Name")
            "Software Name" = @("Software", "Application Name", "Name")
            "Primary IP" = @("IP Address", "IP Address(s)", "IP Addresses", "Primary IP Address", "Management IP Address")
            "IP Address" = @("IP Address(s)", "IP Addresses", "Primary IP", "Management IP Address")
            "MAC Address" = @("MAC Address(s)", "Primary MAC Address", "MAC Addresses")
            "Gateway(S)" = @("Gateway", "Default Gateway", "Gateways")
            "DNS Servers" = @("DNS Server(S)", "DNS Server", "DNS")
            "Domain(s)" = @("Domains", "Domain")
            "WebMail URL" = @("Webmail", "Webmail URL", "Portal URL", "URL")
            "Vendor Website" = @("Website", "URL", "Portal URL")
            "Support Email" = @("Support Email Address", "Email")
            "Support Phone Number" = @("Support Phone", "Phone")
            "Backup Description" = @("Backup Job Description", "Description")
            "Backup Interval" = @("Backup Frequency", "Frequency")
            "Local Backup Server(S)" = @("Protected Servers", "Servers", "Local Backup Servers")
            "Next Test Restore Date" = @("Next Restore Verification Date", "Restore Verification Date")
            "Last Successful Backup" = @("Last Backup", "Last Successful Backup Date")
            "License Key(S)" = @("License Key", "License Keys", "Product Key")
            "Renewal Date" = @("Expiration Date", "Expiry Date", "Renew Date")
            "Expiration Date" = @("Expiry Date", "Renewal Date", "Expires")
            "SANs" = @("Subject Alternative Names", "SAN", "Alternative Names")
            "Phone" = @("Phone Number", "Main Number", "Support Phone")
            "Email" = @("Email Address", "Support Email", "Webmail")
            "Notes" = @("Note", "Description", "Details")
            "Details" = @("Notes", "Description")
            "State" = @("Province", "Region")
            "Address 1" = @("Address", "Street Address", "Address Line 1")
            "Address 2" = @("Address Line 2", "Suite", "Unit")
        }
    }

    $out = [System.Collections.Generic.List[string]]::new()
    [void]$out.Add($Label)
    foreach ($key in $script:PassportalFieldAliases.Keys) {
        if ($key -ieq $Label) {
            foreach ($alias in $script:PassportalFieldAliases[$key]) {
                if (-not $out.Contains($alias)) { [void]$out.Add($alias) }
            }
        }
    }

    return $out.ToArray()
}

function Test-PassportalMeaningfulValue {
    param(
        [AllowNull()]$Value
    )

    if ($null -eq $Value) { return $false }
    if ($Value -is [array]) { return @($Value | Where-Object { Test-PassportalMeaningfulValue $_ }).Count -gt 0 }

    $s = "$Value"
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    $s = $s.Trim()
    return $s -notin @(
        "Please Select",
        "Select",
        "-- Select --",
        "None",
        "N/A",
        "NA",
        "Not Applicable",
        "NULL",
        "null"
    )
}

function Resolve-PPValue {
    param(
        $Node,
        [int]$Depth = 0
    )

    if ($null -eq $Node) { return $null }
    if ($Depth -gt 12) {
        try { return ($Node | ConvertTo-Json -Depth 6 -Compress) } catch { return "$Node" }
    }

    if ($Node -is [string]) {
        return ([System.Net.WebUtility]::HtmlDecode($Node) -replace "\r\n?", "`n").Trim()
    }
    if ($Node -is [ValueType]) { return $Node }

    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string] -and $Node -isnot [System.Collections.IDictionary] -and -not (Test-PPProperty -Object $Node -Name 'value')) {
        $values = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Node) {
            $resolved = Resolve-PPValue -Node $item -Depth ($Depth + 1)
            if (Test-PassportalMeaningfulValue $resolved) {
                foreach ($line in @("$resolved" -split "`r?`n")) {
                    $line = $line.Trim()
                    if (Test-PassportalMeaningfulValue $line -and -not $values.Contains($line)) {
                        [void]$values.Add($line)
                    }
                }
            }
        }
        if ($values.Count -gt 0) { return ($values -join "`n") }
        return $null
    }

    $resolvedObject = Get-PPPropertyValue -Object $Node -Name 'resolvedObject'
    if ($null -ne $resolvedObject) {
        $resolved = Resolve-PPValue -Node $resolvedObject -Depth ($Depth + 1)
        if (Test-PassportalMeaningfulValue $resolved) { return $resolved }
    }

    $attribute = Get-PPPropertyValue -Object $Node -Name 'attribute'
    if ($null -ne $attribute) {
        $resolved = Resolve-PPValue -Node $attribute -Depth ($Depth + 1)
        if (Test-PassportalMeaningfulValue $resolved) { return $resolved }
    }

    if (Test-PPProperty -Object $Node -Name 'value') {
        $resolved = Resolve-PPValue -Node (Get-PPPropertyValue -Object $Node -Name 'value') -Depth ($Depth + 1)
        if (Test-PassportalMeaningfulValue $resolved) { return $resolved }
    }

    foreach ($propertyName in @('text', 'name', 'label', 'title', 'displayName', 'id')) {
        if (Test-PPProperty -Object $Node -Name $propertyName) {
            $resolved = Resolve-PPValue -Node (Get-PPPropertyValue -Object $Node -Name $propertyName) -Depth ($Depth + 1)
            if (Test-PassportalMeaningfulValue $resolved) { return $resolved }
        }
    }

    $props = @($Node.PSObject.Properties | Where-Object { $_.MemberType -match 'Property' -and $_.Name -notin @('type') })
    if ($props.Count -eq 1) {
        return Resolve-PPValue -Node $props[0].Value -Depth ($Depth + 1)
    }
    if ($props.Count -gt 1) {
        $hasMeaningfulProperty = $false
        foreach ($prop in $props) {
            $propValue = Resolve-PPValue -Node $prop.Value -Depth ($Depth + 1)
            if (Test-PassportalMeaningfulValue $propValue) {
                $hasMeaningfulProperty = $true
                break
            }
        }
        if (-not $hasMeaningfulProperty) { return $null }
    }

    try { return ($Node | ConvertTo-Json -Depth 8 -Compress) } catch { return "$Node" }
}

function Get-PassportalFieldEntries {
    param(
        [AllowNull()]$ppFields
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $ppFields) { return $entries.ToArray() }

    if (Test-PPProperty -Object $ppFields -Name 'Fields') {
        $nested = Get-PPPropertyValue -Object $ppFields -Name 'Fields'
        foreach ($entry in (Get-PassportalFieldEntries -ppFields $nested)) {
            [void]$entries.Add($entry)
        }
        return $entries.ToArray()
    }

    if ($ppFields -is [System.Collections.IEnumerable] -and $ppFields -isnot [string] -and $ppFields -isnot [System.Collections.IDictionary]) {
        foreach ($item in $ppFields) {
            foreach ($entry in (Get-PassportalFieldEntries -ppFields $item)) {
                [void]$entries.Add($entry)
            }
        }
        return $entries.ToArray()
    }

    $properties = if ($ppFields -is [System.Collections.IDictionary]) {
        $ppFields.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = "$($_.Key)"; Value = $_.Value } }
    } else {
        $ppFields.PSObject.Properties
    }

    foreach ($prop in $properties) {
        if ($prop.Name -ieq 'tags') { continue }
        if ($prop.Name -ieq 'name' -and -not (Test-PPProperty -Object $prop.Value -Name 'value')) { continue }
        if ($null -eq $prop.Value) { continue }

        $innerName = Get-PPPropertyValue -Object $prop.Value -Name 'name'
        $description = Get-PPPropertyValue -Object $prop.Value -Name 'description'
        $label = if (Test-PassportalMeaningfulValue $innerName) { "$innerName" } else { "$($prop.Name)" }

        [void]$entries.Add([pscustomobject]@{
            Key = "$($prop.Name)"
            Label = $label
            Description = $description
            Raw = $prop.Value
        })
    }

    return $entries.ToArray()
}

function Get-PassportalFieldMatchScore {
    param(
        [Parameter(Mandatory)][string]$TargetLabel,
        [Parameter(Mandatory)][string]$SourceLabel
    )

    $target = ConvertTo-PassportalLookupKey $TargetLabel
    $source = ConvertTo-PassportalLookupKey $SourceLabel
    if ([string]::IsNullOrWhiteSpace($target) -or [string]::IsNullOrWhiteSpace($source)) { return 0 }
    if (-not $script:PassportalMatchScoreCache) { $script:PassportalMatchScoreCache = @{} }
    $cacheKey = "$target|$source"
    if ($script:PassportalMatchScoreCache.ContainsKey($cacheKey)) { return $script:PassportalMatchScoreCache[$cacheKey] }
    if ($target -eq $source) { return 100 }

    $targetTokens = @($target -split '\s+' | Where-Object { $_ })
    $sourceTokens = @($source -split '\s+' | Where-Object { $_ })
    if ($targetTokens.Count -eq 0 -or $sourceTokens.Count -eq 0) {
        $script:PassportalMatchScoreCache[$cacheKey] = 0
        return 0
    }

    $targetSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$targetTokens, [System.StringComparer]::OrdinalIgnoreCase)
    $sourceSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$sourceTokens, [System.StringComparer]::OrdinalIgnoreCase)
    $intersection = 0
    foreach ($token in $targetSet) {
        if ($sourceSet.Contains($token)) { $intersection++ }
    }

    if ($intersection -eq 0) {
        $script:PassportalMatchScoreCache[$cacheKey] = 0
        return 0
    }

    $coverage = $intersection / $targetSet.Count
    $subsetBonus = if ($intersection -eq $targetSet.Count) { 20 } else { 0 }
    $score = [int]([Math]::Round(($coverage * 80) + $subsetBonus))
    $script:PassportalMatchScoreCache[$cacheKey] = $score
    return $score
}

function New-PassportalFieldLookup {
    param(
        [AllowNull()]$ppFields
    )

    $entries = @(Get-PassportalFieldEntries -ppFields $ppFields)
    $lookup = @{}
    foreach ($entry in $entries) {
        $value = Resolve-PPValue $entry.Raw
        $entry | Add-Member -NotePropertyName Value -NotePropertyValue $value -Force
        $entry | Add-Member -NotePropertyName IsMeaningful -NotePropertyValue (Test-PassportalMeaningfulValue $value) -Force

        foreach ($label in @($entry.Label, $entry.Key)) {
            foreach ($key in (Get-PassportalLookupKeys $label)) {
                if (-not $lookup.ContainsKey($key)) { $lookup[$key] = [System.Collections.Generic.List[object]]::new() }
                [void]$lookup[$key].Add($entry)
            }
        }
    }

    return @{
        Entries = $entries
        Lookup = $lookup
    }
}

function Find-PassportalFieldEntryInLookup {
    param(
        [Parameter(Mandatory)]$FieldLookup,
        [Parameter(Mandatory)][string[]]$Labels
    )

    $entries = @($FieldLookup.Entries)
    $lookup = $FieldLookup.Lookup
    if ($entries.Count -eq 0) { return $null }

    foreach ($label in $Labels) {
        foreach ($alias in (Get-PassportalFieldAliases -Label $label)) {
            foreach ($key in (Get-PassportalLookupKeys $alias)) {
                if ($lookup.ContainsKey($key)) {
                    foreach ($entry in $lookup[$key]) {
                        if ($entry.IsMeaningful) { return $entry }
                    }
                }
            }
        }
    }

    $best = $null
    $bestScore = 0
    foreach ($entry in $entries) {
        foreach ($label in $Labels) {
            foreach ($alias in (Get-PassportalFieldAliases -Label $label)) {
                $score = Get-PassportalFieldMatchScore -TargetLabel $alias -SourceLabel $entry.Label
                if ($score -gt $bestScore) {
                    $best = $entry
                    $bestScore = $score
                }
            }
        }
    }

    if ($bestScore -ge 65 -and $best.IsMeaningful) { return $best }
    return $null
}

function Find-PassportalFieldEntry {
    param(
        [AllowNull()]$ppFields,
        [Parameter(Mandatory)][string[]]$Labels
    )

    $fieldLookup = New-PassportalFieldLookup -ppFields $ppFields
    return Find-PassportalFieldEntryInLookup -FieldLookup $fieldLookup -Labels $Labels
}

function Find-PassportalFieldValue {
    param(
        [AllowNull()]$ppFields,
        [Parameter(Mandatory)][string[]]$Labels
    )

    $entry = Find-PassportalFieldEntry -ppFields $ppFields -Labels $Labels
    if ($null -eq $entry) { return $null }
    return $entry.Value
}

function Find-PassportalFieldValueInLookup {
    param(
        [Parameter(Mandatory)]$FieldLookup,
        [Parameter(Mandatory)][string[]]$Labels
    )

    $entry = Find-PassportalFieldEntryInLookup -FieldLookup $FieldLookup -Labels $Labels
    if ($null -eq $entry) { return $null }
    return $entry.Value
}

function ConvertTo-HuduAssetFieldValue {
    param(
        [AllowNull()]$Value,
        [string]$FieldType = "Text",
        [string]$FieldLabel
    )

    $resolved = Resolve-PPValue $Value
    if (-not (Test-PassportalMeaningfulValue $resolved)) { return $null }
    $s = "$resolved"
    $s = ($s -replace "\r\n?", "`n").Trim()
    if ($FieldLabel -and (ConvertTo-PassportalLookupKey $s) -eq (ConvertTo-PassportalLookupKey $FieldLabel)) { return $null }

    if ($FieldType -ieq "Date") {
        if ($s -match '^\s*(\d{4})[-/](\d{1,2})[-/](\d{1,2})\s*$') {
            return ("{0:0000}-{1:00}-{2:00}" -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
        }

        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($s, [Globalization.CultureInfo]::GetCultureInfo("en-US"), [Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) {
            return $parsed.ToString("yyyy-MM-dd")
        }
    }

    return $s
}

function Get-PassportalDocumentFields {
    param(
        [AllowNull()]$Detail
    )

    if ($null -eq $Detail) { return @{} }
    $fields = Get-PPPropertyValue -Object $Detail -Name 'Fields'
    if ($null -eq $fields) { $fields = Get-PPPropertyValue -Object $Detail -Name 'details' }
    if ($null -ne $fields -and (Test-PPProperty -Object $fields -Name 'Fields')) {
        $nested = Get-PPPropertyValue -Object $fields -Name 'Fields'
        if ($null -ne $nested) { return $nested }
    }
    if ($null -ne $fields) { return $fields }
    return $Detail
}

function Get-TopLevelFieldforAsset {
    param (
        [Parameter(Mandatory)]
        $data,
        [string]$doctype,
        [int]$layoutId,
        [int]$companyId,
        $fields,
        $fieldLookup
    )

    if ($null -eq $fieldLookup) { $fieldLookup = New-PassportalFieldLookup -ppFields $fields }
    $fieldName = Find-PassportalFieldValueInLookup -FieldLookup $fieldLookup -Labels @("Asset Name", "Name", "Device Name", "Hostname", "Title")
    $name = ConvertTo-HuduAssetFieldValue ($data.label ?? $data.name ?? $fieldName ?? "Unnamed $doctype")
    if (-not (Test-PassportalMeaningfulValue $name)) { $name = "Unnamed $doctype" }

    $props = @{
        AssetLayoutId = $layoutId
        name          = $name
        companyId     = $companyId
    }

    $optionalProps = @(
        @{ name = "PrimaryMail"; labels = @("Webmail", "WebMail URL", "Email", "Email Address", "Support Email", "Support Email Address") }
        @{ name = "PrimaryModel"; labels = @("Model", "Version") }
        @{ name = "PrimaryManufacturer"; labels = @("Manufacturer", "Manufactured", "Manufactured By") }
        @{ name = "PrimarySerial"; labels = @("Serial Number", "Serial") }
    )

    foreach ($prop in $optionalProps) {
        $resolved = ConvertTo-HuduAssetFieldValue (Find-PassportalFieldValueInLookup -FieldLookup $fieldLookup -Labels $prop.labels)
        foreach ($label in $prop.labels) {
            if ($resolved -and (ConvertTo-PassportalLookupKey $resolved) -eq (ConvertTo-PassportalLookupKey $label)) {
                $resolved = $null
                break
            }
        }
        if (Test-PassportalMeaningfulValue $resolved) {
            $props[$prop.name] = $resolved
            Write-Verbose "Found optional asset property $($prop.name) = $resolved"
        }
    }

    return $props
}

function Get-NormalizedPassportalFields {
    param(
        [Parameter(Mandatory)] $ppFields,   # hashtable/psobject: Passportal .Fields bag
        [Parameter(Mandatory)][array]$fieldMap, # Hudu layout fields (with .label)
        [int]$passportalId,
        $fieldLookup
    )

    if ($null -eq $fieldLookup) { $fieldLookup = New-PassportalFieldLookup -ppFields $ppFields }
    $result = @{}
    foreach ($field in $fieldMap) {
        $label = $field.label
        if (-not $label) { continue }
        if ($label -ieq "PassPortalID") { continue }

        $matched = Find-PassportalFieldEntryInLookup -FieldLookup $fieldLookup -Labels @($label)
        if ($matched) {
            $val = ConvertTo-HuduAssetFieldValue -Value $matched.Value -FieldType ($field.field_type ?? "Text") -FieldLabel $label
            if (Test-PassportalMeaningfulValue $val) { $result[$label] = $val }
        }
    }

    if ($null -ne $passportalId -and $passportalId -gt 0) { $result['PassPortalID'] = "$passportalId" }

    return $result
}
