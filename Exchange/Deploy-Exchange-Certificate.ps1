<#
.SYNOPSIS
 批量导入并启用 Exchange 证书脚本

.DESCRIPTION
 1. 提示用户输入证书 UNC 路径（含 .pfx 文件名）
 2. 提示输入证书密码
 3. 自动获取所有 Exchange Server
 4. 在每台服务器上导入证书
 5. 自动启用 SMTP、IIS 服务绑定
#>

# 提示用户输入UNC路径 (如 \\ex01\Certs\geekops.pfx)
$CertPath = Read-Host "请输入证书 UNC 路径 (例如：\\ex01\Certs\geekops.pfx)"

if (!(Test-Path $CertPath)) {
    Write-Host "❌ 证书路径不存在，请检查后重新运行。" -ForegroundColor Red
    exit
}

# 提示证书密码
$Password = Read-Host "请输入证书密码" -AsSecureString

# 获取所有 Exchange Server（仅邮箱服务器 / 客户端访问角色服务器）
$Servers = Get-ExchangeServer | Where-Object { $_.ServerRole -match "Mailbox" }

Write-Host "✅ 将在以下服务器上执行证书导入与绑定：" -ForegroundColor Cyan
$Servers | Select-Object Name,ServerRole | Format-Table

Start-Sleep -Seconds 2

foreach ($Server in $Servers) {
    Write-Host "🔄 正在处理服务器: $($Server.Name)" -ForegroundColor Yellow

    # 导入证书
    $ImportedCert = Import-ExchangeCertificate `
        -Server $Server.Name `
        -FileData ([System.IO.File]::ReadAllBytes($CertPath)) `
        -Password $Password `
        -PrivateKeyExportable:$true `
        -ErrorAction Stop

    $Thumbprint = $ImportedCert.Thumbprint

    Write-Host "✅ 证书已导入到 $($Server.Name)，Thumbprint: $Thumbprint" -ForegroundColor Green

    # 启用证书绑定 SMTP、IIS
    Enable-ExchangeCertificate `
        -Server $Server.Name `
        -Thumbprint $Thumbprint `
        -Services SMTP,IIS `
        -Force

    Write-Host "🔗 已为服务器 $($Server.Name) 启用 SMTP 和 IIS 服务" -ForegroundColor Green
    Write-Host "-------------------------------------------------------------"
}

Write-Host "🎉 所有服务器证书导入与服务绑定已完成！" -ForegroundColor Cyan
