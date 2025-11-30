<#
.SYNOPSIS
  无域环境 WSUS 客户端自动配置脚本（企业级）
.DESCRIPTION
  - 自动检测 WSUS 主机连通性
  - 写入 WSUS 必需注册表
  - 设置客户端分组（Client-side Targeting）
  - 重启 Windows Update 服务
  - 触发补丁扫描与上报
.NOTES
  版权所有 Geekops - 2025
  官网地址：www.pangshare.com

  适用系统：Windows 7/8/10/11、Server 2012+
  请以管理员权限运行
  脚本版本：1.5 20251130
#>

param(
    # WSUS 服务器地址（请修改）
    [string]$WsusServer = "http://10.228.22.30:8530",

    # WSUS 客户端分组
    [string]$TargetGroup = "Windows Server 2022",

    # 日志路径
    [string]$LogFile = "C:\Logs\WSUS-Client-Config.log",

    # WSUS 不可达时是否继续执行（建议 true）
    [bool]$ContinueWhenWsusUnreachable = $true
)

# ========== 日志系统 ==========
function Initialize-Log {
    param([string]$Path)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType File -Force | Out-Null }
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Initialize-Log -Path $LogFile
Write-Log "================ WSUS 客户端配置脚本启动 ================"

# ========== 管理员检查 ==========
function Test-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "请以管理员权限运行此脚本。" "ERROR"
        throw "需要管理员权限"
    }
    Write-Log "管理员权限检查通过。"
}
Test-Admin

# ========== 解析 WSUS 地址 ==========
try {
    $wsusUri = [Uri]$WsusServer
    Write-Log "WSUS 地址：$($wsusUri.AbsoluteUri)"
    Write-Log "WSUS 主机：$($wsusUri.Host)，端口：$($wsusUri.Port)"
} catch {
    Write-Log "WSUS 地址格式错误：$WsusServer" "ERROR"
    throw
}

# ========== WSUS 连通性检测 ==========
function Test-WsusConnectivity {
    param(
        [string]$WsusHost,
        [int]$WsusPort
    )

    Write-Log "开始测试与 WSUS [${WsusHost}:${WsusPort}] 的 TCP 连通性..."

    $success = $false

    if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
        try {
            $success = Test-NetConnection -ComputerName $WsusHost -Port $WsusPort -InformationLevel Quiet
        } catch {
            Write-Log "Test-NetConnection 测试失败，将尝试使用 TcpClient。" "WARN"
        }
    }

    if (-not $success) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $iar = $client.BeginConnect($WsusHost, $WsusPort, $null, $null)
            $wait = $iar.AsyncWaitHandle.WaitOne(3000, $false)
            if ($wait) {
                $client.EndConnect($iar)
                $success = $true
            }
            $client.Close()
        } catch {
            Write-Log "TcpClient 测试失败：$($_.Exception.Message)" "WARN"
        }
    }

    if ($success) {
        Write-Log "✅ 已成功连接 WSUS [${WsusHost}:${WsusPort}]。"
    } else {
        Write-Log "⚠ 无法连接 WSUS [${WsusHost}:${WsusPort}]，可能是网络、防火墙或端口限制。" "WARN"
    }

    return $success
}

$wsusReachable = Test-WsusConnectivity -WsusHost $wsusUri.Host -WsusPort $wsusUri.Port

if (-not $wsusReachable -and -not $ContinueWhenWsusUnreachable) {
    Write-Log "WSUS 不可达，脚本终止。" "ERROR"
    throw "WSUS Unreachable"
}

# ========== 写入 WSUS 注册表 ==========
function Set-WsusRegistry {
    param(
        [string]$WsusUrl,
        [string]$TargetGroupName
    )

    Write-Log "开始写入 WSUS 客户端配置到注册表..."

    $base = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate"
    $au   = "$base\AU"

    New-Item -Path $base -Force | Out-Null
    New-Item -Path $au -Force | Out-Null

    New-ItemProperty -Path $base -Name "WUServer" -Value $WsusUrl -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $base -Name "WUStatusServer" -Value $WsusUrl -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $base -Name "TargetGroup" -Value $TargetGroupName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $base -Name "TargetGroupEnabled" -Value 1 -PropertyType DWord -Force | Out-Null

    New-ItemProperty -Path $au -Name "UseWUServer" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $au -Name "AUOptions" -Value 4 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $au -Name "ScheduledInstallDay" -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $au -Name "ScheduledInstallTime" -Value 3 -PropertyType DWord -Force | Out-Null

    Write-Log "WSUS 客户端注册表配置写入完成。"
    $current = Get-ItemProperty -Path $base
    Write-Log "当前 WindowsUpdate 配置：WUServer = $($current.WUServer)，TargetGroup = $($current.TargetGroup)" "DEBUG"
}
Set-WsusRegistry -WsusUrl $WsusServer -TargetGroupName $TargetGroup

# ========== 重启更新服务 ==========
function Restart-WindowsUpdateServices {
    Write-Log "正在重启 Windows Update 相关服务 (wuauserv, bits)..."

    foreach ($svc in @("wuauserv","bits")) {
        try {
            Restart-Service -Name $svc -Force -ErrorAction Stop
            Write-Log "服务 $svc 重启成功。" "DEBUG"
        } catch {
            Write-Log "服务 $svc 重启失败：$($_.Exception.Message)" "WARN"
        }
    }
}
Restart-WindowsUpdateServices

# ========== 触发扫描 & 上报 ==========
function Invoke-WindowsUpdateScan {
    Write-Log "开始触发 Windows Update 扫描与上报..."

    if (Test-Path "$env:SystemRoot\system32\wuauclt.exe") {
        Start-Process -FilePath "wuauclt.exe" -ArgumentList "/detectnow /reportnow" -WindowStyle Hidden
        Write-Log "调用 wuauclt /detectnow /reportnow" "DEBUG"
    }

    if (Test-Path "$env:SystemRoot\system32\UsoClient.exe") {
        Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartScan" -WindowStyle Hidden
        Write-Log "调用 UsoClient StartScan" "DEBUG"
    }

    Write-Log "已触发客户端扫描与上报。"
}
Invoke-WindowsUpdateScan

# ========== 客户端标识 ==========
function Show-ClientIdentity {
    try {
        $wu = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"
        Write-Log "Client ID: $($wu.SusClientId)"
    } catch {
        Write-Log "未找到客户端 ID。" "WARN"
    }
}
Show-ClientIdentity

Write-Log "================ WSUS 客户端配置脚本执行完成 ================"

Write-Log "================ 开始强制 WSUS 首次注册流程 ================"

# 1. 清除现有 WSUS 客户端 ID
Stop-Service wuauserv -Force
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SusClientId" -ErrorAction SilentlyContinue
Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\SusClientIdValidation" -ErrorAction SilentlyContinue
Start-Service wuauserv

# 2. 强制生成新 ID 并触发 Detect
wuauclt.exe /resetauthorization /detectnow

# 3. 触发全量扫描 + 上报
wuauclt.exe /detectnow
wuauclt.exe /reportnow

# Windows 10 / 11 额外触发
if (Test-Path "$env:SystemRoot\system32\UsoClient.exe") {
    UsoClient.exe StartScan
}

Write-Log "WSUS 首次注册流程已完成，客户端将在 10～60 秒内出现在 WSUS 控制台。"

Write-Log "正在执行 Windows Update Interactive Scan（等同手动检查更新）..."

$updateSession = New-Object -ComObject Microsoft.Update.Session
$updateSearcher = $updateSession.CreateUpdateSearcher()

# 此调用 = 点击“检查更新”
$null = $updateSearcher.Search("IsInstalled=0")

Write-Log "InteractiveScan 完成，客户端即将向 WSUS 注册并上报。"
