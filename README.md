# nwa

Network diagnostics for Windows. One script: run it, watch the live status in
the terminal, press Q - it builds and opens an HTML report that explains, in
plain language, what is wrong. Analysis stays local; snapshot public-IP lookup
is opt-in.

## Use

Download a versioned release rather than the mutable `main` branch, verify its
checksum, then run it under your organisation's PowerShell policy:

    $version = 'v0.1.0'   # replace with the release you want
    $base = "https://github.com/SolusKossi/nwa/releases/download/$version"
    irm "$base/nwa.ps1" -OutFile nwa.ps1
    irm "$base/SHA256SUMS.txt" -OutFile SHA256SUMS.txt
    $expected = ((Get-Content SHA256SUMS.txt) -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash .\nwa.ps1 -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw 'Checksum verification failed.' }
    powershell -NoProfile -File .\nwa.ps1

For an additional free provenance check on this public repository, install the
[GitHub CLI](https://cli.github.com/) and run:

    gh attestation verify .\nwa.ps1 -R SolusKossi/nwa

Options:

    -Snapshot            one-shot health check (~15 s) instead of monitoring
    -Sites "a.com,b.no"  also test reachability to your own sites
    -IntervalSec 10      seconds between checks
    -DurationHours 8     auto-stop (default: run until Q)
    -Report              generate the report without asking (scripted runs)
    -RunLabel "baseline" label a run for before/after comparison
    -IncludePublicIp     snapshot only; request the public IP from ipify.org

The report opens from the Desktop. Each run gets its own timestamped raw log
and report, written to %LOCALAPPDATA%\nwa and the Desktop respectively. This
preserves evidence for before/after comparison and avoids OneDrive locking
rapidly changing logs. You can also drop logs onto index.html to analyze them
in any browser (drop two to compare machines side by side) - try it with
sample-monitor.jsonl.

## What it measures

Every 10 s: ping bursts to the gateway and internet (loss, latency, jitter),
DNS, Wi-Fi signal / band / access point / roaming, Ethernet link speed, and
your optional sites. Periodically: channel congestion (nearby APs). On failure:
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

## Releases and signing

Pushing a `v*` tag runs the release workflow. It rebuilds the script, confirms
the committed distributable is current, publishes `nwa.ps1` with a SHA-256
checksum, and creates a GitHub build-provenance attestation.

MIT license.
