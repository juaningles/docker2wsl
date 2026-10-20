# tests\manifest_summary.ps1 <manifest.jsonl> <summary.txt>
# Parses every line as JSON (a parse failure is reported as "parse=failed") and writes
# quote-free key=value lines that batch tests can check with findstr.
param([string]$Manifest, [string]$Out)
$lines = @()
try {
  $recs = @(Get-Content -LiteralPath $Manifest -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
  $lines += 'parse=ok'
  $lines += 'events=' + (($recs | ForEach-Object { $_.event }) -join ',')
  $c = $recs | Where-Object { $_.event -eq 'create' } | Select-Object -First 1
  if ($c) {
    $lines += "schema=$($c.schema)"
    $lines += "command=$($c.command.line)"
    $lines += "image.requested=$($c.image.requested)"
    $lines += "image.id=$($c.image.id)"
    $lines += 'image.digests=' + (@($c.image.digests) -join ',')
    $lines += "image.digests.isarray=$($c.image.digests -is [array])"
    $lines += "image.pulled=$($c.image.pulled)"
    $lines += "distro.name=$($c.distro.name)"
    $lines += "distro.user=$($c.distro.user)"
    $lines += "distro.replaced=$($c.distro.replaced_existing)"
    $lines += "distro.os.isnull=$($null -eq $c.distro.os)"
    $lines += 'bootstrap.requested=' + ((@($c.straps.bootstrap) | ForEach-Object { $_.requested }) -join ',')
    $lines += 'poststrap.requested=' + ((@($c.straps.poststrap) | ForEach-Object { $_.requested }) -join ',')
    $lines += "tool.version=$($c.tool.version)"
    $lines += 'private=' + ((@($c.private) | ForEach-Object { $_.path }) -join ',')
  }
  $i = 0
  foreach ($s in ($recs | Where-Object { $_.event -eq 'strap' })) {
    $i++
    $lines += "strap$i=$($s.kind) $($s.requested) $($s.result) as=$($s.run_as) copy=$($s.rendered_copy) sha=$([bool]$s.sha256) rsha=$([bool]$s.rendered_sha256)"
  }
  $d = $recs | Where-Object { $_.event -eq 'complete' } | Select-Object -Last 1
  if ($d) { $lines += "complete=$($d.result) failed=$($d.failed)" }
} catch { $lines += 'parse=failed' }
Set-Content -LiteralPath $Out -Value $lines -Encoding ascii
