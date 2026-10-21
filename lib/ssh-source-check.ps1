<#
  lib\ssh-source-check.ps1 - refuse an ssh source folder whose Windows ACLs are too open.

  Mirrors the check Windows OpenSSH applies to ~/.ssh: the folder and every private key
  may grant access only to the folder's owner, SYSTEM and Administrators. Any other Allow
  entry (Users, Authenticated Users, Everyone, another account, ...) is reported and the
  script exits 1 with the icacls command that fixes it. Exit 0 = acceptable.

    powershell -NoProfile -ExecutionPolicy Bypass -File lib\ssh-source-check.ps1 -Path C:\...\ssh

  Called by the ssh-keys poststrap through WSL interop (powershell.exe) before anything is
  copied. POSIX modes are useless for this: everything under /mnt/c shows as 777.
#>
param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Container)) { Write-Output "[ssh-keys] not a folder: $Path"; exit 1 }
$dir = Get-Item -LiteralPath $Path
$acl = Get-Acl -LiteralPath $dir.FullName
try { $ownerSid = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier]) }
catch { Write-Output "[ssh-keys] cannot resolve the owner of $($dir.FullName): $($acl.Owner)"; exit 1 }
$allowed = @($ownerSid.Value, 'S-1-5-18', 'S-1-5-32-544')   # owner, SYSTEM, Administrators

function Offending([string]$item) {
  $a = Get-Acl -LiteralPath $item
  foreach ($r in $a.Access) {
    if ($r.AccessControlType -ne 'Allow') { continue }
    try { $sid = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $sid = "$($r.IdentityReference)" }
    if ($sid -notin $allowed) { "  $item : $($r.IdentityReference) ($($r.FileSystemRights))" }
  }
}

# private keys = everything that is not public, config or documentation
$skip = '^(.*\.pub|config|known_hosts.*|authorized_keys|README.*|.*\.md)$'
$bad = @(Offending $dir.FullName)
$unreadable = @()
foreach ($f in Get-ChildItem -LiteralPath $dir.FullName -File -Force) {
  if ($f.Name -notmatch $skip) { $bad += @(Offending $f.FullName) }
  # WSL reads /mnt files with this (non-elevated) token: a file that only Administrators may
  # read passes the ACL test above but fails at copy time, so test real read access too.
  if ($f.Name -notmatch '^(README.*|.*\.md)$') {
    try { [IO.File]::OpenRead($f.FullName).Close() } catch { $unreadable += $f.FullName }
  }
}

$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($bad.Count -eq 0 -and $unreadable.Count -eq 0) { Write-Output "[ssh-keys] ACL ok: $($dir.FullName) (owner $($acl.Owner))"; exit 0 }
if ($bad.Count -gt 0) {
  Write-Output "[ssh-keys] REFUSED: $($dir.FullName) is readable by accounts other than the owner, SYSTEM and Administrators:"
  $bad | Sort-Object -Unique | ForEach-Object { Write-Output $_ }
  Write-Output "[ssh-keys] Fix it from a Windows shell (owner only, inheritance off), then rerun:"
  Write-Output ("  icacls ""{0}"" /inheritance:r /grant:r ""{1}:(OI)(CI)F"" ""SYSTEM:(OI)(CI)F"" ""Administrators:(OI)(CI)F""" -f $dir.FullName, $acl.Owner)
}
if ($unreadable.Count -gt 0) {
  Write-Output "[ssh-keys] REFUSED: these files are not readable by $me (WSL runs with this non-elevated token, so the copy would fail):"
  $unreadable | ForEach-Object { Write-Output "  $_" }
  Write-Output "[ssh-keys] Give yourself explicit access (keeps SYSTEM/Administrators), then rerun:"
  $unreadable | ForEach-Object { Write-Output ("  icacls ""{0}"" /grant:r ""{1}:F"" ""SYSTEM:F"" ""Administrators:F""" -f $_, $me) }
}
exit 1
