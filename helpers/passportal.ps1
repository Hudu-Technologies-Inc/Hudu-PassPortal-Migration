
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
    write-host "Authentication Result $(if ($response -and $response.success -and $true -eq $response.success) {'Successful'} else {'Failure'})"

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

    Write-Host "Checking .\exported-csvs folder for Passportal exports..."
    foreach ($file in Get-ChildItem -Path $exportsFolder -Filter "*.csv" -File | Sort-Object Name) {
        Write-Host "Importing: $($file.Name)" -ForegroundColor DarkBlue
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

    $fieldValues = @{}
    if (-not $sourceFields) {
        Write-Warning "No detail entry found for document ID $docId"
        return @{}
    }

    $sourceFields

    foreach ($fieldDef in $FieldMap) {
        $label = $fieldDef.label

        if ($sourceFields.ContainsKey($label)) {
            $value = $sourceFields[$label]

            if ($value -is [hashtable] -and $value.ContainsKey("value")) {
                $actualValue = $value.value.text
            } else {
                $actualValue = $value
            }

            $fieldValues[$label] = $actualValue
        }
    }

    $fieldValues["PassPortalID"] = $docId
    return $fieldValues
}