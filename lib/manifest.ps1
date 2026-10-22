<#
  lib\manifest.ps1 - build-manifest records for container2wsl.bat (optional helper).

  Appends one JSON object per line (JSON Lines) to
    <install path>\container2wsl-manifest.jsonl     (Windows master copy)
  and mirrors the whole file to $env:C2W_M_TMP, which container2wsl.bat copies into
  the distro as /etc/container2wsl/manifest.jsonl.

  All input arrives in environment variables set by container2wsl.bat, never as
  arguments, so CMD never re-parses user-supplied text:
    C2W_M_ACTION   create | strap | complete
    common         INSTALL_PATH ARG_IMAGE ARG_WSL_NAME ARG_WSL_USER ARG_WSL_LOCATION
                   VERSION C2W_ARGV C2W_CWD C2W_SCRIPT_DIR DOCKER_CMD WSL_CMD FORCE
                   C2W_TARGET (wsl|container) C2W_ENGINE ARG_COMMIT
    create         C2W_IMAGE_PULLED C2W_BUILD_START ARG_{BOOT,POST}STRAP_N/_i/_REQ_i
    strap          C2W_M_KIND C2W_M_INDEX C2W_M_SEQ C2W_M_REQ C2W_M_PATH C2W_M_SH
                   C2W_M_COPY C2W_M_COUNT C2W_M_RESULT C2W_M_AS C2W_STRAP_START
    complete       C2W_M_RESULT C2W_M_FAILED C2W_BUILD_START
  Exit code is always 0 unless the record could not be written at all.
#>
$ErrorActionPreference = 'Stop'
$enc = New-Object Text.UTF8Encoding $false

function Now { [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
function Ev([string]$n) { $v = [Environment]::GetEnvironmentVariable($n); if ($v) { $v } else { $null } }
# Windows PowerShell 5.1 pitfalls handled below: a command with no output yields
# AutomationNull (ConvertTo-Json writes it as {}), and returning a 1-item array unrolls it.
function Quiet([scriptblock]$b) { try { $r = & $b; if ($null -eq $r) { return $null }; return $r } catch { return $null } }
function ReadStamp([string]$file) {
  Quiet { if ($file -and (Test-Path $file)) { [DateTime]::Parse((Get-Content $file -Raw).Trim()).ToUniversalTime() } }
}
function Seconds($start) { if ($start) { [math]::Round(([DateTime]::UtcNow - $start).TotalSeconds, 1) } else { $null } }
# Run a .bat/.exe through cmd so mocks (docker.bat, wsl.bat) behave like the real tools.
function RunCmd([string]$cmdline) { Quiet { $o = & cmd /c "$cmdline 2>nul"; if ($LASTEXITCODE -eq 0) { $o } } }
function Sha256([string]$path) { Quiet { if ($path -and (Test-Path -LiteralPath $path)) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() } } }
function GitInfo([string]$path) {
  # commit of the repo holding $path, and whether $path (or the repo) has local edits
  Quiet {
    if (-not $path -or -not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $dir = if (Test-Path -LiteralPath $path -PathType Container) { $path } else { Split-Path -Parent $path }
    $commit = (& git -C $dir rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $commit) { return $null }
    $dirty = [bool](& git -C $dir status --porcelain -- $path 2>$null)
    $remote = (& git -C $dir remote get-url origin 2>$null)
    [ordered]@{ commit = "$commit".Trim(); dirty = $dirty; remote = $(if ($remote) { "$remote".Trim() } else { $null }) }
  }
}
function StrapList([string]$kind) {
  $n = [int](Ev "ARG_${kind}_N")
  $list = @(for ($i = 1; $i -le $n; $i++) {
    [ordered]@{ requested = (Ev "ARG_${kind}_REQ_$i"); path = (Ev "ARG_${kind}_$i") }
  })
  return ,$list
}

$install = Ev 'INSTALL_PATH'
if (-not $install) { exit 1 }
$master = Join-Path $install 'container2wsl-manifest.jsonl'
$action = Ev 'C2W_M_ACTION'

switch ($action) {
  'create' {
    # previous build's manifest (e.g. --force rebuild) is kept, not lost
    if (Test-Path $master) { Move-Item $master (Join-Path $install 'container2wsl-manifest.prev.jsonl') -Force }

    $docker = Ev 'DOCKER_CMD'; $wsl = Ev 'WSL_CMD'; $name = Ev 'ARG_WSL_NAME'; $ref = Ev 'ARG_IMAGE'
    $img = Quiet { $j = (RunCmd "$docker image inspect `"$ref`"") -join "`n"; if ($j) { @(ConvertFrom-Json $j)[0] } }
    $osrel = Quiet {
      $target = Ev 'C2W_TARGET'
      $lines = if ($target -eq 'container') { RunCmd "$docker exec $name cat /etc/os-release" } else { RunCmd "$wsl -d $name -u root -- cat /etc/os-release" }
      $p = @($lines | Where-Object { $_ -match '^PRETTY_NAME=' }) | Select-Object -First 1
      if ($p) { ($p -replace '^PRETTY_NAME=', '').Trim('"') }
    }
    $env:WSL_UTF8 = '1'
    $wslver = if ((Ev 'C2W_TARGET') -eq 'container') { $null } else { Quiet { $v = @(RunCmd "$wsl --version") | Where-Object { $_ -match '\d+\.\d+' } | Select-Object -First 1; if ($v -and $v -notmatch 'MOCK') { "$v".Trim() } } }
    $engine = Quiet { $v = @(RunCmd "$docker --version") | Select-Object -First 1; if ($v -and $v -notmatch 'MOCK') { "$v".Trim() } }

    $rec = [ordered]@{
      schema  = 1
      event   = 'create'
      time    = Now
      build_started = Quiet { (ReadStamp (Ev 'C2W_BUILD_START')).ToString('yyyy-MM-ddTHH:mm:ssZ') }
      command = [ordered]@{ line = "container2wsl.bat $(Ev 'C2W_ARGV')".TrimEnd(); cwd = (Ev 'C2W_CWD') }
      image   = [ordered]@{
        requested = $ref
        id        = $(if ($img) { $img.Id } else { $null })
        digests   = @(if ($img -and $img.RepoDigests) { $img.RepoDigests })
        tags      = @(if ($img -and $img.RepoTags) { $img.RepoTags })
        created   = $(if ($img) { "$($img.Created)" } else { $null })
        os        = $(if ($img) { $img.Os } else { $null })
        arch      = $(if ($img) { $img.Architecture } else { $null })
        size      = $(if ($img) { $img.Size } else { $null })
        pulled    = ((Ev 'C2W_IMAGE_PULLED') -eq '1')
      }
      distro  = [ordered]@{
        name = $name; user = (Ev 'ARG_WSL_USER'); install_path = $install
        os = $osrel; replaced_existing = ((Ev 'FORCE') -eq '1')
        target = $(if (Ev 'C2W_TARGET') { Ev 'C2W_TARGET' } else { 'wsl' }); engine = (Ev 'C2W_ENGINE'); commit = (Ev 'ARG_COMMIT')
      }
      straps  = [ordered]@{ bootstrap = (StrapList 'BOOTSTRAP'); poststrap = (StrapList 'POSTSTRAP') }
      private = @(foreach ($d in @((Ev 'C2W_PRIVATE_DIRS') -split ';' | Where-Object { $_ })) { [ordered]@{ path = $d; git = (GitInfo $d) } })
      tool    = [ordered]@{ name = 'container2wsl'; version = (Ev 'VERSION'); path = (Ev 'C2W_SCRIPT_DIR'); git = (GitInfo (Ev 'C2W_SCRIPT_DIR')) }
      host    = [ordered]@{
        computer = $env:COMPUTERNAME; windows_user = $env:USERNAME
        windows = [Environment]::OSVersion.Version.ToString(); wsl = $wslver; engine = $engine
      }
    }
  }
  'strap' {
    $path = Ev 'C2W_M_PATH'
    $rec = [ordered]@{
      event      = 'strap'
      time       = Now
      kind       = (Ev 'C2W_M_KIND')
      index      = [int](Ev 'C2W_M_INDEX')
      seq        = [int](Ev 'C2W_M_SEQ')
      requested  = (Ev 'C2W_M_REQ')
      path       = $path
      sha256     = (Sha256 $path)
      git        = (GitInfo $path)
      rendered_sha256 = (Sha256 (Ev 'C2W_M_SH'))
      rendered_copy   = (Ev 'C2W_M_COPY')
      run_as     = (Ev 'C2W_M_AS')
      commands   = [int](Ev 'C2W_M_COUNT')
      duration_s = (Seconds (ReadStamp (Ev 'C2W_STRAP_START')))
      result     = (Ev 'C2W_M_RESULT')
    }
  }
  'complete' {
    $rec = [ordered]@{
      event      = 'complete'
      time       = Now
      result     = (Ev 'C2W_M_RESULT')
      failed     = (Ev 'C2W_M_FAILED')
      duration_s = (Seconds (ReadStamp (Ev 'C2W_BUILD_START')))
    }
  }
  default { exit 1 }
}

$line = ($rec | ConvertTo-Json -Compress -Depth 6) + "`n"
[IO.File]::AppendAllText($master, $line, $enc)
$tmp = Ev 'C2W_M_TMP'
if ($tmp) { Copy-Item -LiteralPath $master -Destination $tmp -Force }
exit 0
