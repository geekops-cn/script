<#
.SYNOPSIS
交互式创建 Exchange Server 2019 DAG（Database Availability Group）

.DESCRIPTION
脚本会提示用户输入 DAG 名称、见证服务器、见证目录路径及 DAG IP 地址列表，
并执行 New-DatabaseAvailabilityGroup 命令创建 DAG。

.EXAMPLE
PS > .\Create-DAG.ps1
# 按提示输入信息，脚本将自动创建 DAG

.NOTES
Written by: geekops
Change Log:
V1.00, 2025/11/10 - 初始版本
#>

Write-Host "=== Exchange Server 2019 DAG 创建向导 ===" -ForegroundColor Cyan

# 获取 DAG 名称
$DAGName = Read-Host "请输入 DAG 名称（例如：DAG1）"

# 获取 Witness Server
$WitnessServer = Read-Host "请输入 Witness 服务器名称（例如：MBX2）"

# 获取 Witness Directory
$WitnessDirectory = Read-Host "请输入 Witness 目录路径（例如：C:\DAG1）"

# 获取 DAG IP 地址列表
Write-Host "请依次输入 DAG 使用的 IP 地址（可以为多个，使用逗号分隔）"
$DAGIPs = Read-Host "例如：10.0.0.8,192.168.0.8"
$DAGIPList = $DAGIPs -split "," | ForEach-Object { $_.Trim() }

Write-Host "`n以下配置将被应用：" -ForegroundColor Yellow
Write-Host "DAG 名称:                  $DAGName"
Write-Host "Witness 服务器:           $WitnessServer"
Write-Host "Witness 目录路径:         $WitnessDirectory"
Write-Host "DAG IP 地址:              $DAGIPList"
Write-Host "`n请确认信息无误..." -ForegroundColor Yellow

$confirm = Read-Host "确认执行创建? (Y/N)"
if ($confirm -notmatch "^[Yy]$") {
    Write-Host "操作已取消。" -ForegroundColor Red
    exit
}

try {
    New-DatabaseAvailabilityGroup `
        -Name $DAGName `
        -WitnessServer $WitnessServer `
        -WitnessDirectory $WitnessDirectory `
        -DatabaseAvailabilityGroupIPAddresses $DAGIPList

    Write-Host "`n[DAG 创建成功] 请继续添加成员服务器。" -ForegroundColor Green
}
catch {
    Write-Host "`n[DAG 创建失败] $_" -ForegroundColor Red
}
