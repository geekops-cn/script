 <#
.SYNOPSIS
  Active Directory Enhanced Post-Deployment Check Script
.DESCRIPTION
  - For Windows Server 2022 Core (English) after AD DS forest root DC deployment
  - Collects server basic info, AD deployment status, DNS, SYSVOL, replication
  - Outputs a detailed HTML report for validation
.NOTES
  - Run as Administrator
#>

#region UTF-8 Output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001
#endregion

#region Config
$ReportPath = "C:\AD_Enhanced_PostDeployment_Report.html"
$ServicesToCheck = @("NTDS","DNS")
$FeaturesToCheck = @("AD-Domain-Services","DNS")
$FoldersToCheck = @("C:\NTDS","C:\NTDS\Logs","C:\SYSVOL")
#endregion

#region Helper Functions
function Test-ServiceStatus { param([string]$Name) $s = Get-Service -Name $Name -ErrorAction SilentlyContinue; if ($s) { @{Status=$s.Status; Exists=$true} } else { @{Status="NotFound"; Exists=$false} } }
function Test-WindowsFeatureInstalled { param([string]$Name) $f = Get-WindowsFeature -Name $Name; $f.Installed }
function Test-FolderExists { param([string]$Path) Test-Path $Path }
#endregion

#region Collect Checks
$Checks = @()

Write-Host "`nStarting Enhanced Post-Deployment Checks..." -ForegroundColor Cyan

# 1) Server Basic Info
$serverInfo = Get-CimInstance Win32_ComputerSystem
$osInfo = Get-CimInstance Win32_OperatingSystem
$cpuCount = $serverInfo.NumberOfLogicalProcessors
$totalMemoryGB = [math]::Round($serverInfo.TotalPhysicalMemory / 1GB,2)
$diskInfo = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, @{Name="SizeGB";Expression={[math]::Round($_.Size/1GB,2)}}, @{Name="FreeGB";Expression={[math]::Round($_.FreeSpace/1GB,2)}}

$Checks += [PSCustomObject]@{Check="Server Name"; Status=$env:COMPUTERNAME; Pass="Yes"; Details=""}
$Checks += [PSCustomObject]@{Check="OS Version"; Status="$($osInfo.Caption) $($osInfo.Version)"; Pass="Yes"; Details=""}
$Checks += [PSCustomObject]@{Check="CPU Count"; Status=$cpuCount; Pass="Yes"; Details=""}
$Checks += [PSCustomObject]@{Check="Total Memory (GB)"; Status=$totalMemoryGB; Pass="Yes"; Details=""}
foreach ($d in $diskInfo) {
    $Checks += [PSCustomObject]@{Check="Disk $($d.DeviceID)"; Status="Total $($d.SizeGB) GB / Free $($d.FreeGB) GB"; Pass="Yes"; Details=""}
}
$ipAddresses = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" -ErrorAction SilentlyContinue).IPAddress -join ', '
$Checks += [PSCustomObject]@{Check="IPv4 Addresses"; Status=$ipAddresses; Pass="Yes"; Details=""}

# 2) Services
foreach ($svc in $ServicesToCheck) {
    $s = Test-ServiceStatus -Name $svc
    $Checks += [PSCustomObject]@{Check="Service $svc"; Status=$s.Status; Pass=if ($s.Status -eq "Running") {"Yes"} else {"No"}; Details=if ($s.Exists) {"Service exists"} else {"Not Found"}}
}

# 3) Windows Features
foreach ($f in $FeaturesToCheck) {
    $installed = Test-WindowsFeatureInstalled -Name $f
    $Checks += [PSCustomObject]@{Check="Feature $f"; Status=if ($installed) {"Installed"} else {"Not Installed"}; Pass=if ($installed) {"Yes"} else {"No"}; Details=""}
}

# 4) Folder & SYSVOL
foreach ($f in $FoldersToCheck) {
    $exists = Test-FolderExists -Path $f
    $shareStatus = if ($f -like "*SYSVOL*") { if (Get-SmbShare -Name SYSVOL -ErrorAction SilentlyContinue) {"SYSVOL share exists"} else {"SYSVOL share missing"} } else { "" }
    $Checks += [PSCustomObject]@{Check="Folder $f"; Status=if ($exists) {"Exists"} else {"Missing"}; Pass=if ($exists) {"Yes"} else {"No"}; Details=$shareStatus}
}

# 5) Domain & Forest
try {
    $domain = Get-ADDomain -ErrorAction Stop
    $forest = Get-ADForest -ErrorAction Stop
    $Checks += [PSCustomObject]@{Check="Domain Name"; Status=$domain.DNSRoot; Pass="Yes"; Details="NetBIOS: $($domain.NetBIOSName); Domain Mode: $($domain.DomainMode)"}
    $Checks += [PSCustomObject]@{Check="Forest Name"; Status=$forest.Name; Pass="Yes"; Details="Forest Mode: $($forest.ForestMode); Domain count: $($forest.Domains.Count)"}
} catch {
    $Checks += [PSCustomObject]@{Check="Domain/Forest Availability"; Status="Failed"; Pass="No"; Details=$_}
}

# 6) DNS Resolution
try {
    $dnsTest = Resolve-DnsName $env:COMPUTERNAME -ErrorAction Stop
    $Checks += [PSCustomObject]@{Check="DNS Resolution"; Status="Success"; Pass="Yes"; Details="Resolved IPs: $($dnsTest.IPAddress -join ', ')"} 
} catch {
    $Checks += [PSCustomObject]@{Check="DNS Resolution"; Status="Failed"; Pass="No"; Details=$_}
}

# 7) Domain Controllers
try {
    $DCs = Get-ADDomainController -Filter * | Select-Object Name,IPv4Address,IsGlobalCatalog,OperatingSystem
    foreach ($dc in $DCs) {
        $Checks += [PSCustomObject]@{Check="Domain Controller $($dc.Name)"; Status="$($dc.OperatingSystem), IP: $($dc.IPv4Address)"; Pass="Yes"; Details=if ($dc.IsGlobalCatalog) {"Global Catalog"} else {"Non-GC"}}
    }
} catch {
    $Checks += [PSCustomObject]@{Check="Domain Controller Discovery"; Status="Failed"; Pass="No"; Details=$_}
}

# 8) AD Replication Status
try {
    $repl = Get-ADReplicationPartnerMetadata -Scope Domain | Select-Object Server,LastReplicationAttempt,LastReplicationSuccess,Partner
    foreach ($r in $repl) {
        $Checks += [PSCustomObject]@{Check="Replication from $($r.Partner)"; Status="Last Attempt: $($r.LastReplicationAttempt)"; Pass=if($r.LastReplicationSuccess -ne $null) {"Yes"} else {"No"}; Details="Last Success: $($r.LastReplicationSuccess)"}
    }
} catch {
    $Checks += [PSCustomObject]@{Check="AD Replication Check"; Status="Failed"; Pass="No"; Details=$_}
}

#endregion

#region Generate HTML Report
$html = @"
<html>
<head>
<style>
body { font-family: Arial, sans-serif; background-color:#f4f4f4; color:#333; }
table { border-collapse: collapse; width: 95%; margin: 20px auto; }
th, td { border: 1px solid #ccc; padding: 8px; text-align: left; vertical-align: top; word-break: break-word; }
th { background-color: #4CAF50; color: white; }
tr:nth-child(even){ background-color: #f2f2f2; }
.PassYes { background-color: #c6efce; color: #006100; font-weight: bold; }
.PassNo { background-color: #ffc7ce; color: #9c0006; font-weight: bold; }
</style>
</head>
<body>
<h2 style="text-align:center;">Active Directory Post-Deployment Detailed Report</h2>
<table>
<tr><th>Check Item</th><th>Status</th><th>Pass</th><th>Details</th></tr>
"@

foreach ($c in $Checks) {
    $passClass = if ($c.Pass -eq "Yes") { "PassYes" } else { "PassNo" }
    $html += "<tr><td>$($c.Check)</td><td>$($c.Status)</td><td class='$passClass'>$($c.Pass)</td><td>$($c.Details)</td></tr>`n"
}

$html += @"
</table>
<p style='text-align:center;'>Report generated on $(Get-Date)</p>
</body>
</html>
"@

$html | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host "`nEnhanced post-deployment check completed. Report saved to $ReportPath" -ForegroundColor Green
#endregion
 
