 <#
.SYNOPSIS
Exchange Server 2022 Deployment Script (Supports First/Additional Server)
Author: System Administrator
Date: 2025-11-18
#>

param()

#===============================
# Logging Function
#===============================
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "WARNING"){"Yellow"}else{"Green"})
}

#===============================
# Check Domain Membership
#===============================
function Test-DomainMembership {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($computerSystem.PartOfDomain) {
        $domainName = $computerSystem.Domain
        $domainUser = "$env:USERDOMAIN\$env:USERNAME"
        
        Write-Log "Server is domain joined to: $domainName"
        Write-Log "Current user: $domainUser"
        
        return @{
            IsDomainJoined = $true
            DomainName = $domainName
            CurrentUser = $domainUser
            ComputerName = $env:COMPUTERNAME
        }
    } else {
        Write-Log "Server is not domain joined!" "ERROR"
        throw "Server must be domain joined before running this script."
    }
}

#===============================
# User Input Function
#===============================
function Get-UserInput {
    param(
        [string]$Prompt,
        [string]$DefaultValue = "",
        [switch]$Required = $true
    )
    
    do {
        if ($DefaultValue) {
            Write-Host "$Prompt (default: $DefaultValue): " -NoNewline -ForegroundColor Yellow
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $input = $DefaultValue
            }
        } else {
            Write-Host "$Prompt`: " -NoNewline -ForegroundColor Yellow
            $input = Read-Host
        }
        
        if ($Required -and [string]::IsNullOrWhiteSpace($input)) {
            Write-Host "This field is required." -ForegroundColor Red
        } else {
            break
        }
    } while ($true)

    return $input.Trim()
}

#===============================
# Install Windows Prerequisites
#===============================
function Install-Prerequisites {
    param([string]$ToolsPath)

    Write-Log "Installing Windows features..."

    $features = @(
        "Server-Media-Foundation","NET-Framework-45-Core","NET-Framework-45-ASPNET",
        "NET-WCF-HTTP-Activation45","NET-WCF-Pipe-Activation45","NET-WCF-TCP-Activation45",
        "NET-WCF-TCP-PortSharing45","RPC-over-HTTP-proxy","RSAT-Clustering",
        "RSAT-Clustering-CmdInterface","RSAT-Clustering-PowerShell","WAS-Process-Model",
        "Web-Asp-Net45","Web-Basic-Auth","Web-Client-Auth","Web-Digest-Auth",
        "Web-Dir-Browsing","Web-Dyn-Compression","Web-Http-Errors","Web-Http-Logging",
        "Web-Http-Redirect","Web-Http-Tracing","Web-ISAPI-Ext","Web-ISAPI-Filter",
        "Web-Metabase","Web-Mgmt-Service","Web-Net-Ext45","Web-Request-Monitor",
        "Web-Server","Web-Stat-Compression","Web-Static-Content","Web-Windows-Auth",
        "Web-WMI","RSAT-ADDS"
    )

    $total = $features.Count
    $i = 0

    foreach ($feature in $features) {
        $i++
        Write-Progress -Activity "Installing Windows Features" -Status "$feature" -PercentComplete (($i/$total)*100)

        $result = Install-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
        if ($result.Success) {
            Write-Log "Installed: $feature"
        } else {
            Write-Log "Failed: $feature" "WARNING"
        }
    }

    Write-Progress -Activity "Installing Windows Features" -Completed

    $unwanted = @("NET-WCF-MSMQ-Activation45","MSMQ")
    foreach ($item in $unwanted) {
        Write-Log "Removing feature: $item"
        Remove-WindowsFeature -Name $item -ErrorAction SilentlyContinue | Out-Null
    }

    # =====================================================================
    # 新?增?功|能¨¹：êo自Á?动¡¥下?载? vcredist 和¨ª URL Rewrite
    # =====================================================================

    if (-not $ToolsPath -or [string]::IsNullOrWhiteSpace($ToolsPath)) {
        $ToolsPath = "C:\tools"
    }

    if (-not (Test-Path $ToolsPath)) {
        Write-Log "ToolsPath does not exist. Creating: $ToolsPath" "WARNING"
        New-Item -ItemType Directory -Path $ToolsPath -Force | Out-Null
    }

    $vcredistUrl = "https://aka.ms/highdpimfc2013x64chs"
    $rewriteUrl  = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"

    $vcredistFile = Join-Path $ToolsPath "vcredist_x64.exe"
    $rewriteFile  = Join-Path $ToolsPath "rewrite_amd64_en-US.msi"

    if (-not (Test-Path $vcredistFile)) {
        Write-Log "Downloading vcredist..." "WARNING"
        Invoke-WebRequest -Uri $vcredistUrl -OutFile $vcredistFile -UseBasicParsing
        Write-Log "vcredist downloaded successfully."
    }

    if (-not (Test-Path $rewriteFile)) {
        Write-Log "Downloading URL Rewrite..." "WARNING"
        Invoke-WebRequest -Uri $rewriteUrl -OutFile $rewriteFile -UseBasicParsing
        Write-Log "URL Rewrite downloaded successfully."
    }

    # =====================================================================
    # 原-有®D逻?辑-：êo安ã2装Á¡ã vcredist / URL Rewrite
    # =====================================================================

    if (Test-Path $vcredistFile) {
        Write-Log "Installing Visual C++ Redistributable..."
        Start-Process $vcredistFile -ArgumentList "/quiet","/norestart" -Wait
    }

    if (Test-Path $rewriteFile) {
        Write-Log "Installing URL Rewrite..."
        Start-Process "msiexec.exe" -ArgumentList "/i",$rewriteFile,"/quiet","/norestart" -Wait
    }

    Write-Log "Prerequisites installation completed."
}

#===============================
# Install UCMA
#===============================
function Install-UCMA {
    param([string]$IsoPath)

    $ucmaPath = Join-Path $IsoPath "UCMARedist\Setup.exe"
    if (-not (Test-Path $ucmaPath)) {
        Write-Log "UCMA Setup not found: $ucmaPath" "ERROR"
        throw "UCMA install file missing."
    }

    Write-Log "Installing UCMA..."
    Start-Process $ucmaPath -ArgumentList "/quiet","/norestart" -Wait
    Write-Log "UCMA installation completed."
}

#===============================
# Run PrepareAD
#===============================
function Run-PrepareAD {
    param(
        [string]$IsoPath,
        [string]$OrgName
    )

    $setup = Join-Path $IsoPath "Setup.exe"

    Write-Log "Extending AD Schema (PrepareAD)..."

    $args = "/PrepareAD /OrganizationName:`"$OrgName`" /IAcceptExchangeServerLicenseTerms_DiagnosticDataON"

    Start-Process -FilePath $setup -ArgumentList $args -Wait -NoNewWindow

    Write-Log "PrepareAD completed."
}

#===============================
# Install Exchange Server
#===============================
function Install-Exchange {
    param(
        [string]$IsoPath,
        [string]$OrgName,
        [switch]$IsFirstServer
    )

    $setup = Join-Path $IsoPath "Setup.exe"

    if ($IsFirstServer) {
        $args = "/Mode:Install /Roles:m /OrganizationName:`"$OrgName`" /IAcceptExchangeServerLicenseTerms_DiagnosticDataON /InstallWindowsComponents /DisableAMFiltering"
    } else {
        $args = "/Mode:Install /Roles:m /IAcceptExchangeServerLicenseTerms_DiagnosticDataON /InstallWindowsComponents /DisableAMFiltering"
    }

    Write-Log "Starting Exchange installation..."

    Start-Process -FilePath $setup -ArgumentList $args -Wait

    Write-Log "Exchange installation completed."
}

#===============================
# Main Script
#===============================
try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Exchange Server 2022 Deployment Script" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Step 1: Domain Check
    Test-DomainMembership | Out-Null

    # Step 2: First server or additional?
    Write-Host ""
    Write-Host "Select Deployment Mode:" -ForegroundColor Yellow
    Write-Host "[1] Install FIRST Exchange Server"
    Write-Host "[2] Install SECOND/ADDITIONAL Exchange Server"
    $mode = Get-UserInput -Prompt "Enter option number" -Required

    if ($mode -eq "1") {
        $IsFirstServer = $true
        $OrgName = Get-UserInput -Prompt "Enter Organization Name" -DefaultValue "geekops" -Required
    } else {
        $IsFirstServer = $false
        $OrgName = $null
    }

    # Step 3: Paths
    $toolsPath = Get-UserInput -Prompt "Enter tools path" -Required
    $isoPath = Get-UserInput -Prompt "Enter Exchange ISO path" -Required

    if (-not (Test-Path (Join-Path $isoPath "Setup.exe"))) {
        throw "Setup.exe not found in ISO path."
    }

    # Step 4: Prerequisites
    Install-Prerequisites -ToolsPath $toolsPath

    # Step 5: UCMA
    Install-UCMA -IsoPath $isoPath

    # Step 6: If first server →¨² PrepareAD
    if ($IsFirstServer) {
        Run-PrepareAD -IsoPath $isoPath -OrgName $OrgName
    }

    # Step 7: Install Exchange
    Install-Exchange -IsoPath $isoPath -OrgName $OrgName -IsFirstServer:$IsFirstServer

    Write-Host "`nDeployment completed successfully!" -ForegroundColor Green

} catch {
    Write-Log "Deployment failed: $_" "ERROR"
    exit 1
}
 
