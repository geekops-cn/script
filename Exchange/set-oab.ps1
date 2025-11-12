<#
.SYNOPSIS
    Exchange Server 2019 脚本：交互式检查数据库与脱机通讯簿（OAB）挂载状态。
.DESCRIPTION
    支持中文 Exchange 环境。可交互选择单个或全部数据库，
    并根据脱机通讯簿数量自动决定是否需要用户选择。
.NOTES
    作者：GeekOps.cn
    测试环境：Exchange Server 2019 CU14 (中文环境)
#>

# 确保脚本在 Exchange Management Shell 环境运行
try {
    Get-MailboxDatabase | Out-Null
} catch {
    Write-Host "❌ 请在 Exchange Management Shell 中运行此脚本。" -ForegroundColor Red
    exit
}

Write-Host "`n=== Exchange 数据库与脱机通讯簿状态检查 ===`n" -ForegroundColor Cyan

# 获取数据库信息
$databases = Get-MailboxDatabase | Select-Object Name, Mounted, OfflineAddressBook
$databases | Format-Table Name, Mounted, OfflineAddressBook -AutoSize

Write-Host "`n请选择要操作的数据库：" -ForegroundColor Yellow
Write-Host "  [1] 选择单个数据库"
Write-Host "  [2] 所有数据库"
$choice = Read-Host "请输入选项 (1 或 2)"

switch ($choice) {
    1 {
        $dbName = Read-Host "请输入要操作的数据库名称（区分大小写）"
        $targetDBs = $databases | Where-Object { $_.Name -eq $dbName }
        if (-not $targetDBs) {
            Write-Host "❌ 未找到数据库：$dbName" -ForegroundColor Red
            exit
        }
    }
    2 {
        $targetDBs = $databases
        Write-Host "✅ 已选择所有数据库进行操作" -ForegroundColor Green
    }
    default {
        Write-Host "❌ 输入无效，请输入 1 或 2。" -ForegroundColor Red
        exit
    }
}

# 获取脱机通讯簿列表（强制转换为数组以避免单项时类型错误）
$oabs = @(Get-OfflineAddressBook | Select-Object Name, AddressLists)
if (-not $oabs -or $oabs.Count -eq 0) {
    Write-Host "❌ 未找到任何脱机通讯簿，请先创建。" -ForegroundColor Red
    exit
}

Write-Host "`n=== 当前可用的脱机通讯簿 ===" -ForegroundColor Cyan
$oabs | Format-Table Name, AddressLists -AutoSize

# 判断脱机通讯簿数量
if ($oabs.Count -eq 1) {
    $selectedOAB = $oabs[0]
    Write-Host "`n系统检测到仅有一个脱机通讯簿：$($selectedOAB.Name)" -ForegroundColor Yellow
    $confirm = Read-Host "是否将其挂载到所选数据库？(直接回车=是，N=否)"
    if ($confirm -eq "" -or $confirm -match "^[Yy]") {
        foreach ($db in $targetDBs) {
            Write-Host "正在为数据库 [$($db.Name)] 挂载脱机通讯簿 [$($selectedOAB.Name)]..." -ForegroundColor Cyan
            Set-MailboxDatabase -Identity $db.Name -OfflineAddressBook $selectedOAB.Name
        }
        Write-Host "✅ 挂载完成。" -ForegroundColor Green
    } else {
        Write-Host "❌ 已取消操作。" -ForegroundColor Red
    }
}
else {
    Write-Host "`n检测到多个脱机通讯簿，请选择要挂载的：" -ForegroundColor Yellow
    for ($i = 0; $i -lt $oabs.Count; $i++) {
        Write-Host "[$($i+1)] $($oabs[$i].Name)"
    }

    $index = Read-Host "请输入要使用的脱机通讯簿编号"
    if ($index -match '^\d+$' -and $index -ge 1 -and $index -le $oabs.Count) {
        $selectedOAB = $oabs[$index - 1]
        foreach ($db in $targetDBs) {
            Write-Host "正在为数据库 [$($db.Name)] 挂载脱机通讯簿 [$($selectedOAB.Name)]..." -ForegroundColor Cyan
            Set-MailboxDatabase -Identity $db.Name -OfflineAddressBook $selectedOAB.Name
        }
        Write-Host "✅ 所选数据库已挂载脱机通讯簿 [$($selectedOAB.Name)]。" -ForegroundColor Green
    } else {
        Write-Host "❌ 输入无效，操作已取消。" -ForegroundColor Red
    }
}

Write-Host "`n=== 当前数据库脱机通讯簿挂载结果 ===" -ForegroundColor Cyan
Get-MailboxDatabase | Select-Object Name, OfflineAddressBook | Format-Table -AutoSize
