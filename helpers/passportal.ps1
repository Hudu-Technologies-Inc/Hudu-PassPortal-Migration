
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

    $uri = "$BaseUri/$($ObjectType.ToLower())"
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