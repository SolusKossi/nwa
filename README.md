# NWA

Network diagnostics for Windows. One script: run it, watch the live status in
the terminal, press Q - it builds and opens an HTML report that explains, in
plain language, what is wrong. Analysis stays local; snapshot public-IP lookup
is opt-in.

## Mid-run monitoring: 

<img width="1083" height="543" alt="image" src="https://github.com/user-attachments/assets/d29b7077-52c8-4137-b6c4-87d1f7d97551" />

## Post-run report: 

<img width="825" height="1211" alt="image" src="https://github.com/user-attachments/assets/1128e2ee-9bee-4be0-bfd3-73456d9c5a63" />

## Use

    irm https://raw.githubusercontent.com/SolusKossi/nwa/main/nwa.ps1 -OutFile nwa.ps1
    powershell -ep bypass -f .\nwa.ps1

If your machine blocks the script ("running scripts is disabled", or it was
downloaded with a browser rather than `irm`), unblock it first:

    Unblock-File .\nwa.ps1

Options:

    -Snapshot            one-shot health check (~15 s) instead of monitoring
    -Sites "a.com,b.no"  also test reachability to your own sites
    -NoDefaultSites      skip the built-in Microsoft 365 checks
    -SiteCheckSec 60     how often to test sites
    -IntervalSec 10      seconds between checks
    -DurationHours 8     auto-stop (default: run until Q)
    -OfficeHours "08-17" when the office is busy (report coverage check)
    -RunLabel "baseline" label a run for before/after comparison
    -IncludePublicIp     snapshot only; request the public IP from ipify.org

The report opens by itself when the run ends. Each run gets its own timestamped
log and report in %LOCALAPPDATA%\nwa, so nothing clutters your desktop and each
capture is preserved for before/after comparison. You can also drop logs onto
index.html to analyze them in any browser (drop two to compare machines side by
side) - try it with sample-monitor.jsonl.

## What it measures

Every 10 s: ping bursts to the gateway and internet (loss, latency, jitter),
DNS, Wi-Fi signal / band / access point / roaming, and Ethernet link speed.
Every 60 s: reachability of login.microsoftonline.com, teams.microsoft.com and
outlook.office365.com, plus any sites you add - because "the network is slow"
usually means Teams or sign-in is slow, and a ping to 1.1.1.1 does not measure
that. These are HEAD requests; nothing is uploaded. Turn them off with
-NoDefaultSites. Periodically: channel congestion (nearby APs). On failure:
a quick path trace. Plus Windows' own Wi-Fi disconnect log (the reason for
each drop), adapter driver / power management, IPv6, and sleep-gap detection
so hours where the laptop was asleep are not counted as "all fine".

## Notes

- No admin needed. Windows PowerShell 5.1 and PowerShell 7.
- Reports contain hostname, username and IPs (snapshot mode also process
  names) - review before sharing outside your org.
- Windows 11 24H2: if Location is off, Windows hides which AP you are on, so
  roam detection and the neighbor scan are limited. The script warns about it.
- Repo layout: src/nwa.src.ps1 + index.html are the sources; build.ps1 bakes
  index.html into nwa.ps1 as the report template. Edit src, run build, commit.

## Verify what you are running

For managed machines, or if you would rather not trust the mutable `main`
branch, take a tagged release and check it before running:

    $version = 'v0.1.0'   # or a later release
    $base = "https://github.com/SolusKossi/nwa/releases/download/$version"
    irm "$base/nwa.ps1" -OutFile nwa.ps1
    irm "$base/SHA256SUMS.txt" -OutFile SHA256SUMS.txt
    $expected = ((Get-Content SHA256SUMS.txt) -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash .\nwa.ps1 -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw 'Checksum verification failed.' }

With the [GitHub CLI](https://cli.github.com/) you can also check the build
provenance attestation:

    gh attestation verify .\nwa.ps1 -R SolusKossi/nwa

Pushing a `v*` tag runs the release workflow: it rebuilds the script, confirms
the committed distributable is current, publishes `nwa.ps1` with a SHA-256
checksum, and creates the attestation.

MIT license.
