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

function Get-PassportalLeafArrays {
    param (
        [Parameter(Mandatory)]
        [object]$Data
    )

    $leafArrays = @()

    if ($Data -is [System.Collections.IEnumerable] -and $Data -notlike '*String*') {
        foreach ($item in $Data) {
            $leafArrays += Get-PassportalLeafArrays -Data $item
        }
    } elseif ($Data -is [PSCustomObject]) {
        $leafArrays += ,$Data
    }

    return $leafArrays
}

# --- MAIN FUNCTION TO FETCH AND FLATTEN ---
function Get-PassportalObjects {
    param (
        [Parameter(Mandatory)][string]$ObjectType
    )

    $uri = "$($passportalData.BaseURL)/$($ObjectType.ToLower())"
    Write-Host "Requesting $ObjectType from $uri"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $passportalData.requestHeaders
        $flat = Get-FlatPassportalData -Data $response
        return $flat
    } catch {
        Write-Warning "Failed to get $ObjectType. $_"
        return @()
    }
}

# --- RECURSIVELY FLATTEN TO PSCUSTOMOBJECTS ---
function Get-FlatPassportalData {
    param (
        [object]$Data
    )

    $results = @()

    if ($null -eq $Data) { return @() }

    if ($Data -is [System.Collections.IDictionary] -or $Data -is [PSCustomObject]) {
        return ,$Data
    }
    elseif ($Data -is [System.Collections.IEnumerable] -and $Data -notlike '*String*') {
        foreach ($item in $Data) {
            $results += Get-FlatPassportalData -Data $item
        }
    }

    return $results
}