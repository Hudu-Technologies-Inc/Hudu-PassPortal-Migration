
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
        # $ppLabel = $ppLabel -replace " (YYYY-MM-DD)", ""
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
            }
        } else {
        }
    }

    if ($passportalId) { $result['PassPortalID'] = $passportalId }

    return $result
}