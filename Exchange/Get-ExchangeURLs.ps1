<# 
.SYNOPSIS
查询组织内所有 Exchange Server 的核心 URL 信息（无需指定 -Server）
适用版本：Exchange 2016 / 2019 / SE

.DESCRIPTION
查询组织内所有 Exchange Server 的核心 URL 信息（无需指定 -Server）

.EXAMPLE
.\Get-ExchangeURLs.ps1

.NOTES
Written by: geekops
Change Log:
V1.00, 2025/11/10 - 初始版本
#>


Begin {
    Write-Host "🔍 正在初始化 Exchange 管理环境..." -ForegroundColor Cyan

    try {
        if (-not (Get-Command Get-ExchangeServer -ErrorAction SilentlyContinue)) {
            if (Test-Path "$env:ExchangeInstallPath\bin\RemoteExchange.ps1") {
                . "$env:ExchangeInstallPath\bin\RemoteExchange.ps1"
                Connect-ExchangeServer -auto -AllowClobber -ErrorAction Stop
                Write-Host "✅ 已成功加载 Exchange 管理模块" -ForegroundColor Green
            }
            else {
                throw "未检测到 Exchange 管理工具，请在 Exchange Management Shell 中运行。"
            }
        }
    }
    catch {
        Write-Error "❌ 加载 Exchange 管理模块失败：$($_.Exception.Message)"
        Exit 1
    }

    # 获取组织内所有 Mailbox 服务器（Exchange 2016/2019 都是多角色）
    try {
        $allExchangeServers = Get-ExchangeServer -ErrorAction Stop |
            Where-Object { $_.ServerRole -match "Mailbox" } |
            Select-Object -ExpandProperty Name

        Write-Host "✅ 检测到 $($allExchangeServers.Count) 台 Exchange 服务器" -ForegroundColor Green
    }
    catch {
        Write-Error "❌ 获取服务器列表失败：$($_.Exception.Message)"
        Exit 1
    }
}

Process {
    foreach ($serverName in $allExchangeServers) {

        Write-Host "`n--------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host "正在查询服务器：$serverName" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------" -ForegroundColor DarkCyan

        # ✅ 优先从 Autodiscover URL 中提取真实可用 FQDN
        try {
            $cas = Get-ClientAccessService -Identity $serverName -ErrorAction Stop
            $fqdn = $cas.AutoDiscoverServiceInternalUri.Host
        } catch { $fqdn = $null }

        # 🔁 回退策略：计算机名 + 域名
        if (-not $fqdn) {
            try {
                $dnsSuffix = (Get-WmiObject Win32_ComputerSystem).Domain
                $fqdn = "$serverName.$dnsSuffix"
            } catch { $fqdn = $serverName }
        }

        Write-Host "FQDN：$fqdn" -ForegroundColor Yellow

        # 查询 URL 结构定义
        $services = @(
            @{ Name="Autodiscover"; Cmd={Get-ClientAccessService $serverName}; Internal="AutoDiscoverServiceInternalUri"; External=$null }
            @{ Name="OWA"; Cmd={Get-OWAVirtualDirectory -Server $serverName -AdPropertiesOnly}; Internal="InternalURL"; External="ExternalURL" }
            @{ Name="ECP"; Cmd={Get-ECPVirtualDirectory -Server $serverName -AdPropertiesOnly}; Internal="InternalURL"; External="ExternalURL" }
            @{ Name="EWS"; Cmd={Get-WebServicesVirtualDirectory -Server $serverName -AdPropertiesOnly}; Internal="InternalURL"; External="ExternalURL" }
            @{ Name="MAPI"; Cmd={Get-MAPIVirtualDirectory -Server $serverName -AdPropertiesOnly}; Internal="InternalURL"; External="ExternalURL" }
            @{ Name="ActiveSync"; Cmd={Get-ActiveSyncVirtualDirectory -Server $serverName -AdPropertiesOnly}; Internal="InternalURL"; External="ExternalURL" }
            @{ Name="OAB"; Cmd={Get-OABVirtualDirectory -Server $serverName -AdPropertiesOnly}; Internal="InternalURL"; External="ExternalURL" }
            @{ Name="PowerShell"; Cmd={Get-PowerShellVirtualDirectory -Server $serverName -AdPropertiesOnly}; Internal="InternalURL"; External="ExternalURL" }
            @{ Name="OutlookAnywhere"; Cmd={Get-OutlookAnywhere -Server $serverName -AdPropertiesOnly}; Internal="InternalHostName"; External="ExternalHostName" }
        )

        foreach ($svc in $services) {
            Write-Host "`n📌 $($svc.Name)" -ForegroundColor Green

            try {
                $r = & $svc.Cmd

                # 内部 URL
                $internal = $r.$($svc.Internal)
                if (-not $internal) {
                    switch ($svc.Name) {
                        "Autodiscover" { $internal = "https://$fqdn/autodiscover/autodiscover.xml" }
                        "OWA" { $internal = "https://$fqdn/owa" }
                        "ECP" { $internal = "https://$fqdn/ecp" }
                        "EWS" { $internal = "https://$fqdn/ews/exchange.asmx" }
                        "MAPI" { $internal = "https://$fqdn/mapi" }
                        "ActiveSync" { $internal = "https://$fqdn/Microsoft-Server-ActiveSync" }
                        "OAB" { $internal = "https://$fqdn/oab" }
                        "PowerShell" { $internal = "https://$fqdn/powershell" }
                        "OutlookAnywhere" { $internal = $fqdn }
                    }
                }
                Write-Host "   内部：$internal"

                # 外部 URL（如无则说明与内部一致或未配置）
                if ($svc.External) {
                    $external = $r.$($svc.External)
                    if (-not $external) { $external = "【未配置或与内部相同】" }
                    Write-Host "   外部：$external"
                }

            } catch {
                Write-Host "   ❌ 查询失败：$($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

End {
    Write-Host "`n✅ Exchange URL 查询已完成！" -ForegroundColor Green
}
