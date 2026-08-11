# Builds nwa.ps1 (the distributable) from src/nwa.src.ps1 + index.html.
# index.html is embedded base64 as the report template.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$tpl = [IO.File]::ReadAllText((Join-Path $root 'index.html'))
$marker = 'window.NWA_EMBEDDED = window.NWA_EMBEDDED || null;'
$n = ([regex]::Matches($tpl, [regex]::Escape($marker))).Count
if ($n -ne 1) { throw "index.html must contain the NWA_EMBEDDED marker exactly once (found $n)." }

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($tpl))
$src = [IO.File]::ReadAllText((Join-Path $root 'src\nwa.src.ps1'))
if ($src -notmatch '@@NWA_TEMPLATE_B64@@') { throw 'src/nwa.src.ps1 is missing the @@NWA_TEMPLATE_B64@@ placeholder.' }

$out = $src.Replace('@@NWA_TEMPLATE_B64@@', $b64)
[IO.File]::WriteAllText((Join-Path $root 'nwa.ps1'), $out, (New-Object Text.UTF8Encoding($false)))

$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'nwa.ps1'), [ref]$null, [ref]$e)
if ($e.Count) { $e | ForEach-Object { Write-Host "$($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red }; throw 'nwa.ps1 does not parse.' }
Write-Host ("Built nwa.ps1 ({0} KB) - parse OK." -f [math]::Round((Get-Item (Join-Path $root 'nwa.ps1')).Length / 1kb))
