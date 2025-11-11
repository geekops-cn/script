
<#
.SYNOPSIS
交互式创建 Exchange Server 2019 DAG 并添加成员服务器（支持失败重试）

.DESCRIPTION
脚本完成以下功能：
1) 创建 DAG
2) 列出所有 Mailbox Server，让用户选择加入 DAG
3) 如果添加失败，允许用户选择【重试】或【跳过】

.EXAMPLE
PS > .\Create-DAG-With-Members-Retry.ps1

.NOTES
Written by: geekops
Change Log:
V1.00, 2025/11/10 - 初始版本
#>

Write-Host "=== Exchange Server 2019 DAG 创建向导 ===" -ForegroundColor Cyan

#-------------------------------
# 1) 获取用户输入信息
#-------------------------------
$DAGName = Read-Host "请输入 DAG 名称（例如：DAG1）"
$WitnessServer = Read-Host "请输入 Witness 服务器名称（例如：MBX2）"
$WitnessDirectory = Read-Host "请输入 Witness 目录路径（例如：C:\DAG1）"

Write-Host "请依次输入 DAG 使用的 IP 地址（可多个，使用逗号分隔）" -ForegroundColor Yellow
$DAGIPs = Read-Host "例如：10.0.0.8,192.168.0.8"
$DAGIPList = $DAGIPs -split "," | ForEach-Object { $_.Trim() }

Write-Host "`n即将创建 DAG，配置信息如下：" -ForegroundColor Yellow
Write-Host ("-" * 60)
Write-Host "DAG 名称:         $DAGName"
Write-Host "Witness Server:   $WitnessServer"
Write-Host "Witness 目录:     $WitnessDirectory"
Write-Host "DAG IP 列表:      $($DAGIPList -join ', ')"
Write-Host ("-" * 60)

$confirm = Read-Host "确认创建 DAG？(Y/N)"
if ($confirm -notmatch "^[Yy]$") {
    Write-Host "操作已取消。" -ForegroundColor Red
    exit
}

#-------------------------------
# 2) 创建 DAG
#-------------------------------
try {
    New-DatabaseAvailabilityGroup `
        -Name $DAGName `
        -WitnessServer $WitnessServer `
        -WitnessDirectory $WitnessDirectory `
        -DatabaseAvailabilityGroupIPAddresses $DAGIPList

    Write-Host "`n[DAG 创建成功]" -ForegroundColor Green
}
catch {
    Write-Host "`n[DAG 创建失败] $_" -ForegroundColor Red
    exit
}

#-------------------------------
# 3) 选择并添加 DAG 成员服务器
#-------------------------------
Write-Host "`n正在读取环境中的 Mailbox 服务器..." -ForegroundColor Cyan
$MailboxServers = Get-MailboxServer | Select-Object Name, FQDN

if ($MailboxServers.Count -eq 0) {
    Write-Host "未检测到任何 Mailbox Server，无法继续添加成员服务器。" -ForegroundColor Red
    exit
}

Write-Host "`n可加入 DAG 的服务器列表：" -ForegroundColor Yellow
$index = 1
$MailboxServers | ForEach-Object {
    Write-Host ("[{0}] {1} ({2})" -f $index, $_.Name, $_.FQDN)
    $index++
}

Write-Host "`n请从以上序号中选择要加入 DAG 的服务器（可多选，使用逗号分隔）"
$selection = Read-Host "例如：1,3"

$selectedIndexes = $selection -split "," | ForEach-Object { $_.Trim() }

foreach ($i in $selectedIndexes) {
    if ($i -as [int] -and $i -le $MailboxServers.Count -and $i -ge 1) {
        $ServerToAdd = $MailboxServers[[int]$i - 1].Name
        
        :RetryAddServer do {
            Write-Host "`n正在将服务器 $ServerToAdd 加入 DAG..." -ForegroundColor Cyan
            
            try {
                Add-DatabaseAvailabilityGroupServer -Identity $DAGName -MailboxServer $ServerToAdd -ErrorAction Stop
                Write-Host "[成功] $ServerToAdd 已加入 $DAGName" -ForegroundColor Green
                break RetryAddServer
            }
            catch {
                Write-Host "[失败] 添加 $ServerToAdd 出错：" -ForegroundColor Red
                Write-Host $_ -ForegroundColor DarkRed

                $retry = Read-Host "是否需要重试？(Y=重试 / S=跳过该服务器)"
                if ($retry -match "^[Yy]$") {
                    continue RetryAddServer
                } else {
                    Write-Host "[已跳过] $ServerToAdd 未添加到 DAG。" -ForegroundColor Yellow
                    break RetryAddServer
                }
            }
        } while ($true)
    }
    else {
        Write-Host "[跳过] 无效的选择：$i" -ForegroundColor DarkYellow
    }
}

Write-Host "`n所有操作已完成，请继续进行数据库复制配置。" -ForegroundColor Green
