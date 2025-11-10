<# 
.SYNOPSIS
批量为 Exchange Server 设置许可证
适用版本：Exchange 2016 / 2019 / SE

.DESCRIPTION
批量为 Exchange Server 设置许可证

.EXAMPLE
.\set-exchangelicense-batch.ps1

.\set-exchangelicense-batch.ps1 -ProductKey XXXXX-XXXXX-XXXXX-XXXXX-XXXXX -Edition Enterprise

.NOTES
Written by: geekops
Change Log:
V1.00, 2025/11/10 - 初始版本
#>

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Exchange Server 批量许可证激活脚本" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan

# 输入密钥
$ProductKey = Read-Host "请输入 Exchange 产品密钥 (格式：XXXXX-XXXXX-XXXXX-XXXXX-XXXXX)"

# 确认许可证类型
$edition = Read-Host "请输入许可证类型 (Standard / Enterprise)"

if ($edition -notin @("Standard","Enterprise")) {
    Write-Host "❌ 输入无效，请输入 Standard 或 Enterprise" -ForegroundColor Red
    exit
}

# 获取所有 Exchange Server
$Servers = Get-ExchangeServer | Select-Object Name,Edition,ServerRole

Write-Host "`n发现以下 Exchange 服务器：" -ForegroundColor Cyan
$Servers | Format-Table -AutoSize

$confirm = Read-Host "`n是否继续批量设置许可证？(Y/N)"
if ($confirm -ne "Y") { Write-Host "操作已取消。" -ForegroundColor Yellow; exit }

foreach ($srv in $Servers) {
    Write-Host "`n→ 正在为 $($srv.Name) 设置许可证..." -ForegroundColor Green

    try {
        Set-ExchangeServer -Identity $srv.Name -ProductKey $ProductKey -ErrorAction Stop
        Write-Host "✅ 成功设置 $($srv.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ 设置失败：$($srv.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }
}

Write-Host "`n正在验证许可证状态..." -ForegroundColor Cyan
Get-ExchangeServer | Select Name,Edition,AdminDisplayVersion | Format-Table -AutoSize

Write-Host "`n如未立即生效，需重启服务或服务器。" -ForegroundColor Yellow

# 询问是否自动重启服务
$restart = Read-Host "是否自动重启 Exchange 服务 (推荐 Y)? (Y/N)"
if ($restart -eq "Y") {

    foreach ($srv in $Servers) {
        Write-Host "`n🔄 正在重启 $($srv.Name) Exchange 服务..." -ForegroundColor Cyan
        Invoke-Command -ComputerName $srv.Name -ScriptBlock {
            Restart-Service MSExchangeIS -Force
            Restart-Service MSExchangeTransport -Force
            Restart-Service MSExchangeFrontEndTransport -Force
        }
    }

    Write-Host "`n✅ Exchange 服务已重启" -ForegroundColor Green
}

Write-Host "`n如果许可证仍未生效，可重启所有服务器。" -ForegroundColor Cyan
Write-Host "使用命令：" -ForegroundColor Yellow
Write-Host "Restart-Computer -ComputerName (Get-ExchangeServer).Name -Force"
