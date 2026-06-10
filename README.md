# nwa

A small network diagnostic for Windows. You run a PowerShell probe on a PC, then drop
the file it produces onto a single web page that analyzes it and tells you, in plain
language, what is wrong.

Everything is analyzed in your browser. Nothing is uploaded.

## How to use it

1. Open `index.html` in a browser.
2. Pick a mode:
   - **Snapshot**: a one-shot health check (about 15 seconds).
   - **Monitor**: keeps checking until you press Ctrl+C. Use this for intermittent
     problems (dropouts, jitter, Wi-Fi roaming, slow DNS).
3. Download the script, run it in PowerShell, and stop it when you are done. It writes
   a report and opens it for you.

To try it without running anything, drag `sample-monitor.jsonl` onto the page.

## Notes

- Analyzing works in any browser. Collecting the data needs Windows + PowerShell
  (no admin required).
- Files: `index.html` (the app), `collect.ps1` and `monitor.ps1` (the probes),
  `sample-monitor.jsonl` (demo data).

## License

MIT
