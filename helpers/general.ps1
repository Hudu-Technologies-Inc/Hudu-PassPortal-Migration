
function Unset-Vars {
    param (
        [string]$varname,
        [string[]]$scopes = @('Local', 'Script', 'Global', 'Private')
    )

    foreach ($scope in $scopes) {
        if (Get-Variable -Name $varname -Scope $scope -ErrorAction SilentlyContinue) {
            Remove-Variable -Name $varname -Scope $scope -Force -ErrorAction SilentlyContinue
            Write-Host "Unset `$${varname} from scope: $scope"
        }
    }
}

function normalize-companyName {
    param([string]$Text)

    ($Text `
        -replace '(?i)\binc\b', '' `
        -replace '[\.,]', '' `
        -replace '\s+', ' '
    ).Trim()
}

function Omni-Relate {
    param(
        [bool]$includeArticles=$true,
        [bool]$includeProcesses=$true,
        [bool]$includeWebsites=$true,
        [bool]$includeIPAM=$true,
        [bool]$includePasswords=$true,
        [bool]$dryRun=$false
    )

    function _Normalize-AssetName {
        param([string]$Name)
        if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
        $n = $Name.Normalize([Text.NormalizationForm]::FormKC)
        $n = $n -replace '&nbsp;',' ' -replace '\s+',' '
        $n = $n.Trim().ToLowerInvariant()
        return $n
    }

    function _Normalize-WebsiteURL {
        param([string]$Url)
        if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
        $u = $Url.Trim()
        if ($u -match '^(https?://)?(?<host>[^/]+)(?<rest>/.*)?$') {
            $hostname = $matches.host.ToLowerInvariant()
            return $hostname.ToLowerInvariant()
        }
        return $u.ToLowerInvariant()
    }

    function _Add-UniqueText {
        param(
            [System.Collections.Generic.List[string]]$List,
            [string]$Value
        )

        if ([string]::IsNullOrWhiteSpace($Value)) { return }

        $trimmed = $Value.Trim()
        if (-not $List.Contains($trimmed)) {
            $null = $List.Add($trimmed)
        }
    }

    function _Contains-IgnoreCase {
        param(
            [string]$Text,
            [string]$Value
        )

        if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Value)) { return $false }
        return $Text.IndexOf($Value, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }

    function _Test-TextsContainNeedle {
        param(
            [string[]]$Texts,
            [string]$Needle,
            [int]$MinimumLength = 5
        )

        if ([string]::IsNullOrWhiteSpace($Needle)) { return $false }

        $candidate = $Needle.Trim()
        $looksStructured = $candidate -match '[\.:/@\\]'
        if (-not $looksStructured -and "$candidate".length -lt $MinimumLength) {
            return $false
        }

        foreach ($text in @($Texts)) {
            if (_Contains-IgnoreCase -Text $text -Value $candidate) {
                return $true
            }
        }

        return $false
    }

    function _Get-AssetIdentifiers {
        param($Asset)

        $identifiers = [System.Collections.Generic.List[string]]::new()
        _Add-UniqueText -List $identifiers -Value $Asset.name

        $normalizedAssetName = _Normalize-AssetName $Asset.name
        if (-not [string]::IsNullOrWhiteSpace($normalizedAssetName) -and "$normalizedAssetName".length -ge 5 -and $normalizedAssetName -ine 'main') {
            _Add-UniqueText -List $identifiers -Value $normalizedAssetName
        }

        foreach ($field in @($Asset.fields | Where-Object { $_.field_type -eq 'Website' })) {
            _Add-UniqueText -List $identifiers -Value $field.value
            _Add-UniqueText -List $identifiers -Value (_Normalize-WebsiteURL $field.value)
        }

        return @($identifiers)
    }

    function _Get-AssetsMentionedInTexts {
        param(
            [object[]]$Assets,
            $SourceAsset,
            [string[]]$Texts
        )

        if (-not $Assets -or -not $Texts -or $Texts.Count -eq 0) { return @() }

        $matchedAssets = [System.Collections.Generic.List[object]]::new()

        foreach ($asset in @($Assets)) {
            if ($null -eq $asset -or [string]$asset.id -eq [string]$SourceAsset.id) { continue }

            $normalizedName = _Normalize-AssetName $asset.name
            if ([string]::IsNullOrWhiteSpace($normalizedName) -or $normalizedName -ieq 'main' -or "$normalizedName".Length -le 5) {
                continue
            }

            $identifiers = [System.Collections.Generic.List[string]]::new()
            _Add-UniqueText -List $identifiers -Value $asset.name
            _Add-UniqueText -List $identifiers -Value $normalizedName

            foreach ($identifier in @($identifiers)) {
                if (_Test-TextsContainNeedle -Texts $Texts -Needle $identifier -MinimumLength 6) {
                    $null = $matchedAssets.Add($asset)
                    break
                }
            }
        }

        return @($matchedAssets)
    }

    function _Get-PasswordFolderName {
        param(
            $Password,
            [object[]]$PasswordFolders
        )

        if ($null -eq $Password -or $null -eq $Password.password_folder_id) { return $null }

        return ($PasswordFolders | Where-Object { $_.id -eq $Password.password_folder_id } | Select-Object -First 1).name
    }

    function _Get-NonAssetSearchTexts {
        param(
            [string]$Type,
            $Item,
            [object[]]$PasswordFolders
        )

        $texts = [System.Collections.Generic.List[string]]::new()

        switch ($Type) {
            'Website' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.notes
                _Add-UniqueText -List $texts -Value (_Normalize-WebsiteURL $Item.name)
                if ($Item.PSObject.Properties['url']) {
                    _Add-UniqueText -List $texts -Value $Item.url
                    _Add-UniqueText -List $texts -Value (_Normalize-WebsiteURL $Item.url)
                }
            }
            'Article' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.content
            }
            'Procedure' {
                _Add-UniqueText -List $texts -Value $Item.name
                foreach ($task in @($Item.procedure_tasks_attributes)) {
                    if ($task -is [string]) {
                        _Add-UniqueText -List $texts -Value $task
                        continue
                    }

                    _Add-UniqueText -List $texts -Value $task.name
                    if ($task.PSObject.Properties['description']) {
                        _Add-UniqueText -List $texts -Value $task.description
                    }
                }
            }
            'AssetPassword' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.notes
                _Add-UniqueText -List $texts -Value $Item.description
                _Add-UniqueText -List $texts -Value (_Get-PasswordFolderName -Password $Item -PasswordFolders $PasswordFolders)
            }
            'Network' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.notes
                _Add-UniqueText -List $texts -Value $Item.description
                foreach ($propertyName in @('network', 'cidr', 'subnet', 'gateway')) {
                    if ($Item.PSObject.Properties[$propertyName]) {
                        _Add-UniqueText -List $texts -Value ([string]$Item.$propertyName)
                    }
                }
            }
            'IPAddress' {
                _Add-UniqueText -List $texts -Value $Item.name
                _Add-UniqueText -List $texts -Value $Item.notes
                _Add-UniqueText -List $texts -Value $Item.description
                foreach ($propertyName in @('ip_address', 'address', 'hostname')) {
                    if ($Item.PSObject.Properties[$propertyName]) {
                        _Add-UniqueText -List $texts -Value ([string]$Item.$propertyName)
                    }
                }
            }
        }

        return @($texts)
    }

    function _Get-RelationTargetIdentifiers {
        param(
            [string]$Type,
            $Item,
            [object[]]$PasswordFolders
        )

        if ($Type -eq 'Asset') {
            return @(_Get-AssetIdentifiers -Asset $Item)
        }

        $identifiers = [System.Collections.Generic.List[string]]::new()
        _Add-UniqueText -List $identifiers -Value $Item.name

        switch ($Type) {
            'Website' {
                _Add-UniqueText -List $identifiers -Value (_Normalize-WebsiteURL $Item.name)
                if ($Item.PSObject.Properties['url']) {
                    _Add-UniqueText -List $identifiers -Value $Item.url
                    _Add-UniqueText -List $identifiers -Value (_Normalize-WebsiteURL $Item.url)
                }
            }
            'Procedure' {
                foreach ($task in @($Item.procedure_tasks_attributes)) {
                    if ($task -is [string]) {
                        _Add-UniqueText -List $identifiers -Value $task
                    } else {
                        _Add-UniqueText -List $identifiers -Value $task.name
                    }
                }
            }
            'AssetPassword' {
                _Add-UniqueText -List $identifiers -Value (_Get-PasswordFolderName -Password $Item -PasswordFolders $PasswordFolders)
            }
            'Network' {
                foreach ($propertyName in @('network', 'cidr', 'subnet', 'gateway')) {
                    if ($Item.PSObject.Properties[$propertyName]) {
                        _Add-UniqueText -List $identifiers -Value ([string]$Item.$propertyName)
                    }
                }
            }
            'IPAddress' {
                foreach ($propertyName in @('ip_address', 'address', 'hostname')) {
                    if ($Item.PSObject.Properties[$propertyName]) {
                        _Add-UniqueText -List $identifiers -Value ([string]$Item.$propertyName)
                    }
                }
            }
        }

        return @($identifiers)
    }

    function _New-TrackedRelation {
        param(
            [string]$CompanyName,
            [string]$FromType,
            [object]$FromId,
            [string]$FromName,
            [string]$ToType,
            [object]$ToId,
            [string]$ToName,
            [string]$RelationLabel,
            [hashtable]$SeenRelations,
            [switch]$DryRun
        )

        if ($FromType -eq $ToType -and [string]$FromId -eq [string]$ToId) { return }
        if ($FromType -eq "IPAddress" -and $ToType -eq "IPAddress") { return }

        $relationKey = "$FromType|$FromId|$ToType|$ToId"
        if ($SeenRelations.ContainsKey($relationKey)) { return }
        $SeenRelations[$relationKey] = $true

        Write-Host "[$CompanyName] '$FromName' ($FromId) mentions $RelationLabel -> '$ToName' ($ToId)"

        if ($DryRun) { return }

        try {
            $null = New-HuduRelation -FromableType $FromType -ToableType $ToType -FromableID $FromId -ToableID $ToId
        } catch {
            Write-Warning "Failed relation creation for $FromType/$FromId -> $ToType/$ToId : $($_.Exception.Message)"
        }
    }

    if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
    write-host "getting companies"; $allcompanies = get-huducompanies;
    write-host "getting assets"; $allAssets = get-huduassets;
    if ($includewebsites){write-host "getting websites"; $allWebsites = get-huduwebsites;} else {write-host "skipping websites"; $allWebsites = @();}
    if ($includeArticles){write-host "getting articles"; $allArticles = get-huduarticles;} else {write-host "skipping articles"; $allArticles = @();}
    if ($includeProcesses){write-host "getting processes"; $allProcesses = Get-HuduProcedures;} else {write-host "skipping processes"; $allProcesses = @();}
    if ($includeIPAM){
        write-host "getting networks"; $allNetworks = Get-HuduNetworks;
        write-host "getting addresses"; $alladdresses = get-huduipaddresses;
    } else {write-host "skipping IPAM"; $allNetworks = @(); $alladdresses = @();}
    if ($includePasswords){
        write-host "getting passwords"; $allPasswords = get-hudupasswords;
        write-host "getting password folders"; $allPasswordFolders = get-hudupasswordfolders;
    } else {write-host "skipping passwords"; $allPasswords = @(); $allPasswordFolders = @();}



    foreach ($c in $allcompanies) { 

        $companyAssets = $allAssets | Where-Object { $_.company_id -eq $c.id }
        $companywebsites = $allWebsites | Where-Object { $_.company_id -eq $c.id }
        $companyArticles = $allArticles | Where-Object { $_.company_id -eq $c.id }
        $companyProcesses = $allProcesses | Where-Object { $_.company_id -eq $c.id }
        $companyNetworks = $allNetworks | Where-Object { $_.company_id -eq $c.id }
        $companyAddresses = $alladdresses | Where-Object { $_.company_id -eq $c.id }
        $companypasswords = $allPasswords | Where-Object { $_.company_id -eq $c.id }
        $companypasswordfolders = $allPasswordFolders | Where-Object { $_.company_id -eq $c.id }

        foreach ($i in @($companywebsites,$companyArticles,$companyProcesses,$companyNetworks,$companyAddresses,$companyAssets,$companypasswords,$companypasswordfolders) | Where-Object { $_.count -gt 0 }) {
            write-host "Company '$($c.name)' has $($i.count) items of type $($i[0].psobject.typeNames[0])" -ForegroundColor DarkCyan
        }

        $companyProcedureTaskNames = $companyProcesses.procedure_tasks_attributes.name | sort-object -unique
        $companyProcedureAssignments = $companyProcesses.procedure_tasks_attributes.first_assigned_user_name | sort-object -unique


        $companyAssetsByName = $companyAssets | Group-Object { _Normalize-AssetName $_.name } -AsHashTable -AsString
        $companySeenRelations = @{}

        foreach ($a in $companyAssets) {
            $normalizedAssetName = _Normalize-AssetName $a.name
            write-host "Processing asset '$($a.name)' ($($a.id))"


            $mentionedWebsites = @()
            $mentionedArticles = @()
            $mentionedAssets = @()
            $mentionedProcedures = @()
            $mentionedPasswords = @()
            $networksMentioned = @()
            $addressesMentioned = @()


            # start out with association by name (if not generalized)
            if ($normalizedAssetName -ieq "main" -or "$normalizedAssetName".length -lt 5) {
                write-host "Skipping match by name on too-generic of asset '$($a.name)' ($($a.id)) due to short or generic name" -ForegroundColor Yellow
            } else {
            if ($companywebsites) {
                $mentionedWebsites = $companywebsites | Where-Object { $_.Notes -and ($_.Notes.Contains($normalizedAssetName) -or $_.Notes.Contains($a.name)) }
            }
            if ($companyArticles) {
                $mentionedArticles = $companyArticles | Where-Object { ($_.Name -and $_.Content.Contains($a.name)) -or ($_.Content -and $_.Content.Contains($normalizedAssetName)) }
            }
            if ($companyProcesses) {
                $mentionedProcedures = $companyProcesses | Where-Object { ($_.name -and $_.name.Contains($normalizedAssetName)) -or ($_.procedure_tasks_attributes.name -and $_.procedure_tasks_attributes.name.Contains($normalizedAssetName)) -or ($_.name -and $_.name.Contains($a.name)) -or ($_.procedure_tasks_attributes.name -and $_.procedure_tasks_attributes.name.Contains($a.name)) }
            }
            if ($companypasswords) {
                $mentionedPasswords = $companypasswords | Where-Object { ($_.name -and ($_.name.Contains($normalizedAssetName) -or $_.name.Contains($a.name))) -or ($_.notes -and ($_.notes.Contains($normalizedAssetName) -or $_.notes.Contains($a.name)) -or ($_.description -and ($_.description.Contains($normalizedAssetName) -or $_.description.Contains($a.name)))) }
            }}
            

            # websites where name or url is mentioned in text/richtext fields of the asset
            # articles with content or name mentioned in a website field (either website field or text/richtext fields)
            $a.fields | Where-Object {$_.field_type -eq "Website"} | ForEach-Object {
                $fieldValue = $_.value
                $fieldvaluenormalized = _Normalize-WebsiteURL $fieldValue
                foreach ($companyProcess in $companyProcesses){ # procedure or tasks contain website field value or asset name
                    if (($companyProcess.name -and $companyProcess.name.Contains($fieldValue) -or $companyProcess.procedure_tasks_attributes.name -and $companyProcess.procedure_tasks_attributes.name.Contains($fieldValue)) -or `
                        ($companyProcess.name -and $companyProcess.name.Contains($fieldValue) -or $companyProcess.procedure_tasks_attributes.name -and $companyProcess.procedure_tasks_attributes.name.Contains($fieldValue))){
                        $mentionedProcedures += $companyProcess
                    }
                }
                foreach ($password in $companypasswords){ # password or password notes contain website field value or asset name
                    if (($password.name -and $password.name.Contains($fieldValue)) -or ($password.notes -and $password.notes.Contains($fieldValue)) -or ($password.name -and $password.name.Contains($a.name)) -or ($password.notes -and $password.notes.Contains($a.name))){
                        $mentionedPasswords += $password
                    } elseif ($null -ne $password.password_folder_id){
                        $passwordFolder = $companypasswordfolders | Where-Object { $_.id -eq $password.password_folder_id } | Select-Object -First 1
                        if ($passwordFolder.name -and $fieldValue -and $passwordFolder.name.Contains($fieldValue) -or $passwordFolder.name -and $fieldValue -and $passwordFolder.name.Contains($a.name)){
                            $mentionedPasswords += $password
                        }
                    }
                }
                foreach ($network in $companyNetworks){
                    if ($network.name -and $network.name.Contains($fieldValue) -or $network.notes -and $network.notes.Contains($fieldValue) -or $network.name -and $network.name.Contains($a.name) -or $network.notes -and $network.notes.Contains($a.name) -or $network.description -and ( $network.description.Contains($fieldValue) -or $network.description.Contains($a.name) -or $network.description.Contains($fieldvaluenormalized)) ){
                        $networksMentioned += $network
                    }
                }
                foreach ($address in $companyaddresses){
                    if ($address.name -and $address.name.Contains($fieldValue) -or $address.notes -and $address.notes.Contains($fieldValue) -or $address.name -and $address.name.Contains($a.name) -or $address.notes -and $address.notes.Contains($a.name) -or $address.description -and ( $address.description.Contains($fieldValue) -or $address.description.Contains($a.name) -or $address.description.Contains($fieldvaluenormalized)) ){
                        $addressesMentioned += $address
                    }
                }
                $mentionedWebsites += $companywebsites | Where-Object { "$fieldvaluenormalized*" -ilike "$(_Normalize-WebsiteURL $_.name)*" -or $_.name -icontains "$($fieldvaluenormalized)" -or $_.name -icontains $normalizedAssetName }
                $mentionedArticles += $companyArticles | Where-Object { $_.content -and $_.content.Contains("$($fieldvaluenormalized)") -or ($_.Name -and $_.Name.Contains("$($fieldvaluenormalized)")) }
                $mentionedAssets += $companyAssets | Where-Object { $_.name -and $_.name.Contains("$($fieldvaluenormalized)") }
            }
            $a.fields | Where-Object {$_.field_type -eq "ConfidentialText"} | ForEach-Object {
                if (($_.value -and $_.value -eq $password.password) -or ($_.value -and $_.value -eq $password.notes) -or ($_.value -and $_.value -eq $a.name) -or ($_.value -and $_.value -eq $password.name)){
                    $mentionedPasswords += $password
                } 
            }

            $a.fields | Where-Object {$_.field_type -eq "RichText" -or $_.field_type -ieq "Heading"  -or $_.field_type -ieq "Embed"} | ForEach-Object {
                $fieldValue = $_.value
                foreach ($companyProcess in $companyProcesses){
                    if (($companyProcess.name -and $fieldValue -icontains $companyProcess.name -or $companyProcess.procedure_tasks_attributes.name -and $fieldValue -icontains $companyProcess.procedure_tasks_attributes.name)){
                        $mentionedProcedures += $companyProcess
                    }
                }
                foreach ($password in $companypasswords){ 
                    if (($password.name -and $fieldValue -icontains $password.name) -or ($password.notes -and $fieldValue -icontains $password.notes) -or ($password.name -and $fieldValue -icontains $a.name) -or ($password.notes -and $fieldValue -icontains $a.name)){
                        $mentionedPasswords += $password
                    } elseif ($null -ne $password.password_folder_id){
                        $passwordFolder = $companypasswordfolders | Where-Object { $_.id -eq $password.password_folder_id } | Select-Object -First 1
                        if ($passwordFolder.name -and $fieldValue -and $fieldValue -icontains $passwordFolder.name -or $passwordFolder.name -and $fieldValue -icontains $a.name){
                            $mentionedPasswords += $password
                        }
                    }
                }
                foreach ($network in $companyNetworks){
                    if ($network.name -and $fieldValue -icontains $network.name -or $network.notes -and $fieldValue -icontains $network.notes -or $network.name -and $fieldValue -icontains $a.name -or $network.notes -and $fieldValue -icontains $a.name -or $network.description -and ( $fieldValue -icontains $network.description) ){
                        $networksMentioned += $network
                    }
                }
                foreach ($address in $companyaddresses){
                    if ($address.name -and $fieldValue -icontains $address.name -or $address.notes -and $fieldValue -icontains $address.notes -or $address.name -and $fieldValue -icontains $a.name -or $address.notes -and $fieldValue -icontains $a.name -or $address.description -and ( $fieldValue -icontains $address.description) ){
                        $addressesMentioned += $address
                    }
                }                
                $mentionedWebsites += $companywebsites | Where-Object { $fieldValue -icontains $normalizedAssetName -or $(_Normalize-AssetName $_.name) -ieq $normalizedAssetName -or $fieldValue -icontains $_.name -or $_.notes -icontains $normalizedAssetName -or $_.notes -icontains $a.name }
                $mentionedArticles += $companyArticles | Where-Object { $_.content -and $_.content.Contains($normalizedAssetName) -or $_.content -icontains $a.name -or $normalizedAssetName -ieq (_Normalize-AssetName $_.name) }
                $mentionedAssets += _Get-AssetsMentionedInTexts -Assets $companyAssets -SourceAsset $a -Texts @($fieldValue)
            }       
            $a.fields | Where-Object {$_.field_type -eq "Text"  -or $_.field_type -ieq "Link"  -or $_.field_type -ieq "ConfidentialText"  -or $_.field_type -ieq "Phone"  -or $_.field_type -ieq "Copyable Text"} | ForEach-Object {
                $fieldValue = $_.value
                foreach ($companyProcess in $companyProcesses){
                    if (
                        ($companyProcess.name -and $fieldValue -icontains $companyProcess.name -or $companyProcess.procedure_tasks_attributes.name -and $fieldValue -icontains $companyProcess.procedure_tasks_attributes.name) `
                        -or ($companyProcess.name -and $companyProcess.name -icontains $fieldValue -or $companyProcess.procedure_tasks_attributes.name -and $companyProcess.procedure_tasks_attributes.name -icontains $fieldValue)){
                        $mentionedProcedures += $companyProcess
                    }
                }
                foreach ($password in $companypasswords){ 
                    if (
                        ($password.name -and $fieldValue -icontains $password.name) -or ($password.notes -and $fieldValue -icontains $password.notes) -or ($password.name -and $fieldValue -icontains $a.name) -or ($password.notes -and $fieldValue -icontains $a.name) `
                        -or ($password.name -and $password.name -icontains $fieldValue) -or ($password.notes -and $password.notes -icontains $fieldValue)){
                        $mentionedPasswords += $password
                    } elseif ($null -ne $password.password_folder_id){
                        $passwordFolder = $companypasswordfolders | Where-Object { $_.id -eq $password.password_folder_id } | Select-Object -First 1
                        if (
                            ($passwordFolder.name -and $fieldValue -and $fieldValue -icontains $passwordFolder.name) -or ($passwordFolder.name -and $fieldValue -icontains $a.name) `
                            -or ($passwordFolder.name -and $passwordFolder.name -icontains $fieldValue)){
                            $mentionedPasswords += $password
                        }
                    }
                }
                foreach ($network in $companyNetworks){
                    if (($network.name -and $fieldValue -icontains $network.name -or $network.notes -and $fieldValue -icontains $network.notes -or $network.name -and $fieldValue -icontains $a.name -or $network.notes -and $fieldValue -icontains $a.name -or $network.description -and ( $fieldValue -icontains $network.description)) -or `
                        ($network.name -and $network.name -icontains $fieldValue) -or ($network.notes -and $network.notes -icontains $fieldValue) -or ($network.description -and $network.description -icontains $fieldValue)){
                        $networksMentioned += $network
                    }
                }
                foreach ($address in $companyaddresses){
                    if (($address.name -and $fieldValue -icontains $address.name -or $address.notes -and $fieldValue -icontains $address.notes -or $address.name -and $fieldValue -icontains $a.name -or $address.notes -and $fieldValue -icontains $a.name -or $address.description -and ( $fieldValue -icontains $address.description) ) -or `
                        ($address.name -and $address.name -icontains $fieldValue) -or ($address.notes -and $address.notes -icontains $fieldValue) -or ($address.description -and $address.description -icontains $fieldValue)){
                        $addressesMentioned += $address
                    }
                }

                $mentionedArticles += $companyArticles | Where-Object { $($fieldValue) -ieq $_.name -or $_.content -and $_.content.Contains($fieldValue) }
                $mentionedWebsites += $companywebsites | Where-Object { $($fieldValue) -ieq $_.name -or $(_Normalize-WebsiteURL $_.name) -ieq $fieldValue -or $_.notes -icontains $fieldValue -or $_.notes -icontains $a.name }
                $mentionedAssets += _Get-AssetsMentionedInTexts -Assets $companyAssets -SourceAsset $a -Texts @($fieldValue)
            }
    
            # "siblings": other assets with same normalized name but different id
            $siblings = @($companyAssetsByName[$normalizedAssetName] | Where-Object { $_.id -ne $a.id })
            $siblings | ForEach-Object {
                Write-Host "Sibling Asset $($a.name)@($($a.asset_layout_id)) -> $($_.name)@($($_.asset_layout_id))"
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Asset" -ToId $_.id -ToName $_.name -RelationLabel "asset" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedWebsites | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Website" -ToId $_.id -ToName $_.name -RelationLabel "website" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedArticles | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Article" -ToId $_.id -ToName $_.name -RelationLabel "article" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedAssets | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Asset" -ToId $_.id -ToName $_.name -RelationLabel "asset" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedPasswords | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "AssetPassword" -ToId $_.id -ToName $_.name -RelationLabel "password" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $mentionedProcedures | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Procedure" -ToId $_.id -ToName $_.name -RelationLabel "procedure" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $addressesMentioned | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "IPAddress" -ToId $_.id -ToName $_.name -RelationLabel "address" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
            $networksMentioned | ForEach-Object {
                _New-TrackedRelation -CompanyName $c.name -FromType "Asset" -FromId $a.id -FromName $a.name -ToType "Network" -ToId $_.id -ToName $_.name -RelationLabel "network" -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
        }

        $nonAssetSources = @()
        $nonAssetSources += $companywebsites | ForEach-Object { [pscustomobject]@{ type = 'Website'; item = $_ } }
        $nonAssetSources += $companyArticles | ForEach-Object { [pscustomobject]@{ type = 'Article'; item = $_ } }
        $nonAssetSources += $companyProcesses | ForEach-Object { [pscustomobject]@{ type = 'Procedure'; item = $_ } }
        $nonAssetSources += $companypasswords | ForEach-Object { [pscustomobject]@{ type = 'AssetPassword'; item = $_ } }
        $nonAssetSources += $companyNetworks | ForEach-Object { [pscustomobject]@{ type = 'Network'; item = $_ } }
        $nonAssetSources += $companyAddresses | ForEach-Object { [pscustomobject]@{ type = 'IPAddress'; item = $_ } }

        $relationTargets = @()
        $relationTargets += $companyAssets | ForEach-Object { [pscustomobject]@{ type = 'Asset'; label = 'asset'; item = $_ } }
        $relationTargets += $companywebsites | ForEach-Object { [pscustomobject]@{ type = 'Website'; label = 'website'; item = $_ } }
        $relationTargets += $companyArticles | ForEach-Object { [pscustomobject]@{ type = 'Article'; label = 'article'; item = $_ } }
        $relationTargets += $companyProcesses | ForEach-Object { [pscustomobject]@{ type = 'Procedure'; label = 'procedure'; item = $_ } }
        $relationTargets += $companypasswords | ForEach-Object { [pscustomobject]@{ type = 'AssetPassword'; label = 'password'; item = $_ } }
        $relationTargets += $companyNetworks | ForEach-Object { [pscustomobject]@{ type = 'Network'; label = 'network'; item = $_ } }
        $relationTargets += $companyAddresses | ForEach-Object { [pscustomobject]@{ type = 'IPAddress'; label = 'address'; item = $_ } }

        foreach ($source in $nonAssetSources) {
            $sourceTexts = @(_Get-NonAssetSearchTexts -Type $source.type -Item $source.item -PasswordFolders $companypasswordfolders)
            if (-not $sourceTexts -or $sourceTexts.Count -eq 0) { continue }

            $sourceName = $source.item.name
            if ([string]::IsNullOrWhiteSpace($sourceName)) {
                $sourceName = "$($source.type) $($source.item.id)"
            }

            Write-Host "Processing $($source.type.ToLowerInvariant()) '$sourceName' ($($source.item.id)) for relation mentions"

            foreach ($target in $relationTargets) {
                if ($source.type -eq $target.type -and [string]$source.item.id -eq [string]$target.item.id) { continue }

                $targetIdentifiers = @(_Get-RelationTargetIdentifiers -Type $target.type -Item $target.item -PasswordFolders $companypasswordfolders)
                if (-not $targetIdentifiers -or $targetIdentifiers.Count -eq 0) { continue }

                $matched = $false
                foreach ($targetIdentifier in $targetIdentifiers) {
                    if (_Test-TextsContainNeedle -Texts $sourceTexts -Needle $targetIdentifier) {
                        $matched = $true
                        break
                    }
                }

                if (-not $matched) { continue }

                _New-TrackedRelation -CompanyName $c.name -FromType $source.type -FromId $source.item.id -FromName $sourceName -ToType $target.type -ToId $target.item.id -ToName $target.item.name -RelationLabel $target.label -SeenRelations $companySeenRelations -DryRun:$dryRun
            }
        }
    }
    if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}

}
function Get-HuduCompanyFromName {
    # use index first. Then existing list. Then API call.
    param (
        [Parameter(Mandatory = $true)]
        [string]$CompanyName,
        [array]$HuduCompanies,
        [bool]$includenicknames = $false,
        [bool]$deepCompanySearch = $false
    )
    if ([string]::IsNullOrWhiteSpace($CompanyName)) { return $null }

        $normalizedCompanyName = normalize-companyName -Text $CompanyName
    # matched first
    $matchedCompany = $null
    if ($deepCompanySearch -eq $true){
        $matchedCompany = get-huducompanies | Where-Object {$(normalize-companyName -Text $_.name) -ieq (normalize-companyName -Text $normalizedCompanyName)} | Select-Object -First 1
    }

    if ($null -ne $matchedCompany){
      $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
      write-host "matched company using prematched companies: $($matchedCompany.name)"
      return $matchedCompany
    }    

    # then existing list
    $matchedCompany = $matchedCompany ?? $HuduCompanies | where-object {
            ($_.name -ieq $CompanyName) -or
            [bool]$(test-equiv -A $_.name -B $CompanyName)`
        } | Select-Object -First 1

    if ($true -eq $includenicknames){
        $matchedCompany =$matchedCompany ?? $HuduCompanies | where-object {
                ($_.nickname -ieq $CompanyName) -or
                [bool]$(test-equiv -A $_.nickname -B $CompanyName)`
            } | Select-Object -First 1
    }
    if ($null -ne $matchedCompany){
      $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
      write-host "matched company using companies array: $($matchedCompany.name)"
      return $matchedCompany
    }


    # finally API call
    if ($deepCompanySearch -eq $false){return $matchedCompany}

    $matchedCompany = $matchedCompany ?? $(Get-HuduCompanies -Name $CompanyName | select-object -first 1)
    if ($null -eq $matchedCompany){
          $matchedCompany = $matchedCompany ?? $(Get-HuduCompanies) | where-object {
            ($_.name -ieq $CompanyName) -or
            [bool]$(test-equiv -A $_.name -B $CompanyName) -or 
            ($normalizedCompanyName -ieq (normalize-companyName -Text $_.name))  -or
            ($normalizedCompanyName -icontains (normalize-companyName -Text $_.name)) 
        } | Select-Object -First 1
    }
    if ($null -ne $matchedCompany){
      write-host "matched company using API call: $($matchedCompany.name)"
      $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
      return $matchedCompany
    }
    $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
    return $matchedCompany
}

function Get-EnsuredPath {
    param([string]$path)
    $outpath = if (-not $path -or [string]::IsNullOrWhiteSpace($path)) { $(join-path $(Resolve-Path .).path "debug") } else {$path}
    if (-not (Test-Path $outpath)) {
        Get-ChildItem -Path "$outpath" -File -Recurse -Force | Remove-Item -Force
        New-Item -ItemType Directory -Path $outpath -Force -ErrorAction Stop | Out-Null
        write-host "path is now present: $outpath"
    } else {write-host "path is present: $outpath"}
    return $outpath
}

function Get-ContainsStringInsensitive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$String,

        [Parameter(Mandatory)]
        [string]$Substring
    )

    return [string]::IndexOf($String, $Substring, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}
function Get-StringVariants {
    param(
        [Parameter(Mandatory)][string]$InputString
    )

    # normalize consecutive spaces/underscores to single space
    $normalized = ($InputString -replace '[_\s]+', ' ').Trim()

    # TitleCase
    $titleWords = $normalized -split '\s+' | ForEach-Object {
        if ($_ -and $_.Length -gt 0) {
            $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
        }
    }
    $titleCase = ($titleWords) -join ' '

    # snake_case
    $snakeCase = ($normalized -replace '\s+', '_').ToLower()

    $variants = @(
        $titleCase
        ($titleCase -replace '\s+', '_')
        ($titleCase -replace '[_\s]+', '')
        ($snakeCase -replace '_', ' ')
        $snakeCase
        ($snakeCase -replace '[_\s]+', '')
    )

    # uniquify case-insensitively, preserving first occurrence
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($v in $variants) {
        if ([string]::IsNullOrEmpty($v)) { continue }
        if ($set.Add($v)) { [void]$out.Add($v) }
    }
    return $out.ToArray()
}
function Get-HTTPDecodedString {
  param([Parameter(ValueFromPipeline)][string]$InputString)
  if ($null -eq $InputString) { return $null }
  $s = [System.Net.WebUtility]::UrlDecode($InputString)
  $s = [System.Net.WebUtility]::HtmlDecode($s)
  return $s
}
function Write-InspectObject {
    param (
        [object]$object,
        [int]$Depth = 32,
        [int]$MaxLines = 16
    )

    $stringifiedObject = $null

    if ($null -eq $object) {
        return "Unreadable Object (null input)"
    }
    # Try JSON
    $stringifiedObject = try {
        $json = $object | ConvertTo-Json -Depth $Depth -ErrorAction Stop
        "# Type: $($object.GetType().FullName)`n$json"
    } catch { $null }

    # Try Format-Table
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-Table -Force | Out-String
        } catch { $null }
    }

    # Try Format-List
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-List -Force | Out-String
        } catch { $null }
    }

    # Fallback to manual property dump
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $props = $object | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
            $lines = foreach ($p in $props) {
                try {
                    "$p = $($object.$p)"
                } catch {
                    "$p = <unreadable>"
                }
            }
            "# Type: $($object.GetType().FullName)`n" + ($lines -join "`n")
        } catch {
            "Unreadable Object"
        }
    }

    if (-not $stringifiedObject) {
        $stringifiedObject =  try {"$($($object).ToString())"} catch {$null}
    }
    # Truncate to max lines if necessary
    $lines = $stringifiedObject -split "`r?`n"
    if ($lines.Count -gt $MaxLines) {
        $lines = $lines[0..($MaxLines - 1)] + "... (truncated)"
    }

    return $lines -join "`n"
}

function Write-ErrorObjectsToFile {
    param (
        [Parameter(Mandatory)]
        [object]$ErrorObject,

        [Parameter()]
        [string]$Name = "unnamed",

        [Parameter()]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color
    )

    $stringOutput = try {
        $ErrorObject | Format-List -Force | Out-String
    } catch {
        "Failed to stringify object: $_"
    }

    $propertyDump = try {
        $props = $ErrorObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $lines = foreach ($p in $props) {
            try {
                "$p = $($ErrorObject.$p)"
            } catch {
                "$p = <unreadable>"
            }
        }
        $lines -join "`n"
    } catch {
        "Failed to enumerate properties: $_"
    }

    $logContent = @"
==== OBJECT STRING ====
$stringOutput

==== PROPERTY DUMP ====
$propertyDump
"@

    if ($ErroredItemsFolder -and (Test-Path $ErroredItemsFolder)) {
        $SafeName = ($Name -replace '[\\/:*?"<>|]', '_') -replace '\s+', ''
        if ($SafeName.Length -gt 60) {
            $SafeName = $SafeName.Substring(0, 60)
        }
        $filename = "${SafeName}_error_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $fullPath = Join-Path $ErroredItemsFolder $filename
        Set-Content -Path $fullPath -Value $logContent -Encoding UTF8
        if ($Color) {
            Write-Host "Error written to $fullPath" -ForegroundColor $Color
        } else {
            Write-Host "Error written to $fullPath"
        }
    }

    if ($Color) {
        Write-Host "$logContent" -ForegroundColor $Color
    } else {
        Write-Host "$logContent"
    }
}

function Convert-ToSnakeCase {
    param([Parameter(Mandatory)][string]$Text)
    $t = $Text.Trim()
    # collapse spaces/punctuation -> underscore, lower-case
    $t = ($t -replace '[^A-Za-z0-9]+','_').Trim('_').ToLowerInvariant()
    return $t
}

function Save-HtmlSnapshot {
    param (
        [Parameter(Mandatory)][string]$PageId,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Suffix,
        [Parameter(Mandatory)][string]$OutDir
    )

    $safeTitle = ($Title -replace '[^\w\d\-]', '_') -replace '_+', '_'
    $filename = "${PageId}_${safeTitle}_${Suffix}.html"
    $path = Join-Path -Path $OutDir -ChildPath $filename

    try {
        $Content | Out-File -FilePath $path -Encoding UTF8
        Write-Host "Saved HTML snapshot: $path"
    } catch {
        Write-ErrorObjectsToFile -Name "$($_.safeTitle ?? "unnamed")" -ErrorObject @{
            Error       = $_
            PageId      = $PageId 
            Content     = $Content
            Message     ="Error Saving HTML Snapshot"
            OutDir      = $OutDir
        }
    }
}
function Get-PercentDone {
    param (
        [int]$Current,
        [int]$Total
    )
    if ($Total -eq 0) {
        return 100}
    $percentDone = ($Current / $Total) * 100
    if ($percentDone -gt 100){
        return 100
    }
    $rounded = [Math]::Round($percentDone, 2)
    return $rounded
}   
function Set-PrintAndLog {
    param (
        [string]$message,
        [Parameter()]
        [Alias("ForegroundColor")]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color
    )
    $logline = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    if ($Color) {
        Write-Host $logline -ForegroundColor $Color
    } else {
        Write-Host $logline
    }
    Add-Content -Path $LogFile -Value $logline
}
function Select-ObjectFromList($objects, $message, $inspectObjects = $false, $allowNull = $false) {
    $validated = $false
    while (-not $validated) {
        if ($allowNull) {
            Write-Host "0: None/Custom"
        }

        for ($i = 0; $i -lt $objects.Count; $i++) {
            $object = $objects[$i]

            $displayLine = if ($inspectObjects) {
                "$($i+1): $(Write-InspectObject -object $object)"
            } elseif ($null -ne $object.OptionMessage) {
                "$($i+1): $($object.OptionMessage)"
            } elseif ($null -ne $object.name) {
                "$($i+1): $($object.name)"
            } else {
                "$($i+1): $($object)"
            }

            Write-Host $displayLine -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }

        $choice = Read-Host $message

        if (-not [int]::TryParse($choice, [ref]$choice)) {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
            continue
        }

        if ($choice -eq 0 -and $allowNull) {
            return $null
        }

        if ($choice -ge 1 -and $choice -le $objects.Count) {
            return $objects[$choice - 1]
        } else {
            Write-Host "Invalid selection. Please enter a number from the list." -ForegroundColor Red
        }
    }
}



function Get-ArticlePreviewBlock {
    param (
        [string]$Title,
        [string]$docId,
        [string]$Content,
        [int]$MaxLength = 200
    )
    $descriptor = "ID: $docId, titled $Title"
    $snippet = if ($Content.Length -gt $MaxLength) {
        $Content.Substring(0, $MaxLength) + "..."
    } else {
        $Content
    }

@"
Mapping Passportal Page $descriptor ---
Title: $Title
Snippet: $snippet
"@
}


function Get-SafeFilename {
    param([string]$Name,
        [int]$MaxLength=25
    )

    # If there's a '?', take only the part before it
    $BaseName = $Name -split '\?' | Select-Object -First 1

    # Extract extension (including the dot), if present
    $Extension = [System.IO.Path]::GetExtension($BaseName)
    $NameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BaseName)

    # Sanitize name and extension
    $SafeName = $NameWithoutExt -replace '[\\\/:*?"<>|]', '_'
    $SafeExt = $Extension -replace '[\\\/:*?"<>|]', '_'

    # Truncate base name to 25 chars
    if ($SafeName.Length -gt $MaxLength) {
        $SafeName = $SafeName.Substring(0, $MaxLength)
    }

    return "$SafeName$SafeExt"
}

function New-HuduStubArticle {
    param (
        [string]$Title,
        [string]$Content,
        [nullable[int]]$CompanyId,
        [nullable[int]]$FolderId
    )

    $params = @{
        Name    = $Title
        Content = $Content
    }

    if ($CompanyId -ne $null -and $CompanyId -ne -1) {
        $params.CompanyId = $CompanyId
    }

    if ($FolderId -ne $null -and $FolderId -ne 0) {
        $params.FolderId = $FolderId
    }

    return (New-HuduArticle @params).article
}

function Get-SafeTitle {
    param ([string]$Name)

    if (-not $Name) {
        return "untitled"
    }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $decoded = [uri]::UnescapeDataString($baseName)
    $safe = $decoded -replace '[\\/:*?"<>|]', ' '
    $safe = ($safe -replace '\s{2,}', ' ').Trim()
    return $safe
}
function Set-Capitalized {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }
    return $text.Substring(0,1).ToUpper() + $text.Substring(1)
}
function Get-JsonString {
    param (
        $object
    )
    try {
        $value= "$($($object | convertto-json -depth 90).ToString())"
    } catch {
        $value = "$($object)"
    }
    return $value
}
