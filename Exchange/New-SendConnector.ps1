New-SendConnector -Name "to Internet" `
-Usage Internet `
-AddressSpaces "SMTP:*;1" `
-DNSRoutingEnabled $true `
-SourceTransportServers "EX01","EX02"
