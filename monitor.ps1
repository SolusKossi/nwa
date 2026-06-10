# ============================================================
#  nwa - Network MONITOR  (intermittent-issue mode)
#  Samples your connection every few seconds and appends each
#  result to a log on your Desktop. Runs FOREVER until you stop
#  it with Ctrl+C. The log is saved continuously, so it's ready
#  to upload to the nwa MONITOR view the moment you stop.
#  Nothing is uploaded by this script.
#
#  --- you can edit these settings ---
$IntervalSec     = 10    # seconds between checks
$DurationHours   = 0     # 0 = run forever (until Ctrl+C). Set e.g. 8 to auto-stop.
$PingCount       = 5     # pings per target per check (for jitter / micro-loss)
$NeighborScanSec = 300   # how often to scan nearby Wi-Fi APs (channel congestion). 0 = never.
$httpTargets   = @(      # optional: sites to test by name, e.g. 'https://yourapp.com'. Leave empty for none.
)
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
$targets = @('1.1.1.1','8.8.8.8')
$dnsHost = 'google.com'
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'network-monitor.jsonl'

# fast multi-ping (no 1s gap) - returns recv/loss/min/avg/max/jitter
function Test-PingSet([string]$ip,[int]$count,[int]$timeoutMs){
  $rtts = New-Object System.Collections.Generic.List[int]
  $pinger = New-Object System.Net.NetworkInformation.Ping
  for ($i=0; $i -lt $count; $i++) {
    try { $pr = $pinger.Send($ip,$timeoutMs); if ($pr.Status -eq 'Success') { $rtts.Add([int]$pr.RoundtripTime) } } catch {}
  }
  $recv = $rtts.Count
  $o = [ordered]@{ recv=$recv; loss=[math]::Round((1-($recv/$count))*100,0); min=$null; avg=$null; max=$null; jit=$null }
  if ($recv -gt 0) {
    $o.min = ($rtts | Measure-Object -Minimum).Minimum
    $o.max = ($rtts | Measure-Object -Maximum).Maximum
    $o.avg = [math]::Round(($rtts | Measure-Object -Average).Average,0)
    if ($rtts.Count -gt 1) {
      $d = New-Object System.Collections.Generic.List[int]
      for ($i=1; $i -lt $rtts.Count; $i++) { $d.Add([math]::Abs($rtts[$i]-$rtts[$i-1])) }
      $o.jit = [math]::Round(($d | Measure-Object -Average).Average,0)
    } else { $o.jit = 0 }
  }
  return $o
}

# scan nearby Wi-Fi networks -> how crowded is my channel (co-channel contention)
function Get-Congestion([int]$myChan){
  $chans = New-Object System.Collections.Generic.List[int]
  foreach ($l in (netsh wlan show networks mode=bssid)) {
    if ($l -match '^\s*Channel\s*:\s*(\d+)') { $chans.Add([int]$matches[1]) }
  }
  [ordered]@{ total = $chans.Count; coChan = @($chans | Where-Object { $_ -eq $myChan }).Count; chan = $myChan }
}

# current DNS servers + default gateway (so the analysis can show them)
$upIdx = @((Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }).ifIndex)
$dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.ServerAddresses -and ($upIdx -contains $_.InterfaceIndex) } |
  ForEach-Object { $_.ServerAddresses } | Select-Object -Unique)
$gateway = $null
try { $gateway = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4DefaultGateway.NextHop } catch {}
# if the gateway doesn't answer ICMP, skip it (otherwise every tick wastes ~5s pinging a silent host)
if ($gateway) {
  $gwTest = Test-PingSet $gateway 2 800
  if ($gwTest.recv -eq 0) { Write-Host "Gateway $gateway doesn't answer ping (ICMP blocked) - skipping gateway checks." -ForegroundColor DarkYellow; $gateway = $null }
}

# adapter + driver + power-management (one-time context; radio power-saving is a common cause of drops)
$adapterInfo = $null
try {
  $a = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } |
       Sort-Object { if ($_.PhysicalMediaType -match '802.11|Wireless') { 0 } else { 1 } } | Select-Object -First 1
  if ($a) {
    $pm = $null
    try { $p = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop
          if ($p) { $pm = [ordered]@{ selectiveSuspend = [string]$p.SelectiveSuspend; sleepOnDisconnect = [string]$p.DeviceSleepOnDisconnect } } } catch {}
    $adapterInfo = [ordered]@{
      name = $a.Name; description = $a.InterfaceDescription
      driverVersion = [string]$a.DriverVersion; driverDate = [string]$a.DriverDate
      linkSpeed = [string]$a.LinkSpeed; powerMgmt = $pm
    }
  }
} catch {}

# IPv6 reachability (one-time context)
$ipv6 = $null
try { $r6 = Test-PingSet '2606:4700:4700::1111' 2 1200; $ipv6 = [ordered]@{ reachable = ($r6.recv -gt 0); ms = $r6.avg } }
catch { $ipv6 = [ordered]@{ reachable = $false; ms = $null } }

$meta = [ordered]@{
  schema          = 'nwa-monitor/1'
  startedAt       = (Get-Date).ToString('o')
  intervalSec     = $IntervalSec
  durationHours   = $DurationHours
  pingCount       = $PingCount
  neighborScanSec = $NeighborScanSec
  computerName    = $env:COMPUTERNAME
  targets         = $targets
  gateway         = $gateway
  dnsHost         = $dnsHost
  dnsServers      = $dnsServers
  adapter         = $adapterInfo
  ipv6            = $ipv6
  httpTargets     = $httpTargets
}
Set-Content -Path $out -Value ($meta | ConvertTo-Json -Compress) -Encoding utf8

$end = (Get-Date).AddHours($DurationHours)
$stopMsg = if ($DurationHours -le 0) { 'Running until you press Ctrl+C.' } else { "Auto-stops at $end (Ctrl+C to stop early)." }
Write-Host "MONITORING every ${IntervalSec}s ($PingCount pings/target). $stopMsg" -ForegroundColor Green
Write-Host ("Gateway: {0}   Services: {1}" -f $(if($gateway){$gateway}else{'n/a'}), ($httpTargets -join ', ')) -ForegroundColor Green
Write-Host "Logging to: $out" -ForegroundColor Green
Write-Host ''
$nbrEvery = if ($NeighborScanSec -gt 0) { [math]::Max(1, [int]($NeighborScanSec / $IntervalSec)) } else { 0 }
$k = 0
try {
  while ($DurationHours -le 0 -or (Get-Date) -lt $end) {
    $tick = [ordered]@{ t = (Get-Date).ToString('o') }

    # connectivity: gateway (local hop) + internet IPs, each a burst of pings
    $q = [ordered]@{}
    if ($gateway) { $r = Test-PingSet $gateway $PingCount 1000; $q['gw'] = $r; $tick.gw = $(if ($r.recv) { $r.avg } else { -1 }) } else { $tick.gw = $null }
    foreach ($tg in $targets) { $r = Test-PingSet $tg $PingCount 1000; $q[$tg] = $r; $tick[$tg] = $(if ($r.recv) { $r.avg } else { -1 }) }
    $tick.q = $q

    # DNS resolution time
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $rr = Resolve-DnsName -Name $dnsHost -Type A -ErrorAction SilentlyContinue
    $sw.Stop()
    $tick.dns = $(if ($rr) { [int]$sw.Elapsed.TotalMilliseconds } else { -1 })

    # Wi-Fi link detail (signal, which AP/BSSID, band, channel, PHY rates) for roaming/distance analysis
    $wsig=$null;$wbssid=$null;$wband=$null;$wchan=$null;$wrx=$null;$wtx=$null;$wradio=$null
    foreach ($l in (netsh wlan show interfaces)) {
      if     ($l -match '^\s*Signal\s*:\s*(\d+)%')                 { $wsig=[int]$matches[1] }
      elseif ($l -match 'BSSID\s*:\s*([0-9a-fA-F:]{17})')          { $wbssid=$matches[1].Trim() }
      elseif ($l -match '^\s*Band\s*:\s*(.+)$')                    { $wband=$matches[1].Trim() }
      elseif ($l -match '^\s*Channel\s*:\s*(\d+)')                 { $wchan=[int]$matches[1] }
      elseif ($l -match '^\s*Receive rate \(Mbps\)\s*:\s*([\d\.]+)'){ $wrx=[double]$matches[1] }
      elseif ($l -match '^\s*Transmit rate \(Mbps\)\s*:\s*([\d\.]+)'){ $wtx=[double]$matches[1] }
      elseif ($l -match '^\s*Radio type\s*:\s*(.+)$')              { $wradio=$matches[1].Trim() }
    }
    $tick.sig=$wsig; $tick.bssid=$wbssid; $tick.band=$wband; $tick.chan=$wchan; $tick.rx=$wrx; $tick.tx=$wtx; $tick.radio=$wradio

    # periodic channel-congestion scan (counts nearby APs on your channel)
    if ($nbrEvery -gt 0 -and $wchan -and ($k % $nbrEvery -eq 0)) { $tick.nbr = Get-Congestion $wchan }
    $k++

    $tick.up = [bool](Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })

    # HTTP(S) reachability per service. ms = -1 means could NOT reach it at all.
    $tick.http = @(foreach ($u in $httpTargets) {
      $hsw = [System.Diagnostics.Stopwatch]::StartNew()
      try {
        $resp = Invoke-WebRequest -Uri $u -Method Head -TimeoutSec 6 -UseBasicParsing -ErrorAction Stop
        $hsw.Stop()
        [ordered]@{ u = $u; ms = [int]$hsw.Elapsed.TotalMilliseconds; code = [int]$resp.StatusCode }
      } catch {
        $hsw.Stop()
        $code = 0
        if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch {} }
        if ($code -gt 0) { [ordered]@{ u = $u; ms = [int]$hsw.Elapsed.TotalMilliseconds; code = $code } }
        else             { [ordered]@{ u = $u; ms = -1; code = 0 } }
      }
    })

    Add-Content -Path $out -Value ($tick | ConvertTo-Json -Compress -Depth 6) -Encoding utf8

    # live console line
    $gwq = $q['gw']; $i1 = $q['1.1.1.1']
    $loss = if ($i1) { $i1.loss } else { 100 }
    $state = if (-not $tick.up -or ($i1 -and $i1.recv -eq 0)) { 'DOWN' } elseif ($tick.dns -lt 0) { 'DNS!' } elseif ($loss -gt 0) { 'LOSS' } else { ' ok ' }
    $gwStr = if ($gateway) { "gw=$($tick.gw)ms " } else { "" }
    Write-Host ("[{0}] {1}  {2}net={3}ms loss={4}% jit={5}ms  dns={6}ms  sig={7}% {8}" -f `
      (Get-Date -Format HH:mm:ss), $state, $gwStr, $tick.'1.1.1.1', $loss, $(if($i1){$i1.jit}else{'-'}), $tick.dns, $wsig, $(if($wband){$wband}else{''}))

    Start-Sleep -Seconds $IntervalSec
  }
}
finally {
  Write-Host ''
  Write-Host "==> Monitor log saved: $out" -ForegroundColor Green
  Write-Host '    Drag it onto the nwa MONITOR view to analyze.' -ForegroundColor Green
  Start-Process explorer.exe "/select,`"$out`""
}
