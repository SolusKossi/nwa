# ============================================================
#  nwa - Network Analysis Collector
#  Gathers a broad network snapshot + recent history into one
#  JSON file on your Desktop. Nothing is uploaded by this script.
#  Run: paste this whole thing into PowerShell and press Enter.
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$report = [ordered]@{}
$report.schema      = 'nwa-report/1'
$report.generatedAt = (Get-Date).ToString('o')
$report.hoursWindow = 24

Write-Host 'Collecting system info...'
$os = Get-CimInstance Win32_OperatingSystem
$report.system = [ordered]@{
  computerName = $env:COMPUTERNAME
  user         = $env:USERNAME
  os           = $os.Caption
  osVersion    = [string]$os.Version
  uptimeHours  = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
}

Write-Host 'Collecting network adapters...'
$report.adapters = @(Get-NetAdapter | ForEach-Object {
  [ordered]@{
    name        = $_.Name
    description = $_.InterfaceDescription
    status      = [string]$_.Status
    macAddress  = $_.MacAddress
    linkSpeed   = $_.LinkSpeed
    mediaType   = [string]$_.PhysicalMediaType
    ifIndex     = $_.ifIndex
  }
})

Write-Host 'Collecting IP configuration...'
$report.ipConfig = @(Get-NetIPConfiguration | ForEach-Object {
  [ordered]@{
    alias   = $_.InterfaceAlias
    ipv4    = [string]$_.IPv4Address.IPAddress
    ipv6    = [string]$_.IPv6Address.IPAddress
    gateway = [string]$_.IPv4DefaultGateway.NextHop
  }
})

$report.dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | ForEach-Object {
  [ordered]@{ alias = $_.InterfaceAlias; servers = @($_.ServerAddresses) }
})

Write-Host 'Collecting adapter traffic counters...'
$report.adapterStats = @(Get-NetAdapterStatistics | ForEach-Object {
  [ordered]@{
    name                   = $_.Name
    receivedBytes          = [int64]$_.ReceivedBytes
    sentBytes              = [int64]$_.SentBytes
    receivedUnicastPackets = [int64]$_.ReceivedUnicastPackets
    sentUnicastPackets     = [int64]$_.SentUnicastPackets
  }
})

Write-Host 'Collecting Wi-Fi state...'
$report.wifi = [ordered]@{}
$wifiRaw = netsh wlan show interfaces
if ($wifiRaw) {
  $report.wifi.raw = ($wifiRaw -join "`n")
  foreach ($line in $wifiRaw) {
    if ($line -match '^\s*(SSID|BSSID|Signal|Channel|Band|Radio type|Receive rate \(Mbps\)|Transmit rate \(Mbps\)|Authentication|State)\s*:\s*(.+)$') {
      $report.wifi[$matches[1].Trim()] = $matches[2].Trim()
    }
  }
}

Write-Host 'Running latency tests (this takes a few seconds)...'
$report.latency = @(foreach ($t in @('1.1.1.1','8.8.8.8','google.com')) {
  $r = Test-Connection -ComputerName $t -Count 4 -ErrorAction SilentlyContinue
  $recv = @($r).Count
  $times = @($r | ForEach-Object { if ($_.PSObject.Properties['ResponseTime']) { $_.ResponseTime } else { $_.Latency } })
  [ordered]@{
    target   = $t
    sent     = 4
    received = $recv
    lossPct  = [math]::Round((1 - ($recv / 4)) * 100, 0)
    avgMs    = if ($times) { [math]::Round(($times | Measure-Object -Average).Average, 1) } else { $null }
    minMs    = if ($times) { ($times | Measure-Object -Minimum).Minimum } else { $null }
    maxMs    = if ($times) { ($times | Measure-Object -Maximum).Maximum } else { $null }
  }
})

Write-Host 'Testing DNS resolution speed...'
$report.dnsTest = @(foreach ($h in @('google.com','cloudflare.com','microsoft.com')) {
  $sw  = [System.Diagnostics.Stopwatch]::StartNew()
  $res = Resolve-DnsName -Name $h -Type A -ErrorAction SilentlyContinue
  $sw.Stop()
  [ordered]@{
    host      = $h
    ms        = [math]::Round($sw.Elapsed.TotalMilliseconds, 0)
    resolved  = [bool]$res
    addresses = @($res | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress })
  }
})

Write-Host 'Collecting active connections...'
$procs = @{}
Get-Process | ForEach-Object { $procs[$_.Id] = $_.ProcessName }
$report.connections = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | ForEach-Object {
  [ordered]@{
    localAddress  = $_.LocalAddress
    localPort     = $_.LocalPort
    remoteAddress = $_.RemoteAddress
    remotePort    = $_.RemotePort
    process       = $procs[[int]$_.OwningProcess]
    pid           = $_.OwningProcess
  }
} | Select-Object -First 250)

Write-Host 'Collecting listening ports...'
$report.listening = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
  [ordered]@{
    localAddress = $_.LocalAddress
    localPort    = $_.LocalPort
    process      = $procs[[int]$_.OwningProcess]
    pid          = $_.OwningProcess
  }
} | Select-Object -First 150)

$report.routes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object {
  [ordered]@{ ifAlias = $_.InterfaceAlias; nextHop = $_.NextHop; metric = $_.RouteMetric }
})

Write-Host 'Looking up public IP (best effort)...'
try   { $report.publicIp = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 5).ip }
catch { $report.publicIp = $null }

Write-Host 'Collecting recent network events (last 24h)...'
$since = (Get-Date).AddHours(-24)
$report.events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since } -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -match 'Tcpip|Dhcp|WLAN|NetworkProfile|Netwtw|NDIS|Wlansvc|Dnscache' } |
  Select-Object -First 300 | ForEach-Object {
    [ordered]@{
      time     = $_.TimeCreated.ToString('o')
      level    = [string]$_.LevelDisplayName
      provider = $_.ProviderName
      id       = $_.Id
      message  = ($_.Message -replace '\s+', ' ').Trim()
    }
  })

$outPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'network-report.json'
$report | ConvertTo-Json -Depth 8 | Out-File -FilePath $outPath -Encoding utf8
Write-Host ''
Write-Host "==> Saved report to: $outPath" -ForegroundColor Green
Write-Host '    Now upload that file back to the nwa page to analyze it.' -ForegroundColor Green
Start-Process explorer.exe "/select,`"$outPath`""
