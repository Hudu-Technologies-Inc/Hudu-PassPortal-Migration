$apiKey = $passportalData_SecretAccessKey
$apiSecret = $passportalData_SecretKeyID
$scope = "docs_api"
$content = "aUa&&XUQBJXz2x&"

# Correct HMAC
$hmac = New-Object System.Security.Cryptography.HMACSHA256
$hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($apiSecret)
$hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($content))
$xHash = [BitConverter]::ToString($hash) -replace '-', '' | ForEach-Object { $_.ToLower() }

# Debug
Write-Host "`nx-key: $apiKey"
Write-Host "x-hash: $xHash"
Write-Host "content: $content"

# Headers
$headers = @{
    "X-KEY"  = $apiKey
    "X-HASH" = $xHash
}

# Body (form-encoded)
$body = "content=$([uri]::EscapeDataString($content))"

# Request
$response = Invoke-RestMethod `
  -Uri "https://us-clover.passportalmsp.com/api/v2/auth/client_token" `
  -Method Post `
  -Headers $headers `
  -Body $body `
  -ContentType "application/x-www-form-urlencoded"

$response