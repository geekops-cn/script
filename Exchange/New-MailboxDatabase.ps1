
<#
.SYNOPSIS
Exchange Server 2019 批量创建数据库 + 一次选择Server + 最佳实践路径 + DAG副本播种与监控（最终修复版）

.FEATURES
- 仅在开始时选择一次目标 Mailbox Server（批量创建均使用该服务器）
- 批量创建数据库（前缀+数量 → DB01、DB02...）
- 最佳实践路径结构：
    E:\DB01\DB01.edb
    F:\DB01\Logs\
- 若数据库属于 DAG：支持一次选择副本节点，自动 Add-MailboxDatabaseCopy + 强制播种
- 交互优化：编号选择、输入校验、彩色提示
- 健壮性：目录自动创建、重复检测、错误捕获、结果汇总表
#>

function Show-Title($text, [ConsoleColor]$color = 'Cyan') { Write-Host "`n=== $text ===" -ForegroundColor $color }

function Read-ChoiceIndex($items, $prompt) {
    for ($i = 0; $i -lt $items.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i+1), $items[$i]) }
    $choice = Read-Host $prompt
    if ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -ge 0 -and $idx -lt $items.Count) { return $idx }
    }
    return $null
}

function Ensure-Directory($path) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
}

function Make-DbPaths($edbRoot, $logRoot, $dbName) {
    if ($edbRoot.Length -eq 2 -and $edbRoot.EndsWith(':')) { $edbRoot = "$edbRoot\" }
    if ($logRoot.Length -eq 2 -and $logRoot.EndsWith(':')) { $logRoot = "$logRoot\" }
    $edbDir  = Join-Path $edbRoot $dbName
    $edbFile = Join-Path $edbDir  "$dbName.edb"
    $logDir  = Join-Path (Join-Path $logRoot $dbName) "Logs"
    [PSCustomObject]@{ EdbDir = $edbDir; EdbFile = $edbFile; LogDir = $logDir }
}

Show-Title "Exchange Server 2019 批量创建数据库向导（最终修复版）"

# 1️⃣ 选择目标 Mailbox Server（一次选择）
Show-Title "获取 Mailbox Server 列表" "Yellow"
$mbxServers = Get-MailboxServer | Select-Object -ExpandProperty Name
if (-not $mbxServers -or $mbxServers.Count -eq 0) {
    Write-Host "未发现任何 Mailbox Server，退出。" -ForegroundColor Red
    exit 1
}
$idx = Read-ChoiceIndex $mbxServers "请选择要用于创建数据库的服务器编号"
if ($null -eq $idx) { Write-Host "输入无效，退出。" -ForegroundColor Red; exit 1 }
$TargetServer = $mbxServers[$idx]
Write-Host ("✅ 已选择服务器：{0}" -f $TargetServer) -ForegroundColor Green

# 2️⃣ 输入数据库前缀与数量
$prefix = Read-Host "请输入数据库前缀（例如 DB）"
if ([string]::IsNullOrWhiteSpace($prefix)) { Write-Host "数据库前缀不能为空" -ForegroundColor Red; exit 1 }

$cntRaw  = Read-Host "请输入要创建的数据库数量（例如 5）"
if (-not ($cntRaw -match '^\d+$') -or [int]$cntRaw -le 0) { Write-Host "数量必须为正整数" -ForegroundColor Red; exit 1 }
$count = [int]$cntRaw

# 3️⃣ 指定 EDB / Logs 根路径
$edbRoot = Read-Host "请输入 EDB 根路径（例如 E: 或 E:\ExchangeDBRoot）"
$logRoot = Read-Host "请输入 Logs 根路径（例如 F: 或 F:\ExchangeLogsRoot）"
if ([string]::IsNullOrWhiteSpace($edbRoot) -or [string]::IsNullOrWhiteSpace($logRoot)) {
    Write-Host "路径不能为空" -ForegroundColor Red; exit 1
}

if (-not (Test-Path -LiteralPath $edbRoot)) { Write-Host "⚠ EDB 根路径不存在，正在创建..." -ForegroundColor Yellow; Ensure-Directory $edbRoot }
if (-not (Test-Path -LiteralPath $logRoot)) { Write-Host "⚠ Logs 根路径不存在，正在创建..." -ForegroundColor Yellow; Ensure-Directory $logRoot }

# 4️⃣ 预览创建计划
Show-Title "创建计划预览" "Yellow"
$planPreview = for ($i=1; $i -le $count; $i++) {
    $dbName = "{0}{1:D2}" -f $prefix, $i
    $paths  = Make-DbPaths -edbRoot $edbRoot -logRoot $logRoot -dbName $dbName
    [PSCustomObject]@{
        Database = $dbName
        Server   = $TargetServer
        EDBPath  = $paths.EdbFile
        LogPath  = $paths.LogDir
    }
}
$planPreview | Format-Table -AutoSize
$go = Read-Host "确认创建以上数据库？(Y/N)"
if ($go -notmatch '^[Yy]$') { Write-Host "已取消。" -ForegroundColor Yellow; exit 0 }

# 5️⃣ 批量创建数据库
$results = @()
for ($i=1; $i -le $count; $i++) {
    $dbName = "{0}{1:D2}" -f $prefix, $i
    $paths  = Make-DbPaths -edbRoot $edbRoot -logRoot $logRoot -dbName $dbName

    if (Get-MailboxDatabase -Identity $dbName -ErrorAction SilentlyContinue) {
        Write-Host ("⚠ 数据库 {0} 已存在，跳过创建。" -f $dbName) -ForegroundColor Yellow
        $results += [PSCustomObject]@{ Database=$dbName; Server=$TargetServer; EDBPath=$paths.EdbFile; LogPath=$paths.LogDir; Mounted="已存在"; DAG="N/A"; Copies="N/A"; Status="Skipped" }
        continue
    }

    Ensure-Directory (Split-Path -Path $paths.EdbFile -Parent)
    Ensure-Directory $paths.LogDir

    Write-Host ("▶ 正在服务器 [{0}] 上创建数据库：{1}" -f $TargetServer, $dbName) -ForegroundColor Cyan
    $mounted = $false
    $status  = "Created"

    try {
        New-MailboxDatabase -Server $TargetServer -Name $dbName -EdbFilePath $paths.EdbFile -LogFolderPath $paths.LogDir -ErrorAction Stop | Out-Null
        try {
            Mount-Database -Identity $dbName -ErrorAction Stop
            $mounted = $true
        } catch {
            Write-Host "挂载失败，重试一次..." -ForegroundColor Yellow
            Start-Sleep 3
            Mount-Database -Identity $dbName -ErrorAction Stop
            $mounted = $true
        }

        $results += [PSCustomObject]@{
            Database = $dbName
            Server   = $TargetServer
            EDBPath  = $paths.EdbFile
            LogPath  = $paths.LogDir
            Mounted  = $(if($mounted){"Mounted"}else{"NotMounted"})
            DAG      = "TBD"
            Copies   = "0"
            Status   = $status
        }

        Write-Host ("✅ 数据库 {0} 已创建并挂载" -f $dbName) -ForegroundColor Green
    }
    catch {
        Write-Host ("❌ 创建/挂载数据库 {0} 失败：{1}" -f $dbName, $_.Exception.Message) -ForegroundColor Red
        $results += [PSCustomObject]@{
            Database = $dbName
            Server   = $TargetServer
            EDBPath  = $paths.EdbFile
            LogPath  = $paths.LogDir
            Mounted  = "Failed"
            DAG      = "N/A"
            Copies   = "N/A"
            Status   = "Failed"
        }
    }
}

# 6️⃣ DAG 副本逻辑（修复版）
$createdDbNames = $results | Where-Object { $_.Status -eq 'Created' -or $_.Status -eq 'Skipped' } | Select-Object -ExpandProperty Database
$dagName = $null
foreach ($n in $createdDbNames) {
    $m = (Get-MailboxDatabase $n -ErrorAction SilentlyContinue).MasterServerOrAvailabilityGroup
    if ($m -and (Get-DatabaseAvailabilityGroup $m -ErrorAction SilentlyContinue)) { $dagName = $m; break }
}

if ($dagName) {
    Show-Title ("检测到数据库归属 DAG：{0}" -f $dagName) "Yellow"
    $doCopy = Read-Host "是否为以上数据库添加 DAG 副本并强制播种？(Y/N)"
    if ($doCopy -match '^[Yy]$') {

        # ✅ 获取完整服务器对象并强制数组化
        $AllServers = Get-MailboxServer | Select-Object Name, FQDN
        $OtherServers = @($AllServers | Where-Object { $_.Name -ne $TargetServer })

        if (-not $OtherServers -or $OtherServers.Count -eq 0) {
            Write-Host "没有可用的副本节点，跳过。" -ForegroundColor DarkYellow
        } else {
            Write-Host "`n可添加副本节点：" -ForegroundColor Yellow
            $i = 1
            foreach ($node in $OtherServers) {
                Write-Host "[$i] $($node.Name) ($($node.FQDN))"
                $i++
            }

            # ✅ 安全输入验证
            $copyChoice = Read-Host "选择要添加副本的节点序号（单选）"
            if ($copyChoice -match '^\d+$') {
                $choiceIndex = [int]$copyChoice - 1
                if ($choiceIndex -ge 0 -and $choiceIndex -lt $OtherServers.Count) {
                    $CopyServer = $OtherServers[$choiceIndex].Name

                    foreach ($db in $createdDbNames) {
                        Write-Host "`n→ 正在向 $CopyServer 添加数据库副本：$db" -ForegroundColor Cyan
                        try {
                            Add-MailboxDatabaseCopy -Identity $db -MailboxServer $CopyServer -ErrorAction Stop
                            Write-Host "✅ 副本记录创建成功。" -ForegroundColor Green

                            Write-Host "⏳ 准备执行强制播种..." -ForegroundColor Yellow
                            Suspend-MailboxDatabaseCopy -Identity "$db\$CopyServer" -Confirm:$false -ErrorAction SilentlyContinue
                            Update-MailboxDatabaseCopy -Identity "$db\$CopyServer" -DeleteExistingFiles -ErrorAction Stop
                            Resume-MailboxDatabaseCopy -Identity "$db\$CopyServer" -ErrorAction Stop

                            Write-Host "`n📡 正在监控副本同步状态，按 Ctrl + C 退出..." -ForegroundColor Cyan
                            while ($true) {
                                $s = Get-MailboxDatabaseCopyStatus "$db\$CopyServer"
                                Clear-Host
                                Write-Host "=== $db @ $CopyServer 副本健康状态 === $(Get-Date)" -ForegroundColor Cyan
                                $s | Format-Table Status,CopyQueueLength,ReplayQueueLength,LastInspectedLogTime -AutoSize

                                if ($s.Status -eq "Healthy") {
                                    Write-Host "`n🎉 副本同步完成，状态 Healthy。" -ForegroundColor Green
                                    break
                                }
                                elseif ($s.Status -match "Failed|FailedAndSuspended") {
                                    Write-Host "`n❌ 副本异常，请检查网络/存储/权限" -ForegroundColor Red
                                    break
                                }
                                Start-Sleep 3
                            }

                            ($results | Where-Object { $_.Database -eq $db }).DAG    = $dagName
                            ($results | Where-Object { $_.Database -eq $db }).Copies = 1

                        }
                        catch {
                            Write-Host ("❌ {0} → {1} 副本添加/播种失败：{2}" -f $db, $CopyServer, $_.Exception.Message) -ForegroundColor Red
                        }
                    }
                } else {
                    Write-Host "⚠ 输入超出范围，跳过副本步骤。" -ForegroundColor Yellow
                }
            } else {
                Write-Host "⚠ 输入无效，跳过副本步骤。" -ForegroundColor Yellow
            }
        }
    }
} else {
    Write-Host "未检测到 DAG 归属，跳过副本步骤。" -ForegroundColor DarkYellow
}

# 7️⃣ 输出结果汇总
Show-Title "数据库创建与副本结果" "Green"
$results |
    Select-Object Database,Server,EDBPath,LogPath,Mounted,DAG,Copies,Status |
    Format-Table -AutoSize

$export = Read-Host "是否导出结果到 CSV？(Y/N)"
if ($export -match '^[Yy]$') {
    $csvPath = Join-Path $env:TEMP ("ExchangeDB_Create_Result_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))
    $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host ("结果已导出：{0}" -f $csvPath) -ForegroundColor Green
}

Write-Host "`n🎯 任务完成。" -ForegroundColor Green