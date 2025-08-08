foreach ($PPcompany in $PassportalData.Clients) {
    foreach ($doctype in $passportalData.docTypes) {
        $ObjectsForTransfer = $passportaldata.Documents.data | where-object {$_.type -eq $doctype -and $($_.client_id -eq $PPcompany.id -or $_.clientName -eq $PPcompany.decodedName)}
        write-host $ObjectsForTransfer.count
        foreach ($obj in $ObjectsForTransfer) {
                Write-host "$($($obj | Converto-json -depth 55).ToString())"
                $docFields = $passportalData.documents.details | Where-Object { $_.ID -eq $obj.data.id }
                $fieldMap = Get-PassportalFieldMapForType -Type $doctype
                $formattedFields = $(Build-HuduFieldsFromDocument -FieldMap $fieldMap -sourceFields $docFields -docId $obj.id)
                Write-host "$($($docFields | Converto-json -depth 55).ToString())"
                Write-host "$($($fieldMap | Converto-json -depth 55).ToString())"
                Write-host "$($($formattedFields | Converto-json -depth 55).ToString())"


            }
    }
}