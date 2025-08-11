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
            @{ label="Assigned User"; field_type="Text" },
            @{ label="Purchased By"; field_type="Text" },
            @{ label="Model"; field_type="Text" },
            @{ label="Serial Number"; field_type="Text" },
            @{ label="Purchase Date"; field_type="Date" },
            @{ label="Type"; field_type="Text" },
            @{ label="Asset Tag"; field_type="Text" },
            @{ label="Hostname"; field_type="Text" },
            @{ label="Status"; field_type="Text" },
            @{ label="Platform"; field_type="Text" },
            @{ label="Primary IP"; field_type="Text" },
            @{ label="Hostname"; field_type="Text" },
            @{ label="Operating System"; field_type="Text" },
            @{ label="Operating System Notes"; field_type="RichText" },
            @{ label="Notes"; field_type="RichText" }
        )
        active_directory = @(
            @{ label="AD Full Name"; field_type="Text" },
            @{ label="AD Short Name"; field_type="Text" },
            @{ label="AD Level"; field_type="Text" },
            @{ label="Domain Controller(S)"; field_type="Text" },
            @{ label="DNS Server(S)"; field_type="Text" },
            @{ label="DHCP Server(S)"; field_type="Text" },
            @{ label="Directory Services Restore Mode Password"; field_type="Password" },
            @{ label="Domain Controller IP"; field_type="Text" }
        )
        application = @(
            @{ label="Application Name"; field_type="Text" },
            @{ label="Title"; field_type="Text" },
            @{ label="License Key"; field_type="Text" },
            @{ label="Category"; field_type="Text" },
            @{ label="Version"; field_type="Text" }
            @{ label="Attachment Paths"; field_type="Text" }
            @{ label="Application Owner"; field_type="Text" }            
            @{ label="NOTES"; field_type="RichText" }
        )
        backup = @(
            @{ label="Backup Technology"; field_type="Text" },
            @{ label="Backup Description"; field_type="Text" },
            @{ label="Data Recovery Approver"; field_type="Text" },
            @{ label="Local Backup Server(S)"; field_type="Text" },
            @{ label="Backup Type"; field_type="Text" },
            @{ label="Backup Description"; field_type="Text" },
            @{ label="Backup Interval"; field_type="Text" },
            @{ label="Backup Window"; field_type="Text" },
            @{ label="Retention Policy"; field_type="Text" },
            @{ label="Notes"; field_type="RichText" },
            @{ label="Last Successful Backup"; field_type="Date" },
            @{ label="Next Test Restore Date"; field_type="Date" }
        )
        email = @(
            @{ label="Email Address"; field_type="Text" },
            @{ label="Email Type"; field_type="Password" },
            @{ label="Domain(s)"; field_type="Text" },
            @{ label="Email Servers"; field_type="Text" },
            @{ label="WebMail URL"; field_type="Text" },
            @{ label="Inbound Delivery"; field_type="Text" },
            @{ label="Notes"; field_type="RichText" }
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
            @{ label="Mapped Drive"; field_type="Text" },
            @{ label="File Share Permissions"; field_type="Text" },
            @{ label="User Accounts"; field_type="RichText" }
        )
        contact = @(
            @{ label="Contact Type"; field_type="Text" },
            @{ label="Primary Contact"; field_type="Text" },
            @{ label="Job Title"; field_type="Text" },
            @{ label="First Name"; field_type="Text" },
            @{ label="Last Name"; field_type="Text" },
            @{ label="Phone"; field_type="Phone" },
            @{ label="Notes"; field_type="RichText" },
            @{ label="Email"; field_type="Text" }
        )
        location = @(
            @{ label="Name"; field_type="Text" },
            @{ label="Address 1"; field_type="Text" },
            @{ label="Address 2"; field_type="Text" },
            @{ label="City"; field_type="Text" },
            @{ label="Country"; field_type="Text" },
            @{ label="State"; field_type="RichText" },
            @{ label="Fax"; field_type="Text" },
            @{ label="Phone"; field_type="Text" }
        )
        internet = @(
            @{ label="Internet Service Provider"; field_type="Text" },
            @{ label="Link Type"; field_type="Text" },
            @{ label="Account Number"; field_type="Text" },            
            @{ label="Download Speed (Mbps)"; field_type="Text" },            
            @{ label="Upload Speed (Mbps)"; field_type="Text" },            
            @{ label="SMTP Smarthost"; field_type="Text" },            
            @{ label="Subnet Mask"; field_type="Text" },            
            @{ label="Gateway(S)"; field_type="Text" },            
            @{ label="DNS Servers"; field_type="Text" },            
            @{ label="Gateway(S)"; field_type="Text" },            
            @{ label="Static IPs"; field_type="RichText" }
        )
        lan = @(
            @{ label="Device Name"; field_type="Text" },
            @{ label="IP Address"; field_type="Text" },
            @{ label="MAC Address"; field_type="Text" },
            @{ label="Port Number"; field_type="Text" }
            @{ label="Subnet Mask"; field_type="Text" },            
            @{ label="Gateway(S)"; field_type="Text" },            
            @{ label="DNS Servers"; field_type="Text" },            
            @{ label="Gateway(S)"; field_type="Text" }           
        )
        printing = @(
            @{ label="Connection Type"; field_type="Text" },
            @{ label="Print Drivers Path"; field_type="Text" },
            @{ label="Print Server(S)"; field_type="Text" },
            @{ label="Support Vendor"; field_type="Text" },
            @{ label="Notes"; field_type="RichText" },
            @{ label="Location"; field_type="Text" }
        )
        remote_access = @(
            @{ label="Site"; field_type="Text" },
            @{ label="Client VPN URL"; field_type="Text" },
            @{ label="Client VPN Installer"; field_type="Text" },
            @{ label="Remote Desktop"; field_type="Text" },
            @{ label="Webmail"; field_type="Text" },
            @{ label="Password"; field_type="Password" }
        )
        vendor = @(
            @{ label="Vendor Website"; field_type="Text" },
            @{ label="Vendor Support URL"; field_type="Text" },
            @{ label="Support Phone Number"; field_type="Text" },
            @{ label="Support Email"; field_type="Text" }
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
            @{ label="Main Number"; field_type="Text" }
            @{ label="Phone System Type"; field_type="Text" }
            @{ label="DHCP Options"; field_type="Text" }
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
    $fields = $fieldMap[$Type.ToLower()] ?? @()
    $fields+=@{label="PassPortalID"; field_type="Text"}
    for ($i = 0; $i -lt $fields.Count; $i++) {
        $fields[$i].position = $i + 1
    }
    return $fields
}
