<# 
.SYNOPSIS
设置 Exchange Server 2019 URL 配置（模式 A 内外网同域）
适用版本：Exchange 2016 / 2019 / SE

.DESCRIPTION
设置 Exchange Server 2019 URL 配置（模式 A 内外网同域）

.EXAMPLE
.\Set-ExchangeURLs.ps1

.NOTES
Written by: geekops
Change Log:
V1.00, 2025/11/10 - 初始版本
#>


Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Exchange Server 2019 URL 配置脚本（模式 A 内外网同域）" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan

# 自动载入 Exchange 管理命令环境
if (-not (Get-Command Connect-ExchangeServer -ErrorAction SilentlyContinue)) {
    try {
        $env:ExchangeInstallPath = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup).MsiInstallPath
        . "$env:ExchangeInstallPath\bin\RemoteExchange.ps1"
        Connect-ExchangeServer -auto
    }
    catch {}
}

$ServerName = Read-Host "请输入 Exchange Server 名称 (例如: EX01)"
$Url = "mail.geekops.cn"

Write-Host "`n正在配置虚拟目录..." -ForegroundColor Green

# Autodiscover
Set-ClientAccessService -Identity $ServerName `
  -AutoDiscoverServiceInternalUri "https://$Url/autodiscover/autodiscover.xml" -Confirm:$false

# ECP / OWA / EWS / ActiveSync / MAPI / OAB / PowerShell
Get-EcpVirtualDirectory -Server $ServerName | Set-EcpVirtualDirectory `
  -InternalUrl "https://$Url/ecp" -ExternalUrl "https://$Url/ecp" -Confirm:$false

Get-OwaVirtualDirectory -Server $ServerName | Set-OwaVirtualDirectory `
  -InternalUrl "https://$Url/owa" -ExternalUrl "https://$Url/owa" -Confirm:$false

Get-WebServicesVirtualDirectory -Server $ServerName | Set-WebServicesVirtualDirectory `
  -InternalUrl "https://$Url/EWS/Exchange.asmx" -ExternalUrl "https://$Url/EWS/Exchange.asmx" -Confirm:$false

Get-ActiveSyncVirtualDirectory -Server $ServerName | Set-ActiveSyncVirtualDirectory `
  -InternalUrl "https://$Url/Microsoft-Server-ActiveSync" -ExternalUrl "https://$Url/Microsoft-Server-ActiveSync" -Confirm:$false

Get-MapiVirtualDirectory -Server $ServerName | Set-MapiVirtualDirectory `
  -InternalUrl "https://$Url/mapi" -ExternalUrl "https://$Url/mapi" -Confirm:$false

Get-OabVirtualDirectory -Server $ServerName | Set-OabVirtualDirectory `
  -InternalUrl "https://$Url/OAB" -ExternalUrl "https://$Url/OAB" -Confirm:$false

Get-PowerShellVirtualDirectory -Server $ServerName | Set-PowerShellVirtualDirectory `
  -InternalUrl "https://$Url/powershell" -ExternalUrl "https://$Url/powershell" -Confirm:$false

# Outlook Anywhere / MAPI over HTTP
Get-OutlookAnywhere -Server $ServerName | Set-OutlookAnywhere `
  -InternalHostname $Url -ExternalHostname $Url `
  -ExternalClientsRequireSsl $true -InternalClientsRequireSsl $true `
  -DefaultAuthenticationMethod Negotiate -Confirm:$false

Write-Host "`n✅ URL 已成功配置（统一域名模式）" -ForegroundColor Green
Write-Host "⚠️ 请立即执行：" -ForegroundColor Yellow
Write-Host "iisreset /noforce"
