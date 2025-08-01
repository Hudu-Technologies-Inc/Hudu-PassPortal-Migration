
function Get-PassportalFolders {
    $uri = "$BaseUri/folders"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $PassPortalHeaders
        return $response
    } catch {
        Write-Error "Failed to get folders: $_"
    }
}

function Get-PassportalPasswords {
    $uri = "$BaseUri/passwords"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $PassPortalHeaders
        return $response
    } catch {
        Write-Error "Failed to get passwords: $_"
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
