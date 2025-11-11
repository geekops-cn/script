<#
.SYNOPSIS
Exchange Server 2019 数据库创建 + 副本播种 + 健康可视化监控（终极增强版）
#>

Write-Host "=== Exchange Server 2019 创建数据库向导（增强版） ===" -ForegroundColor Cyan

# 1) 输入数据库名称
$DBName = Read-Host "请输入数据库名称 (如：DB01)"
if (-not $DBName) { Write-Host "数据库名称不能为空" -ForegroundColor Red; exit }

# 2) 选择服务器
Write-Host "`n正在获取 Mailbox Server 列表..." -ForegroundColor Cyan
$MailboxServers = Get-MailboxServer | Select-Object Name, FQDN
if ($MailboxServers.Count -eq 0) { Write-Host "未找到服务器" -ForegroundColor Red; exit }

Write-Host "`n可选服务器：" -ForegroundColor Yellow
$i = 1
foreach ($srv in $MailboxServers) {
    Write-Host "[$i] $($srv.Name) ($($srv.FQDN))"
    $i++
}
$choice = Read-Host "`n请选择服务器序号"
$TargetServer = $MailboxServers[[int]$choice - 1].Name

# 3) 输入数据库和日志路径
$DBPath = Read-Host "请输入数据库文件路径 (例：E:\DB01\DB01.edb)"
$LogPath = Read-Host "请输入日志路径 (例：E:\DB01\Logs)"

Write-Host "`n即将创建数据库：" -ForegroundColor Yellow
Write-Host "数据库：$DBName"
Write-Host "服务器：$TargetServer"
Write-Host "数据库路径：$DBPath"
Write-Host "日志路径：$LogPath"

$confirm = Read-Host "确认创建？(Y/N)"
if ($confirm -notmatch "^[Yy]$") { exit }

# 4) 创建数据库
try {
    New-MailboxDatabase -Name $DBName -Server $TargetServer -EdbFilePath $DBPath -LogFolderPath $LogPath -ErrorAction Stop
    Write-Host "`n✅ 数据库创建成功" -ForegroundColor Green
}
catch { Write-Host "`n❌ 创建失败：" -ForegroundColor Red; Write-Host $_; exit }

# 5) 挂载数据库（带重试）
:MountRetry do {
    try {
        Mount-Database -Identity $DBName -ErrorAction Stop
        Write-Host "✅ 数据库已挂载" -ForegroundColor Green
        break MountRetry
    }
    catch {
        Write-Host "❌ 挂载失败：" -ForegroundColor Red
        Write-Host $_
        $retry = Read-Host "是否重试挂载？(Y=重试 / N=跳过)"
        if ($retry -notmatch "^[Yy]$") { break MountRetry }
    }
} while ($true)

# 6) 绑定脱机通讯簿 OAB
$OABs = Get-OfflineAddressBook | Select-Object Name
if ($OABs.Count -gt 0) {
    Write-Host "`n可用 OAB：" -ForegroundColor Yellow
    $i=1
    foreach ($o in $OABs) { Write-Host "[$i] $($o.Name)"; $i++ }
    $oabChoice = Read-Host "选择一个 OAB (或回车跳过)"
    if ($oabChoice -match "^\d+$") {
        $SelectedOAB = $OABs[[int]$oabChoice - 1].Name
        Set-MailboxDatabase -Identity $DBName -OfflineAddressBook $SelectedOAB
        Write-Host "✅ 已绑定 OAB：$SelectedOAB" -ForegroundColor Green
    }
}

# 7) 如果是 DAG，允许添加副本
$DAG = (Get-MailboxDatabase $DBName).MasterServerOrAvailabilityGroup
if ($DAG -and (Get-DatabaseAvailabilityGroup $DAG -ErrorAction SilentlyContinue)) {

    Write-Host "`n数据库属于 DAG：$DAG" -ForegroundColor Yellow
    $doCopy = Read-Host "是否添加副本？(Y/N)"
    if ($doCopy -match "^[Yy]$") {

        $OtherServers = $MailboxServers | Where-Object { $_.Name -ne $TargetServer }
        Write-Host "`n可添加副本节点：" -ForegroundColor Yellow
        $i=1
        foreach ($node in $OtherServers) { Write-Host "[$i] $($node.Name)"; $i++ }

        $copyChoice = Read-Host "选择节点序号"
        $CopyServer = $OtherServers[[int]$copyChoice - 1].Name

        Write-Host "`n→ 正在向 $CopyServer 添加数据库副本..." -ForegroundColor Cyan
        Add-MailboxDatabaseCopy -Identity $DBName -MailboxServer $CopyServer -ErrorAction Stop
        Write-Host "✅ 副本记录创建成功。" -ForegroundColor Green

        Write-Host "⏳ 准备执行强制播种..." -ForegroundColor Yellow
        Suspend-MailboxDatabaseCopy -Identity "$DBName\$CopyServer" -Confirm:$false -ErrorAction SilentlyContinue
        Update-MailboxDatabaseCopy -Identity "$DBName\$CopyServer" -DeleteExistingFiles -ErrorAction Stop
        Resume-MailboxDatabaseCopy -Identity "$DBName\$CopyServer" -ErrorAction Stop

        Write-Host "`n📡 正在监控副本同步状态，按 Ctrl + C 退出..." -ForegroundColor Cyan
        while ($true) {
            $s = Get-MailboxDatabaseCopyStatus "$DBName\$CopyServer"
            Clear-Host
            Write-Host "=== $DBName @ $CopyServer 副本健康状态 === $(Get-Date)" -ForegroundColor Cyan
            $s | Format-Table Status,CopyQueueLength,ReplayQueueLength,LastInspectedLogTime -AutoSize

            if ($s.Status -eq "Healthy") { Write-Host "`n🎉 副本同步完成，状态 Healthy。" -ForegroundColor Green; break }
            if ($s.Status -match "Failed|FailedAndSuspended") { Write-Host "`n❌ 副本异常，请检查网络/存储/权限" -ForegroundColor Red; break }

            Start-Sleep 3
        }
    }
}

Write-Host "`n🎉 数据库创建过程完成。" -ForegroundColor Green
