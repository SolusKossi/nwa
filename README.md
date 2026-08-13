# nwa

Network diagnostics for Windows. One script: run it, watch the live status in
the terminal, press Q - it builds and opens an HTML report that explains, in
plain language, what is wrong. Everything is analyzed locally; nothing is uploaded.

## Use

    irm https://raw.githubusercontent.com/SolusKossi/nwa/main/nwa.ps1 -OutFile nwa.ps1
    powershell -ep bypass -f .\nwa.ps1

Options:

    -Snapshot            one-shot health check (~15 s) instead of monitoring
    -Sites "a.com,b.no"  also test reachability to your own sites
    -IntervalSec 10      seconds between checks
    -DurationHours 8     auto-stop (default: run until Q)
    -Report              generate the report without asking (scripted runs)

The report opens from the Desktop. The raw log (network-monitor.jsonl) is
written continuously to %LOCALAPPDATA%\nwa - deliberately outside
OneDrive-synced folders, which lock and fork rapidly-changing files. You can
also drop logs onto index.html to analyze them in any browser (drop two to
compare machines side by side) - try it with sample-monitor.jsonl.

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

MIT license.
