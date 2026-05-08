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
            @{ label="Name"; field_type="Text" },
            @{ label="Manufacturer"; field_type="Text" },
            @{ label="Assigned User"; field_type="Text" },
            @{ label="Purchased By"; field_type="Text" },
            @{ label="Model"; field_type="Text" },
            @{ label="Serial Number"; field_type="Text" },
            @{ label="Purchase Date (YYYY-MM-DD)"; field_type="Date" },
            @{ label="Type"; field_type="Text" },
            @{ label="Asset Tag"; field_type="Text" },
            @{ label="Hostname"; field_type="Text" },
            @{ label="Status"; field_type="Text" },
            @{ label="Platform"; field_type="Text" },
            @{ label="Primary IP"; field_type="Text" },
            @{ label="Default Gateway"; field_type="Text" },
            @{ label="MAC Address"; field_type="Text" },
            @{ label="Location"; field_type="Text" },
            @{ label="Operating System"; field_type="Text" },
            @{ label="Operating System Notes"; field_type="RichText" },
            @{ label="Portal URL"; field_type="Text" },
            @{ label="Remote Launch URL"; field_type="Text" },
            @{ label="Integration Type"; field_type="Text" },
            @{ label="Last Logged in User"; field_type="Text" },
            @{ label="Install Date (YYYY-MM-DD)"; field_type="Date" },
            @{ label="Installed By"; field_type="Text" },
            @{ label="Expiration Date (YYYY-MM-DD)"; field_type="Date" },
            @{ label="Notes"; field_type="RichText" }
        )
        active_directory = @(
            @{ label="AD Full Name"; field_type="Text" },
            @{ label="AD Short Name"; field_type="Text" },
            @{ label="AD Level"; field_type="Text" },
            @{ label="AD Servers"; field_type="Text" },
            @{ label="DNS Servers"; field_type="Text" },
            @{ label="DHCP Servers"; field_type="Text" },
            @{ label="Domain Credentials"; field_type="Text" },
            @{ label="Directory Services Restore Mode Password"; field_type="Password" },
            @{ label="Domain Naming Master"; field_type="Text" },
            @{ label="Infrastructure Master"; field_type="Text" },
            @{ label="PDC Emulator"; field_type="Text" },
            @{ label="RID Master"; field_type="Text" },
            @{ label="Schema Master"; field_type="Text" },
            @{ label="GPO(s)"; field_type="RichText" },
            @{ label="Notes"; field_type="RichText" }
        )
        application = @(
            @{ label="Application Name"; field_type="Text" },
            @{ label="Category"; field_type="Text" },
            @{ label="Version"; field_type="Text" },
            @{ label="Vendor"; field_type="Text" },
            @{ label="Importance"; field_type="Text" },
            @{ label="Business Impact"; field_type="Text" },
            @{ label="Customer Account Number"; field_type="Text" },
            @{ label="Application Champion"; field_type="Text" },
            @{ label="Application Servers"; field_type="Text" },
            @{ label="Application Administrator Credentials"; field_type="Text" },
            @{ label="Application Service Account"; field_type="Text" },
            @{ label="Licensing Information"; field_type="RichText" },
            @{ label="Workstation Install Guide"; field_type="RichText" },
            @{ label="Knowlege Base Articles"; field_type="RichText" },
            @{ label="Additional Notes"; field_type="RichText" }
        )
        backup = @(
            @{ label="Backup Technology"; field_type="Text" },
            @{ label="Backup Type"; field_type="Text" },
            @{ label="Backup Job Description"; field_type="Text" },
            @{ label="Protected Servers"; field_type="Text" },
            @{ label="Protected Files"; field_type="RichText" },
            @{ label="Protected Applications"; field_type="RichText" },
            @{ label="Backup Frequency"; field_type="Text" },
            @{ label="Backup Window"; field_type="Text" },
            @{ label="Backup Account Credentials"; field_type="Text" },
            @{ label="Backup Job Encryption Password"; field_type="Text" },
            @{ label="Backup Service Account"; field_type="Text" },
            @{ label="Data Recovery Approver"; field_type="Text" },
            @{ label="Next Restore Verification Date"; field_type="Date" },
            @{ label="Local Backup Type"; field_type="Text" },
            @{ label="Local Backup Server"; field_type="Text" },
            @{ label="Local Backup Location"; field_type="Text" },
            @{ label="Local Retention"; field_type="Text" },
            @{ label="Offsite Replication"; field_type="Text" },
            @{ label="Offsite Location"; field_type="Text" },
            @{ label="Offsite Retention"; field_type="Text" },
            @{ label="Notes"; field_type="RichText" }
        )
        email = @(
            @{ label="Email Type"; field_type="Text" },
            @{ label="Domain(s)"; field_type="Text" },
            @{ label="Location"; field_type="Text" },
            @{ label="Email Servers"; field_type="Text" },
            @{ label="Webmail URL"; field_type="Text" },
            @{ label="Client Admin Portal URL"; field_type="Text" },
            @{ label="Client Admin Credentials"; field_type="Text" },
            @{ label="Inbound Delivery"; field_type="Text" },
            @{ label="Outbound Delivery"; field_type="Text" },
            @{ label="Email Archiving"; field_type="Text" },
            @{ label="Email Backups"; field_type="Text" },
            @{ label="Outbound Email Encryption"; field_type="Text" },
            @{ label="Knowledge Base Articles"; field_type="RichText" },
            @{ label="Additional Notes"; field_type="RichText" }
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
            @{ label="Share Local Path"; field_type="Text" },
            @{ label="Local Server Disk Path"; field_type="Text" },
            @{ label="Mapped Drive"; field_type="Text" },
            @{ label="Mapped By"; field_type="Text" },
            @{ label="Security Group(s)"; field_type="Text" },
            @{ label="Authorization Required"; field_type="Text" },
            @{ label="Point of Contact for Authorization"; field_type="Text" },
            @{ label="Cloud File Sharing Solution"; field_type="Text" },
            @{ label="Cloud File Sharing Administator"; field_type="Text" },
            @{ label="Cloud File Sharing Client Installer"; field_type="Text" },
            @{ label="Cloud File Sharing Install Guide"; field_type="RichText" },
            @{ label="GPO(s)"; field_type="RichText" },
            @{ label="Notes"; field_type="RichText" }
        )
        contact = @(
            @{ label="Contact Type"; field_type="Text" },
            @{ label="Primary Contact"; field_type="Text" },
            @{ label="Job Title"; field_type="Text" },
            @{ label="First Name"; field_type="Text" },
            @{ label="Middle Name"; field_type="Text" },
            @{ label="Last Name"; field_type="Text" },
            @{ label="Location"; field_type="Text" },
            @{ label="Phone"; field_type="Phone" },
            @{ label="Mobile Phone"; field_type="Phone" },
            @{ label="Extension"; field_type="Text" },
            @{ label="Fax"; field_type="Text" },
            @{ label="Email Address"; field_type="Text" },
            @{ label="Notes"; field_type="RichText" }
        )
        location = @(
            @{ label="Name"; field_type="Text" },
            @{ label="Address"; field_type="Text" },
            @{ label="Address 1"; field_type="Text" },
            @{ label="Address 2"; field_type="Text" },
            @{ label="Suite / Unit"; field_type="Text" },
            @{ label="City"; field_type="Text" },
            @{ label="State / Province"; field_type="Text" },
            @{ label="ZIP / Postal Code"; field_type="Text" },
            @{ label="Country"; field_type="Text" },
            @{ label="Fax"; field_type="Text" },
            @{ label="Phone"; field_type="Phone" },
            @{ label="Emergency Contact"; field_type="Text" },
            @{ label="Hours of Operation"; field_type="RichText" },
            @{ label="Floor Plan"; field_type="RichText" },
            @{ label="Notes"; field_type="RichText" }
        )
        internet = @(
            @{ label="Internet Service Provider"; field_type="Text" },
            @{ label="Link Type"; field_type="Text" },
            @{ label="Customer Account Number"; field_type="Text" },
            @{ label="Location"; field_type="Text" },
            @{ label="Download Speed (Mbps)"; field_type="Text" },
            @{ label="Upload Speed (Mpbs)"; field_type="Text" },
            @{ label="Primary Public IP Address"; field_type="Text" },
            @{ label="Public Gateway"; field_type="Text" },
            @{ label="Public Subnet Mask"; field_type="Text" },
            @{ label="DNS Servers"; field_type="Text" },
            @{ label="Router/Firewall"; field_type="Text" },
            @{ label="SLA"; field_type="Text" },
            @{ label="Login/PIN"; field_type="Password" },
            @{ label="Authorized User(s)"; field_type="Text" },
            @{ label="Copy of Invoice"; field_type="Text" },
            @{ label="Additional Notes (IP Addresses)"; field_type="RichText" }
        )
        lan = @(
            @{ label="Location"; field_type="Text" },
            @{ label="Subnet"; field_type="Text" },
            @{ label="VLAN"; field_type="Text" },
            @{ label="VLAN ID"; field_type="Text" },
            @{ label="Router/Firewall"; field_type="Text" },
            @{ label="DHCP Server"; field_type="Text" },
            @{ label="DHCP Scope"; field_type="Text" },
            @{ label="DNS Server(s)"; field_type="Text" },
            @{ label="DNS Settings"; field_type="RichText" },
            @{ label="Network Switches"; field_type="RichText" },
            @{ label="Wireless Devices"; field_type="RichText" },
            @{ label="Network Diagram"; field_type="RichText" }
        )
        printing = @(
            @{ label="Connection Type"; field_type="Text" },
            @{ label="Print Drivers Path"; field_type="Text" },
            @{ label="Print Server(S)"; field_type="Text" },
            @{ label="Printers"; field_type="RichText" },
            @{ label="Site"; field_type="Text" },
            @{ label="Support Vendor"; field_type="Text" },
            @{ label="Deployment"; field_type="Text" },
            @{ label="Install Guide"; field_type="RichText" },
        )
        remote_access = @(
            @{ label="Remote Access Technology"; field_type="Text" },
            @{ label="Remote Access URL"; field_type="Text" },
            @{ label="Remote Access Server"; field_type="Text" },
            @{ label="Client Remote Access Software"; field_type="Text" },
            @{ label="Authorized User(s)"; field_type="Text" },
            @{ label="2FA Type"; field_type="Text" },
            @{ label="2FA Details"; field_type="RichText" },
            @{ label="Notes"; field_type="RichText" }
        )
        vendor = @(
            @{ label="Vendor Name"; field_type="Text" },
            @{ label="Vendor Website"; field_type="Text" },
            @{ label="Vendor Support URL"; field_type="Text" },
            @{ label="Support Phone Number"; field_type="Text" },
            @{ label="Support Email Address"; field_type="Text" }
        )
        virtualization = @(
            @{ label="Hypervisor"; field_type="Text" },
            @{ label="Virtualization Technology"; field_type="Text" },
            @{ label="Virtual Hosts"; field_type="RichText" },
            @{ label="Virtual Machines"; field_type="RichText" },
            @{ label="Primary Host IP"; field_type="Text" }
        )
        voice = @(
            @{ label="Phone System"; field_type="Text" },
            @{ label="SIP Provider"; field_type="Text" },
            @{ label="Main Number"; field_type="Text" },
            @{ label="Phone System Type"; field_type="Text" },
            @{ label="DHCP Options"; field_type="Text" },
            @{ label="Phone Support Vendor"; field_type="Text" }
        )
        wireless = @(
            @{ label="SSID"; field_type="Text" },
            @{ label="Password"; field_type="Password" },
            @{ label="Encryption Type"; field_type="Text" },
            @{ label="Management IP Address"; field_type="Text" },
            @{ label="Guest Network"; field_type="Text" },
            @{ label="Encryption Type"; field_type="Text" },
            @{ label="Pre-Shared Key"; field_type="Password" },
            @{ label="Access Point(S)"; field_type="Text" },
            @{ label="Encryption Type"; field_type="Text" },
            @{ label="Notes"; field_type="RichText" },
            @{ label="Security Type"; field_type="Text" }
        )
        licencing = @(
            @{ label="Software"; field_type="Text" },
            @{ label="Software Name"; field_type="Text" },
            @{ label="Purchase Date"; field_type="Text" },
            @{ label="License Key(S)"; field_type="Text" },
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
    $rawFields = @($fieldMap[$Type.ToLower()] ?? @())
    $rawFields += @{label="PassPortalID"; field_type="Text"}

    $fields = [System.Collections.Generic.List[object]]::new()
    $seenLabels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($field in $rawFields) {
        if (-not $field.label) { continue }
        $lookupLabel = if (Get-Command ConvertTo-PassportalLookupKey -ErrorAction SilentlyContinue) {
            ConvertTo-PassportalLookupKey $field.label
        } else {
            "$($field.label)".Trim().ToLowerInvariant()
        }
        if ([string]::IsNullOrWhiteSpace($lookupLabel)) { continue }
        if ($seenLabels.Add($lookupLabel)) {
            [void]$fields.Add($field)
        }
    }

    for ($i = 0; $i -lt $fields.Count; $i++) {
        $fields[$i].position = $i + 1
    }
    return $fields.ToArray()
}
