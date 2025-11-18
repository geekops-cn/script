 # Exchange Server 2022 Second Server Deployment Script
# Author: System Administrator
# Date: $(Get-Date -Format 'yyyy-MM-dd')

param()

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(if($Level -eq "ERROR"){"Red"}elseif($Level -eq "WARNING"){"Yellow"}else{"Green"})
}

function Test-DomainMembership {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $isDomainJoined = $computerSystem.PartOfDomain
    
    if ($isDomainJoined) {
        $domainName = $computerSystem.Domain
        $currentUser = $env:USERNAME
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

function Get-UserInput {
    param(
        [string]$Prompt,
        [string]$DefaultValue = "",
        [switch]$Required = $true
    )
    
    do {
        if ($DefaultValue) {
            Write-Host "$Prompt (default: $DefaultValue): " -ForegroundColor Yellow -NoNewline
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $input = $DefaultValue
            }
        } else {
            Write-Host "$Prompt`: " -ForegroundColor Yellow -NoNewline
            $input = Read-Host
        }
        
        if ($Required -and [string]::IsNullOrWhiteSpace($input)) {
            Write-Host "This field is required. Please enter a value." -ForegroundColor Red
        } else {
            break
        }
    } while ($true)
    
    return $input.Trim()
}

function Install-Prerequisites {
    param(
        [string]$ToolsPath
    )
    
    Write-Log "Installing Windows features..."
    
    $features = @(
        "Server-Media-Foundation", "NET-Framework-45-Core", "NET-Framework-45-ASPNET",
        "NET-WCF-HTTP-Activation45", "NET-WCF-Pipe-Activation45", "NET-WCF-TCP-Activation45",
        "NET-WCF-TCP-PortSharing45", "RPC-over-HTTP-proxy", "RSAT-Clustering",
        "RSAT-Clustering-CmdInterface", "RSAT-Clustering-PowerShell", "WAS-Process-Model",
        "Web-Asp-Net45", "Web-Basic-Auth", "Web-Client-Auth", "Web-Digest-Auth",
        "Web-Dir-Browsing", "Web-Dyn-Compression", "Web-Http-Errors", "Web-Http-Logging",
        "Web-Http-Redirect", "Web-Http-Tracing", "Web-ISAPI-Ext", "Web-ISAPI-Filter",
        "Web-Metabase", "Web-Mgmt-Service", "Web-Net-Ext45", "Web-Request-Monitor",
        "Web-Server", "Web-Stat-Compression", "Web-Static-Content", "Web-Windows-Auth",
        "Web-WMI", "RSAT-ADDS"
    )
    
    $totalFeatures = $features.Count
    $currentFeature = 0
    
    foreach ($feature in $features) {
        $currentFeature++
        $percentComplete = [math]::Round(($currentFeature / $totalFeatures) * 100, 0)
        Write-Progress -Activity "Installing Windows Features" -Status "Installing $feature ($currentFeature of $totalFeatures)" -PercentComplete $percentComplete
        
        Write-Log "Installing feature: $feature"
        $result = Install-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
        if ($result.Success) {
            Write-Log "Successfully installed: $feature" "INFO"
        } else {
            Write-Log "Failed to install: $feature" "WARNING"
        }
    }
    
    Write-Progress -Activity "Installing Windows Features" -Completed
    
    # Remove unwanted features
    $unwantedFeatures = @("NET-WCF-MSMQ-Activation45", "MSMQ")
    foreach ($feature in $unwantedFeatures) {
        Write-Log "Removing feature: $feature"
        $result = Remove-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
        if ($result.Success) {
            Write-Log "Successfully removed: $feature" "INFO"
        } else {
            Write-Log "Failed to remove: $feature" "WARNING"
        }
    }
    
    # Install tools from specified path
    if (Test-Path $ToolsPath) {
        Write-Log "Installing tools from: $ToolsPath"
        
        # Install Visual C++ Redistributable
        $vcredistPath = Join-Path $ToolsPath "vcredist_x64.exe"
        if (Test-Path $vcredistPath) {
            Write-Log "Installing Visual C++ Redistributable..."
            Write-Progress -Activity "Installing Tools" -Status "Installing Visual C++ Redistributable" -PercentComplete 33
            Start-Process -FilePath $vcredistPath -ArgumentList "/quiet", "/norestart" -Wait
            Write-Log "Visual C++ Redistributable installation completed."
        } else {
            Write-Log "vcredist_x64.exe not found in tools path: $vcredistPath" "WARNING"
        }
        
        # Install URL Rewrite Module
        $rewritePath = Join-Path $ToolsPath "rewrite_amd64_zh-CN.msi"
        if (Test-Path $rewritePath) {
            Write-Log "Installing URL Rewrite Module..."
            Write-Progress -Activity "Installing Tools" -Status "Installing URL Rewrite Module" -PercentComplete 66
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", $rewritePath, "/quiet", "/norestart" -Wait
            Write-Log "URL Rewrite Module installation completed."
        } else {
            Write-Log "rewrite_amd64_zh-CN.msi not found in tools path: $rewritePath" "WARNING"
        }
        
        Write-Progress -Activity "Installing Tools" -Completed
    } else {
        Write-Log "Tools path does not exist: $ToolsPath" "ERROR"
        throw "Tools path is invalid."
    }
}

function Install-UCMA {
    param(
        [string]$IsoPath
    )
    
    # Build the correct UCMA path based on the ISO path
    $ucmaPath = Join-Path $IsoPath "UCMARedist\Setup.exe"
    if (Test-Path $ucmaPath) {
        Write-Log "Installing Unified Communications Managed API from: $ucmaPath"
        Write-Progress -Activity "Installing UCMA" -Status "Installing Unified Communications Managed API" -PercentComplete 50
        Start-Process -FilePath $ucmaPath -ArgumentList "/quiet", "/norestart" -Wait
        Write-Progress -Activity "Installing UCMA" -Status "UCMA Installation Complete" -PercentComplete 100
        Start-Sleep -Seconds 2  # Brief pause to ensure installation is fully complete
        Write-Progress -Activity "Installing UCMA" -Completed
        Write-Log "UCMA installation completed."
    } else {
        Write-Log "UCMA Setup.exe not found at: $ucmaPath" "ERROR"
        throw "UCMA installation file not found."
    }
}

function Install-ExchangeServer {
    param(
        [string]$IsoPath
    )
    
    # The Exchange Setup.exe is in the root of the ISO
    $setupPath = Join-Path $IsoPath "Setup.exe"
    if (Test-Path $setupPath) {
        Write-Log "Starting Exchange Server installation from: $setupPath"
        
        # Create a temporary log directory for exchange installation (not passing log parameter)
        # Exchange will create its own log in %TEMP% by default
        # Use the correct Exchange Server command line parameters without log parameter
        $arguments = "/Mode:Install", "/Roles:m", "/IAcceptExchangeServerLicenseTerms_DiagnosticDataON", "/InstallWindowsComponents", "/DisableAMFiltering"
        
        # Start the installation process
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $setupPath
        $processInfo.Arguments = ($arguments -join " ")
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        
        $process = [System.Diagnostics.Process]::Start($processInfo)
        
        # Monitor the installation progress
        Write-Progress -Activity "Installing Exchange Server" -Status "Starting Installation..." -PercentComplete 0
        
        $startTime = Get-Date
        $timeoutMinutes = 60  # 60 minute timeout
        
        # Monitor the process and log file for progress
        while (!$process.HasExited) {
            $elapsedTime = (Get-Date) - $startTime
            if ($elapsedTime.TotalMinutes -gt $timeoutMinutes) {
                Write-Log "Installation timeout after $timeoutMinutes minutes." "ERROR"
                $process.Kill()
                throw "Exchange installation timed out."
            }
            
            # Calculate estimated progress based on elapsed time (Exchange install typically takes 20-40 minutes)
            $estimatedProgress = [math]::Min(95, [math]::Round(($elapsedTime.TotalMinutes / 30) * 100, 0))
            $estimatedTimeLeft = [math]::Max(0, 30 - $elapsedTime.TotalMinutes)
            
            Write-Progress -Activity "Installing Exchange Server" -Status "Progress: $estimatedProgress% (ETA: $([math]::Round($estimatedTimeLeft)) minutes)" -PercentComplete $estimatedProgress
            
            Start-Sleep -Seconds 5  # Check every 5 seconds
        }
        
        # Final progress update
        Write-Progress -Activity "Installing Exchange Server" -Status "Installation Complete" -PercentComplete 100
        Start-Sleep -Seconds 2
        
        $exitCode = $process.ExitCode
        $output = $process.StandardOutput.ReadToEnd()
        $error = $process.StandardError.ReadToEnd()
        
        Write-Progress -Activity "Installing Exchange Server" -Completed
        
        if ($exitCode -eq 0) {
            Write-Log "Exchange Server installation completed successfully." "INFO"
            return $true
        } else {
            Write-Log "Exchange Server installation failed with exit code: $exitCode" "ERROR"
            Write-Log "Output: $output" "ERROR"
            Write-Log "Error: $error" "ERROR"
            throw "Exchange Server installation failed."
        }
    } else {
        Write-Log "Exchange Setup.exe not found at: $setupPath" "ERROR"
        throw "Exchange installation file not found."
    }
}

# Main execution
try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Exchange Server 2022 Second Server Deployment" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Step 1: Check domain membership and current user
    Write-Host "`nStep 1: Checking domain membership..." -ForegroundColor Yellow
    $domainInfo = Test-DomainMembership
    
    # Step 2: Get user inputs
    Write-Host "`nStep 2: Getting required paths..." -ForegroundColor Yellow
    $toolsPath = Get-UserInput -Prompt "Enter tools path (containing vcredist_x64.exe and rewrite_amd64_zh-CN.msi)" -Required
    $isoPath = Get-UserInput -Prompt "Enter Exchange Server ISO mount path (containing Setup.exe and UCMARedist folder)" -Required
    
    # Validate paths
    if (-not (Test-Path $toolsPath)) {
        throw "Tools path does not exist: $toolsPath"
    }
    if (-not (Test-Path $isoPath)) {
        throw "ISO path does not exist: $isoPath"
    }
    
    Write-Log "Tools path: $toolsPath"
    Write-Log "ISO path: $isoPath"
    
    # Step 3: Install prerequisites
    Write-Host "`nStep 3: Installing prerequisites..." -ForegroundColor Yellow
    Install-Prerequisites -ToolsPath $toolsPath
    
    # Step 4: Install UCMA
    Write-Host "`nStep 4: Installing UCMA..." -ForegroundColor Yellow
    Install-UCMA -IsoPath $isoPath
    
    # Step 5: Install Exchange Server
    Write-Host "`nStep 5: Installing Exchange Server..." -ForegroundColor Yellow
    Write-Host "Note: This process may take 20-40 minutes. Progress will be displayed below." -ForegroundColor Cyan
    Install-ExchangeServer -IsoPath $isoPath
    
    Write-Host "`nDeployment completed successfully!" -ForegroundColor Green
    Write-Host "Exchange Server installation is complete." -ForegroundColor Green
    
} catch {
    Write-Log "Deployment failed: $_" "ERROR"
    Write-Host "Script execution failed. Please check the logs above." -ForegroundColor Red
    exit 1
} 
