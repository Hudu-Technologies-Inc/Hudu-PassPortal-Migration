
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
            '*clients*.csv' {
                $expected = @('Passportal ID','Client Name','Phone','Email')
                $hasHeader = Test-CSVHasHeader -Path $fullPath -ExpectedCols $expected
                $csv = if ($hasHeader) {
                    Import-Csv -Path $fullPath
                } else {
                    Import-Csv -Path $fullPath -Header $expected
                }
                $csvData.clients = $csv
            }
            '*passwords*.csv' {
                $expected = @('Passportal ID','Client Name','Credential','Username','Password','Description','Expires (Yes/No)','Notes','URL','Folder(Optional)')
                $hasHeader = Test-CSVHasHeader -Path $fullPath -ExpectedCols $expected
                $csv = if ($hasHeader) {
                    Import-Csv -Path $fullPath
                } else {
                    Import-Csv -Path $fullPath -Header $expected
                }
                $csvData.passwords = $csv
            }
            '*users*.csv' {
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
                $expected = @('Passportal ID','Credential','Username','Password','Description','Expires (Yes/No)','Notes','URL','Folder(Optional)')
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


$PassportalLayoutDefaults = @{
    asset           = @{ icon = "fas fa-box";           label = "Assets" }
    active_directory= @{ icon = "fas fa-network-wired"; label = "Active Directory" }
    application     = @{ icon = "fas fa-cubes";         label = "Applications" }
    backup          = @{ icon = "fas fa-database";      label = "Backups" }
    email           = @{ icon = "fas fa-envelope";      label = "Email Accounts" }
    folders         = @{ icon = "fas fa-folder";        label = "Folders" }
    file_sharing    = @{ icon = "fas fa-share-alt";     label = "File Sharing" }
    contact         = @{ icon = "fas fa-id-badge";      label = "Contacts" }
    location        = @{ icon = "fas fa-map-marker-alt";label = "Locations" }
    internet        = @{ icon = "fas fa-globe";         label = "Internet" }
    lan             = @{ icon = "fas fa-ethernet";      label = "LAN Devices" }
    printing        = @{ icon = "fas fa-print";         label = "Printers" }
    remote_access   = @{ icon = "fas fa-desktop";       label = "Remote Access" }
    vendor          = @{ icon = "fas fa-store";         label = "Vendors" }
    virtualization  = @{ icon = "fas fa-server";        label = "Virtualization" }
    voice           = @{ icon = "fas fa-phone";         label = "Voice Systems" }
    wireless        = @{ icon = "fas fa-wifi";          label = "Wireless" }
    licencing       = @{ icon = "fas fa-certificate";   label = "Licencing" }
    custom          = @{ icon = "fas fa-puzzle-piece";  label = "Custom Docs" }
    ssl             = @{ icon = "fas fa-lock";          label = "SSL Certificates" }
}

function Get-PassportalFieldMapForType {
    param (
        [Parameter(Mandatory)]
        [string]$Type
    )

    $fieldMap = @{
        asset = @(
            @{ label="Asset Name"; field_type="Text" },
            @{ label="Assigned User"; field_type="Text" },
            @{ label="Purchased By"; field_type="Text" },
            @{ label="Model"; field_type="Text" },
            @{ label="Serial Number"; field_type="Text" },
            @{ label="Purchase Date"; field_type="Date" },
            @{ label="Type"; field_type="Text" },
            @{ label="Asset Tag"; field_type="Text" },
            @{ label="Hostname"; field_type="Text" },
            @{ label="Platform"; field_type="Text" },
            @{ label="Primary IP"; field_type="Text" },
            @{ label="Hostname"; field_type="Text" },
            @{ label="Operating System"; field_type="Text" },
            @{ label="Operating System Notes"; field_type="RichText" },
            @{ label="Notes"; field_type="RichText" }
        )
        active_directory = @(
            @{ label="AD Full Name"; field_type="Text" },
            @{ label="AD Short Name"; field_type="Text" },
            @{ label="AD Level"; field_type="Text" },
            @{ label="Directory Services Restore Mode Password"; field_type="Password" },
            @{ label="Domain Controller IP"; field_type="Text" }
        )
        application = @(
            @{ label="Application Name"; field_type="Text" },
            @{ label="License Key"; field_type="Text" },
            @{ label="Category"; field_type="Text" },
            @{ label="Version"; field_type="Text" }
            @{ label="NOTES"; field_type="RichText" }
        )
        backup = @(
            @{ label="Backup Technology"; field_type="Text" },
            @{ label="Backup Type"; field_type="Text" },
            @{ label="Backup Description"; field_type="Text" },
            @{ label="Backup Interval"; field_type="Text" },
            @{ label="Backup Window"; field_type="Text" },
            @{ label="Retention Policy"; field_type="Text" },
            @{ label="Notes"; field_type="RichText" },
            @{ label="Last Successful Backup"; field_type="Date" },
            @{ label="Next Test Restore Date"; field_type="Date" }
        )
        email = @(
            @{ label="Email Address"; field_type="Text" },
            @{ label="Email Type"; field_type="Password" },
            @{ label="Domain(s)"; field_type="Text" },
            @{ label="Email Servers"; field_type="Text" },
            @{ label="WebMail URL"; field_type="Text" },
            @{ label="Inbound Delivery"; field_type="Text" },
            @{ label="Notes"; field_type="RichText" }
        )
        folders = @(
            @{ label="Folder Name"; field_type="Text" },
            @{ label="Path"; field_type="Text" },
            @{ label="Permissions"; field_type="RichText" }
        )
        file_sharing = @(
            @{ label="Share Name"; field_type="Text" },
            @{ label="Share Description"; field_type="Text" },
            @{ label="File Servers"; field_type="Text" },
            @{ label="Share UNC Path"; field_type="Text" },
            @{ label="Mapped Drive"; field_type="Text" },
            @{ label="File Share Permissions"; field_type="Text" },
            @{ label="User Accounts"; field_type="RichText" }
        )
        contact = @(
            @{ label="Contact Type"; field_type="Text" },
            @{ label="Primary Contact"; field_type="Text" },
            @{ label="Job Title"; field_type="Text" },
            @{ label="First Name"; field_type="Text" },
            @{ label="Last Name"; field_type="Text" },
            @{ label="Phone"; field_type="Phone" },
            @{ label="Notes"; field_type="RichText" },
            @{ label="Email"; field_type="Text" }
        )
        location = @(
            @{ label="Name"; field_type="Text" },
            @{ label="Address 1"; field_type="Text" },
            @{ label="Address 2"; field_type="Text" },
            @{ label="City"; field_type="Text" },
            @{ label="Country"; field_type="Text" },
            @{ label="State"; field_type="RichText" },
            @{ label="Fax"; field_type="Text" },
            @{ label="Phone"; field_type="Text" }
        )
        internet = @(
            @{ label="ISP"; field_type="Text" },
            @{ label="Account Number"; field_type="Text" },
            @{ label="Static IPs"; field_type="RichText" }
        )
        lan = @(
            @{ label="Device Name"; field_type="Text" },
            @{ label="IP Address"; field_type="Text" },
            @{ label="MAC Address"; field_type="Text" },
            @{ label="Port Number"; field_type="Text" }
        )
        printing = @(
            @{ label="Connection Type"; field_type="Text" },
            @{ label="Print Drivers Path"; field_type="Text" },
            @{ label="Notes"; field_type="RichText" },
            @{ label="Location"; field_type="Text" }
        )
        remote_access = @(
            @{ label="Site"; field_type="Text" },
            @{ label="Client VPN URL"; field_type="Text" },
            @{ label="Client VPN Installer"; field_type="Text" },
            @{ label="Remote Desktop"; field_type="Text" },
            @{ label="Webmail"; field_type="Text" },
            @{ label="Password"; field_type="Password" }
        )
        vendor = @(
            @{ label="Vendor Website"; field_type="Text" },
            @{ label="Vendor Support URL"; field_type="Text" },
            @{ label="Support Phone Number"; field_type="Text" },
            @{ label="Support Email"; field_type="Text" }
        )
        virtualization = @(
            @{ label="Hypervisor"; field_type="Text" },
            @{ label="VM Count"; field_type="Text" },
            @{ label="Primary Host IP"; field_type="Text" }
        )
        voice = @(
            @{ label="Phone System"; field_type="Text" },
            @{ label="SIP Provider"; field_type="Text" },
            @{ label="Main Number"; field_type="Text" }
        )
        wireless = @(
            @{ label="SSID"; field_type="Text" },
            @{ label="Password"; field_type="Password" },
            @{ label="Security Type"; field_type="Text" }
        )
        licencing = @(
            @{ label="Software"; field_type="Text" },
            @{ label="License Key"; field_type="Text" },
            @{ label="Seats"; field_type="Text" },
            @{ label="Renewal Date"; field_type="Date" }
        )
        custom = @(
            @{ label="Title"; field_type="Text" },
            @{ label="Details"; field_type="RichText" }
        )
        ssl = @(
            @{ label="Domain"; field_type="Text" },
            @{ label="Expiration Date"; field_type="Date" },
            @{ label="Issuer"; field_type="Text" },
            @{ label="SANs"; field_type="RichText" }
        )
    }
    $fields = $fieldMap[$Type.ToLower()] ?? @()
    $fields+=@{label="PassPortalID"; field_type="Text"}
    for ($i = 0; $i -lt $fields.Count; $i++) {
        $fields[$i].position = $i + 1
    }
    return $fields
}

function Build-HuduFieldsFromDocument {
    param (
        [Parameter(Mandatory)] [array]$FieldMap,
        [Parameter(Mandatory)] $sourceFields,
        [int]$docId
    )

    Write-Host "Building+Populating Fields for doc $docId"
    if (-not $sourceFields) { Write-Warning "No detail entry found for document ID $docId"; return @{} }

    # Normalize PSCustomObject -> hashtable
    $src = if ($sourceFields -is [System.Collections.IDictionary]) {
        $sourceFields
    } else {
        $h=@{}
        $sourceFields.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
        $h
    }

    $fieldValues = @{}

    foreach ($fieldDef in $FieldMap) {
        $label = $fieldDef.label
        Write-Host $label

        if ($src.ContainsKey($label)) {
            $value = $src[$label]

            # handle nested shapes safely
            $actualValue =
                if ($value -is [System.Collections.IDictionary] -and $value.ContainsKey('value')) {
                    # try value.text, fallback to value
                    if ($value['value'] -is [System.Collections.IDictionary] -and $value['value'].ContainsKey('text')) {
                        $value['value']['text']
                    } else { $value['value'] }
                } else { $value }

            $fieldValues[$label] = $actualValue
        }
    }

    $fieldValues['PassPortalID'] = "$docId"
    return $fieldValues
}


function Get-TopLevelFieldforAsset {
    param (
        [Parameter(Mandatory)]
        $data,
        [string]$doctype,
        [int]$layoutId,
        [int]$companyId,
        [array]$fields
    )   $name = $data.label ?? $obj.data[0].label ?? "Unnamed $doctype"
        $email = $fields.webmail ?? $fields.email ?? $fields.email_address ?? $fields.support_email_address ?? $null
        $mfg = $fields.manufacturer ?? $fields.manufactured ?? $fields.manufactured_by ?? $null
        $model = $fields.model ?? $fields.version ?? $null
        $serial = $fields.serial_number ?? $fields.serial ?? $null
        $props =@{
            AssetLayoutId = $layoutId
            name      = $name
            companyId = $companyId
        }
        $optionalProps = @(
            @{name = "PrimaryMail"; resolved = $email.value.text}
            @{name = "PrimaryModel"; resolved = $mfg.value.text}
            @{name = "PrimaryManufacturer"; resolved = $model.value.text}
            @{name = "PrimarySerial"; resolved = $serial.value.text}
        )

        foreach ($prop in $optionalProps) {
            if ($prop.resolved -and -not $([string]::IsNullOrWhiteSpace($prop.resolved))) {
                $props["$($prop.name)"] = $prop.resolved
                write-host "Found optional asset property $($prop.name) = $($prop.resolved)"
            }
        }
        
    return $props

}

function Coerce-ForHudu {
    param(
        [Parameter(Mandatory)] $FieldDef,   # one item from your field map (label, field_type)
        [Parameter(Mandatory)] $RawValue
    )

    if ($null -eq $RawValue) { return $null }

    $ft = "$($FieldDef.field_type)".ToLower()

    switch -regex ($ft) {
        '^(text|richtext|string)$' { return "$RawValue" }
        '^date$' {
            $dt = $RawValue -as [datetime]
            if ($dt) { return $dt.ToString('MM/dd/yyyy') } else { return "$RawValue" }
        }
        '^(bool|boolean)$' {
            # accept true/false/1/0/yes/no
            if ($RawValue -is [bool]) { return $RawValue }
            $s = "$RawValue".Trim()
            if ($s -match '^(true|yes|y|1)$') { return $true }
            if ($s -match '^(false|no|n|0)$') { return $false }
            return $false
        }
        '^(listselect|select)$' { return "$RawValue" }
        '^(multiselect|listmulti)$' {
            if ($RawValue -is [System.Collections.IEnumerable] -and -not ($RawValue -is [string])) { return @($RawValue) }
            return ($RawValue -split '[;,]') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
        '^(number|int|integer|float|double)$' {
            # try int, then double
            if ($RawValue -as [int]) { return [int]$RawValue }
            if ($RawValue -as [double]) { return [double]$RawValue }
            return "$RawValue"
        }
        default { return $RawValue }
    }
}

function Set-PPToHuduFieldValues {
    <#
      Maps Passportal normalized fields to your Hudu field map (labels/types).
      Returns a hashtable keyed by Hudu *label* -> coerced value.
    #>
    param(
        [Parameter(Mandatory)][array]$FieldMap,      # from Get-PassportalFieldMapForType
        [Parameter(Mandatory)][hashtable]$PPIndex    # from Normalize-PassportalFields
    )

    $out = @{}

    foreach ($f in $FieldMap) {
        $label = $f.label
        $snake = Convert-ToSnakeCase $label

        # candidates: exact snake key, exact human label, exact PP key already snake (e.g. 'backup_type')
        $candidates = @()
        if ($PPIndex.ContainsKey($snake)) { $candidates += $PPIndex[$snake] }
        if ($PPIndex.ContainsKey($label)) { $candidates += $PPIndex[$label] }
        if ($PPIndex.ContainsKey($snake)) { $candidates += $PPIndex[$snake] }

        # loose fallback: find first PP key whose name contains the snake label bits
        if ($candidates.Count -eq 0) {
            $hit = $PPIndex.Keys | Where-Object {
                $_ -is [string] -and ($_ -replace '\s','') -match [regex]::Escape(($snake -replace '_',''))
            } | Select-Object -First 1
            if ($hit) { $candidates += $PPIndex[$hit] }
        }

        if ($candidates.Count -gt 0) {
            $val = $candidates[0]
            $out[$label] = Coerce-ForHudu -FieldDef $f -RawValue $val
        }
    }

    return $out
}
function Get-PassportalValue {
    param([Parameter(Mandatory)]$Node)

    if ($null -eq $Node) { return $null }

    # Arrays/lists → resolve each and join (or return array if you prefer)
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        $vals = @()
        foreach ($item in $Node) { $vals += (Get-PassportalValue $item) }
        # If you want an array, return $vals; if you want a string:
        return ($vals -join ', ')
    }

    # Objects/hashtables → check known wrappers in priority order
    if ($Node -is [psobject] -or $Node -is [hashtable]) {
        $p = $Node.PSObject.Properties

        # 1) resolvedObject.value (your target)
        if ($p.Match('resolvedObject')) {
            $ro = $Node.resolvedObject
            if ($ro -and ($ro.PSObject.Properties.Match('value'))) {
                return (Get-PassportalValue $ro.value)
            }
        }
        # Sometimes it's sent lowercase
        if ($p.Match('resolvedobject')) {
            $ro = $Node.resolvedobject
            if ($ro -and ($ro.PSObject.Properties.Match('value'))) {
                return (Get-PassportalValue $ro.value)
            }
        }

        # 2) value.text or value.name or value (common pattern)
        if ($p.Match('value')) {
            $v = $Node.value
            if ($v -is [psobject] -or $v -is [hashtable]) {
                if ($v.PSObject.Properties.Match('text')) { return $v.text }
                if ($v.PSObject.Properties.Match('name')) { return $v.name }
            }
            return $v
        }

        # 3) direct text/name fallbacks
        if ($p.Match('text')) { return $Node.text }
        if ($p.Match('name')) { return $Node.name }
    }

    # Primitives
    return $Node
}


function Resolve-PPValue {
    param(
        $Node
    )
    if ($null -eq $Node) { return $null }

    # handle Passportal wrappers:
    # Prefer resolvedObject.value
    if ($Node.PSObject.Properties['resolvedObject']) {
        $ro = $Node.resolvedObject
        if ($ro -and $ro.PSObject.Properties['value']) {
            return (Resolve-PPValue $ro.value)
        }
    }

    # value.text / value.id / value (primitive)
    if ($Node.PSObject.Properties['value']) {
        $v = $Node.value
        if ($v -is [psobject] -or $v -is [hashtable]) {
            if ($v.PSObject.Properties['text'] -and $v.text) { return $v.text }
            if ($v.PSObject.Properties['name'] -and $v.name) { return $v.name }
            if ($v.PSObject.Properties['id']   -and $v.id)   { return $v.id }
        }
        return $v
    }

    # fallback text/name
    if ($Node.PSObject.Properties['text']) { return $Node.text }
    if ($Node.PSObject.Properties['name']) { return $Node.name }

    return $Node
}

function Get-NormalizedPassportalFields {
    param(
        [Parameter(Mandatory)] $ppFields,   # hashtable/psobject: Passportal .Fields bag
        [Parameter(Mandatory)][array]$fieldMap, # Hudu layout fields (with .label)
        [int]$passportalId
    )

    # 1) Build a fast lookup: variant (lower) -> property (Passportal field object)
    $variantToProp = @{}
    foreach ($prop in $ppFields.PSObject.Properties) {
        # Passportal keeps both the key name and a 'name' inside the value; prefer inner .name if present
        $ppLabel = if ($prop.Value -and $prop.Value.PSObject.Properties['name']) { $prop.Value.name } else { $prop.Name }
        foreach ($v in (Get-StringVariants $ppLabel)) {
            $k = $v.ToLower()
            if (-not $variantToProp.ContainsKey($k)) { $variantToProp[$k] = $prop }  # first match wins
        }
    }

    # 2) For each Hudu field label, try to match a PP field via variants and extract value
    $result = @{}
    foreach ($field in $fieldMap) {
        $label = $field.label
        if (-not $label) { continue }

        $matched = $null
        foreach ($candidate in (Get-StringVariants $label)) {
            $key = $candidate.ToLower()
            if ($variantToProp.ContainsKey($key)) { $matched = $variantToProp[$key]; break }
        }

        if ($matched) {
            $val = Resolve-PPValue $matched.Value
            if ($null -ne $val -and "$val" -ne '') {
                $result[$label] = $val
                # Write-Host "Matched '$label' → '$($matched.Name)' = '$val'"
            } else {
                # Write-Host "Matched '$label' but value empty for PP key '$($matched.Name)'"
            }
        } else {
            # Write-Host "No PP match for Hudu label '$label' (PP doc id $passportalId)"
        }
    }

    # Always handy to include the source id
    if ($passportalId) { $result['PassPortalID'] = $passportalId }

    return $result
}