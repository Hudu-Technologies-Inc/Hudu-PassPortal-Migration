
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

function Get-CSVExportData {
    param (
        [string]$exportsFolder
    )

    Set-PrintAndLog -message "Checking .\exported-csvs folder for Passportal exports..." -Color DarkBlue
    foreach ($file in Get-ChildItem -Path $exportsFolder -Filter "*.csv" -File | Sort-Object Name) {
        Set-PrintAndLog -message "Importing: $($file.Name)" -Color DarkBlue
        $csvData=@{}
        $fullPath = $file.FullName
        $firstLine = (Get-Content -Path $fullPath -TotalCount 1).Trim()

        # Check if the first line appears to be a header
        $hasHeader = $firstLine -match 'PassPortal ID'

        if ($file.Name -like "*clients.csv") {
            $csv = if ($hasHeader) {
                Import-Csv -Path $fullPath
            } else {
                Import-Csv -Path $fullPath -Header "PassPortal ID","Name","Email"
            }
            $csvData['clients'] = $csv
        } elseif ($file.Name -like "*passwords.csv") {
            $csv = if ($hasHeader) {
                Import-Csv -Path $fullPath
            } else {
                Import-Csv -Path $fullPath -Header "Passportal ID","Client Name","Credential","Username","Password","Description","Expires (Yes/No)","Notes","URL","Folder(Optional)"
            }
            $csvData['passwords'] = $csv
        } elseif ($file.Name -like "*users.csv") {
            $csv = if ($hasHeader) {
                Import-Csv -Path $fullPath
            } else {
                Import-Csv -Path $fullPath -Header "Passportal ID (BLANK)","Last Name","First Name","Email","Phone"

            }
            $csvData['users'] = $csv
        } elseif ($file.Name -like "*vault.csv") {
            $csv = if ($hasHeader) {
                Import-Csv -Path $fullPath
            } else {
                Import-Csv -Path $fullPath -Header "Passportal ID","Credential","Username","Password","Description","Expires (Yes/No)","Notes","URL","Folder(Optional)"
            }
            $csvData['vault'] = $csv
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
            @{ label="Model"; field_type="Text" },
            @{ label="Serial Number"; field_type="Text" },
            @{ label="Purchase Date"; field_type="Date" },
            @{ label="Notes"; field_type="RichText" }
        )
        active_directory = @(
            @{ label="Domain Name"; field_type="Text" },
            @{ label="Admin User"; field_type="Text" },
            @{ label="Admin Password"; field_type="Password" },
            @{ label="Domain Controller IP"; field_type="Text" }
        )
        application = @(
            @{ label="App Name"; field_type="Text" },
            @{ label="License Key"; field_type="Text" },
            @{ label="Publisher"; field_type="Text" },
            @{ label="Install Date"; field_type="Date" }
        )
        backup = @(
            @{ label="Backup Type"; field_type="Text" },
            @{ label="Software Used"; field_type="Text" },
            @{ label="Schedule"; field_type="Text" },
            @{ label="Last Successful Backup"; field_type="Date" }
        )
        email = @(
            @{ label="Email Address"; field_type="Text" },
            @{ label="Password"; field_type="Password" },
            @{ label="IMAP Server"; field_type="Text" },
            @{ label="SMTP Server"; field_type="Text" }
        )
        folders = @(
            @{ label="Folder Name"; field_type="Text" },
            @{ label="Path"; field_type="Text" },
            @{ label="Permissions"; field_type="RichText" }
        )
        file_sharing = @(
            @{ label="Platform"; field_type="Text" },
            @{ label="Link"; field_type="Text" },
            @{ label="User Accounts"; field_type="RichText" }
        )
        contact = @(
            @{ label="Full Name"; field_type="Text" },
            @{ label="Email"; field_type="Text" },
            @{ label="Phone"; field_type="Text" },
            @{ label="Role"; field_type="Text" }
        )
        location = @(
            @{ label="Location Name"; field_type="Text" },
            @{ label="Address"; field_type="RichText" },
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
            @{ label="Printer Name"; field_type="Text" },
            @{ label="IP Address"; field_type="Text" },
            @{ label="Model"; field_type="Text" },
            @{ label="Location"; field_type="Text" }
        )
        remote_access = @(
            @{ label="Tool"; field_type="Text" },
            @{ label="Host"; field_type="Text" },
            @{ label="Username"; field_type="Text" },
            @{ label="Password"; field_type="Password" }
        )
        vendor = @(
            @{ label="Vendor Name"; field_type="Text" },
            @{ label="Account Rep"; field_type="Text" },
            @{ label="Phone"; field_type="Text" },
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

    $fieldValues['PassPortalID'] = $docId
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


function Get-NormalizedPassportalFields {
    <#
      Input: $ppFields = the PSCustomObject at details[0].Fields
      Output: hashtable with:
        - original Passportal keys (e.g. "backup_type") → coerced value
        - also index by the human label when available (e.g. "Backup Type") → same value
    #>
    param([Parameter(Mandatory)] $ppFields)

    # PSCustomObject -> hashtable
    $h = @{}
    $ppFields.PSObject.Properties | ForEach-Object {
        $k = $_.Name
        $v = $_.Value

        if ($null -eq $v) { return }

        # extract displayed text when nested
        $val =
            if ($v -is [System.Collections.IDictionary]) {
                if ($v.ContainsKey('value')) {
                    $valObj = $v['value']
                    if ($valObj -is [System.Collections.IDictionary] -and $valObj.ContainsKey('text')) {
                        $valObj['text']
                    } else {
                        $valObj
                    }
                } elseif ($v.ContainsKey('attribute')) {
                    # attribute often an array of objects; pull text(s)
                    $attrs = $v['attribute']
                    if ($attrs -is [System.Collections.IEnumerable]) {
                        @($attrs | ForEach-Object {
                            if ($_ -is [System.Collections.IDictionary] -and $_.ContainsKey('text')) { $_['text'] } else { $_ }
                        }) | Where-Object { $_ -ne $null -and $_ -ne '' }
                    } else {
                        $v
                    }
                } else {
                    $v
                }
            } else {
                $v
            }

        # index by original key
        $h[$k] = $val

        # also index by human label if present (e.g. Backup Type)
        if ($v -is [System.Collections.IDictionary] -and $v.ContainsKey('name') -and $v['name']) {
            $label = [string]$v['name']
            $h[$label] = $val
            # and by snake_case label for convenience
            $h[(Convert-ToSnakeCase $label)] = $val
        }
    }

    return $h
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


function Build-HuduCustomFields {
    param(
        [Parameter(Mandatory)][array]$FieldMap,
        [Parameter(Mandatory)][hashtable]$HuduValuesByLabel
    )

    $list = New-Object System.Collections.Generic.List[hashtable]

    foreach ($f in $FieldMap) {
        $label = $f.label
        $key   = if ($f.PSObject.Properties['key'] -and $f.key) { 
                     $f.key 
                 } else { 
                     Convert-ToSnakeCase $label 
                 }

        if ($HuduValuesByLabel.ContainsKey($label)) {
            $raw = $HuduValuesByLabel[$label]

            # --- Passportal value extraction ---
            if ($null -ne $raw) {
                if ($raw.PSObject.Properties['value']) {
                    $val = $raw.value

                    if ($val -is [psobject] -or $val -is [hashtable]) {
                        # Prefer .text if present
                        if ($val.PSObject.Properties['text'] -and $val.text) {
                            $raw = $val.text
                        }
                        # Otherwise, fall back to .id
                        elseif ($val.PSObject.Properties['id'] -and $val.id) {
                            $raw = $val.id
                        }
                        else {
                            $raw = $val
                        }
                    }
                    else {
                        $raw = $val
                    }
                }
            }
            # -----------------------------------

            if ($null -ne $raw -and ($raw -ne '' -or $raw -isnot [string])) {
                $list.Add(@{ $key = $raw })
            }
        }
    }

    return @($list)
}