 <#
.SYNOPSIS
  Windows Server 2022 Core (PowerShell 5.1) Interactive Active Directory Forest Deployment Script
.DESCRIPTION
  - Compatible with Server Core PowerShell 5.1 and English environment
  - Interactive input for domain name, NetBIOS name, DSRM password, AD paths
  - Creates AD database, log, and SYSVOL folders following Microsoft best practices
  - Installs AD DS and DNS features and promotes the server to forest root DC
.NOTES
  - Run as Administrator
  - Ensure static IP is configured before promoting to DC
#>

#region Set UTF-8 console output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001
#endregion

#region Helper functions & prechecks
function Assert-RunningAsAdmin {
    if (-not ([bool]([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        Write-Host "This script must be run as Administrator. Please restart PowerShell as Administrator." -ForegroundColor Red
        exit 1
    }
}

function Prompt-Default([string]$PromptText, [string]$Default) {
    $input = Read-Host "$PromptText [$Default]"
    if ([string]::IsNullOrWhiteSpace($input)) { return $Default } else { return $input }
}

function Ensure-Folder([string]$Path) {
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Host "Created folder: $Path"
    }
}

function Confirm-Continue([string]$Message) {
    do {
        $ans = Read-Host "$Message (Y/N)"
        if ($ans -match '^[Yy]') { return $true }
        if ($ans -match '^[Nn]') { return $false }
    } while ($true)
}

function Test-StaticIP {
    $adapters = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' }
    if (-not $adapters) { return $false }
    foreach ($a in $adapters) {
        if ($a.Dhcp -eq $true) { return $false }
    }
    return $true
}
#endregion

# --- Start script ---
Assert-RunningAsAdmin

Write-Host "=== Windows Server 2022 Core - Interactive Active Directory Deployment ===`n" -ForegroundColor Cyan

# Default values
$defaultDomain = "contoso.local"
$defaultSafeModeUser = "Administrator"
$defaultNetbios = "CONTOSO"
$defaultDBPath = "C:\NTDS"
$defaultLogPath = "C:\NTDS\Logs"
$defaultSysvolPath = "C:\SYSVOL"
$defaultForestLevel = "Windows2016Forest"
$defaultDomainLevel = "Windows2016Domain"

# 1) User input
$DomainName = Prompt-Default "Enter the new forest root domain FQDN" $defaultDomain
$NetBiosName = Prompt-Default "Enter NetBIOS name (short name)" $defaultNetbios
$SafeModeAccount = Prompt-Default "Enter DSRM account name" $defaultSafeModeUser

Write-Host "Enter the DSRM password (must enter twice for confirmation):" -ForegroundColor Yellow
$dsrmPlain1 = Read-Host -AsSecureString "DSRM Password (input 1)"
$dsrmPlain2 = Read-Host -AsSecureString "DSRM Password (input 2)"
if (-not (Compare-Object (ConvertFrom-SecureString $dsrmPlain1) (ConvertFrom-SecureString $dsrmPlain2) -SyncWindow 0)) {
    Write-Host "DSRM passwords do not match. Exiting." -ForegroundColor Red
    exit 1
}
$SafeModePassword = $dsrmPlain1

$DBPath = Prompt-Default "Enter AD database path (NTDS.dit)" $defaultDBPath
$LogPath = Prompt-Default "Enter AD log path" $defaultLogPath
$SYSVOLPath = Prompt-Default "Enter SYSVOL path" $defaultSysvolPath

$ForestMode = Prompt-Default "Forest functional level (recommended: Windows2016Forest)" $defaultForestLevel
$DomainMode = Prompt-Default "Domain functional level (recommended: Windows2016Domain)" $defaultDomainLevel

$DNSDelegation = Read-Host "Enter parent DNS name if DNS delegation is required (leave empty to skip)"

# 2) Environment check
Write-Host "`n=== Environment Check ===" -ForegroundColor Cyan
if (Get-Service -Name NTDS -ErrorAction SilentlyContinue) {
    Write-Host "This server is already a domain controller. Script is intended for new forest root DC only." -ForegroundColor Red
    exit 1
}

if (-not (Test-StaticIP)) {
    Write-Warning "DHCP is detected. Static IP is recommended."
    if (-not (Confirm-Continue "Do you want to continue?")) { exit 1 }
} else {
    Write-Host "Static IP configuration detected."
}

# 3) Show input summary
Write-Host "`n=== Input Summary ===" -ForegroundColor Cyan
Write-Host "Forest root domain: $DomainName"
Write-Host "NetBIOS name: $NetBiosName"
Write-Host "DSRM account: $SafeModeAccount"
Write-Host "AD database path: $DBPath"
Write-Host "AD log path: $LogPath"
Write-Host "SYSVOL path: $SYSVOLPath"
Write-Host "Forest functional level: $ForestMode"
Write-Host "Domain functional level: $DomainMode"

if ($DNSDelegation -ne '') {
    Write-Host "DNS delegation: $DNSDelegation"
} else {
    Write-Host "DNS delegation: (none)"
}

if (-not (Confirm-Continue "Do you want to continue?")) { exit 0 }

# 4) Create folders
Write-Host "`n=== Creating Folders ===" -ForegroundColor Cyan
Ensure-Folder -Path $DBPath
Ensure-Folder -Path $LogPath
Ensure-Folder -Path $SYSVOLPath
Write-Host "Folders are ready. ADDS installation will set required permissions."

# 5) Install Windows features
Write-Host "`n=== Installing AD DS and DNS Features ===" -ForegroundColor Cyan
$features = @('AD-Domain-Services','DNS')
foreach ($f in $features) {
    $installed = Get-WindowsFeature -Name $f
    if ($installed.Installed) {
        Write-Host "Feature $f is already installed."
    } else {
        Install-WindowsFeature -Name $f -IncludeManagementTools -Verbose
        $installed = Get-WindowsFeature -Name $f
        if (-not $installed.Installed) {
            Write-Host "Failed to install feature $f. Exiting." -ForegroundColor Red
            exit 1
        }
        Write-Host "Feature $f installed successfully."
    }
}

# 6) Optional DNS forwarder configuration
$setForwarders = $false
if (Confirm-Continue "Do you want to configure DNS forwarders? (recommended)") {
    $setForwarders = $true
    $forwardersInput = Read-Host "Enter upstream DNS IPv4 addresses (comma-separated, e.g., 8.8.8.8,1.1.1.1)"
    $forwarders = ($forwardersInput -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}

# 7) Promote to forest root DC
Write-Host "`n=== Promoting to Forest Root DC ===" -ForegroundColor Cyan
$installParams = @{
    DomainName = $DomainName
    DomainNetbiosName = $NetBiosName
    SafeModeAdministratorPassword = $SafeModePassword
    DatabasePath = $DBPath
    LogPath = $LogPath
    SysvolPath = $SYSVOLPath
    InstallDNS = $true
    CreateDNSDelegation = $false
    NoRebootOnCompletion = $false
    Force = $true
}

# Set forest and domain functional levels
try {
    $installParams['ForestMode'] = [Microsoft.ActiveDirectory.Management.ADForestMode]::$ForestMode
    $installParams['DomainMode'] = [Microsoft.ActiveDirectory.Management.ADDomainMode]::$DomainMode
} catch {
    Write-Warning "Invalid functional level specified. Default levels will be used."
    $installParams.Remove('ForestMode') | Out-Null
    $installParams.Remove('DomainMode') | Out-Null
}

if ($DNSDelegation -ne '') {
    $installParams['CreateDNSDelegation'] = $true
}

Write-Host "`nAbout to run Install-ADDSForest and restart the server." -ForegroundColor Yellow
if (-not (Confirm-Continue "Start installation?")) { exit 0 }

# Execute AD DS promotion
try {
    Install-ADDSForest @installParams -Verbose -ErrorAction Stop
} catch {
    Write-Host "Install-ADDSForest failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Script Completed ===" -ForegroundColor Green
Write-Host "The server will automatically restart to complete domain controller installation."
Write-Host "After reboot, verify AD and DNS services."

 
