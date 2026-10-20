# CLAUDE.md - container2wsl

## Project Overview

Windows batch script that creates a WSL distribution from any Docker image.
`container2wsl.bat` works on its own, with no dependencies beyond Docker and WSL.
The optional `lib\manifest.ps1` next to it adds the build manifest; keep the
script working (banner `Manifest : off`) when that file is absent.

## Architecture

The main script runs 4-6 sequential steps via `call :subroutine` labels:
1. `docker_ensure_image` - check local / pull from registry
2. `docker_export_image` - `docker create` + `docker export` to tar
3. `wsl_import` - `wsl --import` with error detection
4. `wsl_configure_user` - create user, write `/etc/wsl.conf`, restart distro
5. `wsl_bootstrap` (optional) - run bootstrap file commands as root
6. `wsl_poststrap` (optional) - run poststrap file commands as user

Manifest (`:manifest`, `:manifest_strap`, `:manifest_complete`, plus `lib\manifest.ps1`):
`create` is written after step 4, a `strap` record after each strap (pass or fail), and
`complete` at the end or when a strap fails. The batch side passes **all** data to
PowerShell in environment variables (never arguments), the helper appends to the
Windows copy in the install dir, and the batch side copies the whole file into the
distro with `install -D`. Manifest problems print `[WARN]` and never fail the build.
PowerShell 5.1 traps in the helper: commands with no output give AutomationNull
(serialised as `{}`), and returning a 1-item array unrolls it. See `Quiet` and `,$list`.

## Critical WSL Quirks

These are hard-won lessons. Do not "simplify" these workarounds:

- **`wsl -d` and `-u` reject quoted values**: `wsl -d "name"` silently fails with "no distribution found"; `wsl -u "user"` fails with `getpwnam("user") failed`. Always use unquoted: `wsl -d name -u user`. `--import` and `--terminate` handle quotes fine.
- **WSL exits 0 on failure**: Both `wsl --import` and `wsl -d ... -- cmd` return exit code 0 even when they fail. Must capture output to a file and check for UTF-16 LE error text via `findstr /c:"E r r o r"`.
- **`bash -c` quoting is broken**: `wsl -d NAME -- bash -c "cmd 'arg'"` includes the trailing `"` in the argument. Use direct commands instead: `wsl -d NAME -u root -- useradd -m -s /bin/bash USERNAME`.
- **Windows line endings corrupt wsl.conf**: CMD `echo` writes `\r\n`. After copying a file into WSL, run `sed -i "s/\r//" /etc/wsl.conf` or the `[user]` section won't parse.
- **Distro readiness after import**: The distro is registered immediately after `wsl --import` but may take a moment to accept commands. The readiness check must capture output and look for error text (not just check exit code, since exit code is always 0).

## CMD Batch Scripting Gotchas

- **`)` in echo inside if/else blocks** closes the block early. Use delayed expansion variables (`!var!`) for any content that might contain `)`, or restructure to avoid if/else blocks entirely (use `goto` or flat `if` chains).
- **Calling a `.bat` without `call`** transfers control permanently. Always `call script.bat`.
- **Windows → WSL paths** go through `:win2lx` (lowercase drive letter → `/mnt/<d>/...`, no trailing `/`). Never write `C:/=/mnt/c/` substitutions; `%TEMP%` or the clone may live on another drive.
- **Private overlay folders**: `--private` → `C2W_PRIVATE_DIRS` (the caller's value is saved as `C2W_PRIVATE_DIRS_IN` on line 1 because the script rebuilds the variable) → siblings of `%C2W_SCRIPT_DIR%..` with a `.devtools-overlay` marker. `:add_private` builds both the `;` Windows list and the `:` `/mnt` list; `:resolve_strap` searches them after the built-in folders; `:set_strap_dir` exposes the running strap's folder. Loop over the `;` list with `for %%d in ("!C2W_PRIVATE_DIRS:;=" "!")`, which keeps paths with spaces whole.
- **Poststraps run as a normal user**: on Alpine neither the user's PATH nor sudo's `secure_path` includes `/sbin`, so call `/sbin/apk` by full path; and `~/.local/bin` is not on PATH in a bare login shell, so anything you add to `~/.profile` must reference `$HOME/.local/bin/<tool>` explicitly.
- **Strap scripts run under `set -e`**, so a trailing `while` loop or `cmd && other` whose last evaluation is false aborts the strap silently. Use `if`; and a pipeline's status is the last command's, so capture `powershell.exe` output to a file when its exit code matters (see ssh-keys).
- **`shift` also shifts `%0`**, so after argument parsing `%~dp0` in the main flow points at an argument, not the script. Use `%C2W_SCRIPT_DIR%`, captured at the top of the script. Inside a `call :label` subroutine `%~dp0` is fine. Mocked tests run from the repo folder can hide this; test_06 runs from `%TEMP%`.
- **`goto :label 2>nul || (fallback)`** does not work reliably. Use explicit `if` chains.
- **`>` in echo** is parsed as redirect. Don't use `>` as a display character in batch echo statements.
- **Unicode characters** (`---`, checkmarks, bullets) don't survive CMD's codepage. Use ASCII only for display.
- **Strap lines are re-parsed by CMD** in the command display loop (`call set "_BS_EXPANDED=!_BS_LINE!"`). The quoting flips, so `>`, `<`, `|`, `&` inside a strap's double quotes become live CMD operators and can create stray files. `%*` expands to the subroutine's args. Keep those characters outside double quotes. test_04 #21 checks the built-ins for stray files.

## Testing

```
tests\run_tests.bat                        # run all (315 assertions)
tests\run_tests.bat test_01                # run one file
tests\run_tests.bat --html report.html     # generate HTML report with colors
tests\run_tests.bat --force                # skip collision pre-check
```

- Tests use mock `docker.bat` and `wsl.bat` injected via PATH
- Each run generates a random `C2W_TEST_ID` (e.g. `c2wt12345`) used as prefix for all WSL distro names
- Pre-flight checks `wsl --list` for leftover `c2wt*` distros; refuses without `--force`
- Post-run automatically unregisters any `c2wt*` distros and cleans storage dirs
- `test_01_args` uses `--dry-run` only (no mocks needed)
- `test_02_docker` and `test_03_wsl` use mocks
- `test_04_bootstrap` tests bootstrap execution (mocked)
- `test_05_poststrap` tests poststrap execution (mocked)
- `test_06_manifest` tests the build manifest (mocked; `manifest_summary.ps1` parses the JSON Lines)
- Assertion helpers use `setlocal enabledelayedexpansion` + flat `if/goto` to avoid block-parsing bugs
- ANSI colors in output: green PASS, red FAIL, yellow test headers, cyan file names

## File Layout

```
container2wsl.bat            # main script (works alone)
lib/
  manifest.ps1               # optional: build manifest (JSON Lines) writer
  ssh-source-check.ps1       # Windows ACL check for ssh-keys sources (owner/SYSTEM/Administrators only)
  c2w-manifest               # sh+awk report, installed in the distro as /usr/local/bin/c2w-manifest (LF only, see .gitattributes)
bootstraps/
  devtools                   # git, curl, build-essential, jq, etc.
  homebrew                   # Linuxbrew + dependencies + prefix ownership setup
  sudo                       # install sudo + passwordless sudoers entry
  systemd-enable             # enable systemd in wsl.conf
  zsh                        # zsh + Oh My Zsh
  k8s-tools                  # kubectl, kubelogin, helm 4, yq -> /usr/local/bin (apt/apk)
  data-tools                 # jq, miller, make, unzip, curl (apt/apk)
  azure-cli                  # az via Microsoft's apt repo
  motd                       # zsh login header: c2w-manifest --short via /etc/zsh/zlogin
poststraps/
  powerlevel10k             # installs Oh My Zsh if needed, theme, and plugins
  brew-python               # brew python (superseded by uv)
  uv                        # uv + uv-managed default python (C2W_UV_PYTHON pins)
  devtools-shell            # clone devtools to ~/devtools + install.sh (C2W_DEVTOOLS_REPO, else ../devtools)
  devtools-overlay          # clone each private overlay folder + devtools install.sh --overlay
  ssh-keys                  # ~/.ssh from <private>/ssh or C2W_SSH_SOURCE; refuses open ACLs/modes
  keychain                  # keychain package or upstream 2.8.5 script; ~/.keychain_default_keys
  claude                    # Claude Code, native installer (C2W_CLAUDE_VERSION)
  databricks-ug             # Databricks Unity Gateway (ug, formerly ucode) + Databricks CLI
tests/
  run_tests.bat              # test runner with --html, --force, pre-flight checks
  helpers.bat                # assertion library (10 assertion types)
  test_01_args.bat           # argument parsing tests (--dry-run, no mocks)
  test_02_docker.bat         # docker step tests (mocked)
  test_03_wsl.bat            # wsl import + user config tests (mocked)
  test_04_bootstrap.bat      # bootstrap feature tests (mocked)
  test_05_poststrap.bat      # poststrap feature tests (mocked)
  test_06_manifest.bat       # build manifest tests (mocked)
  manifest_summary.ps1       # parses a manifest into key=value lines for asserts
  mocks/
    docker.bat               # mock docker (controlled via C2W_MOCK_* vars)
    wsl.bat                  # mock wsl (controlled via C2W_MOCK_* vars)
```

## Mock Control Variables

| Variable | Default | Effect |
|---|---|---|
| `C2W_MOCK_IMAGE_EXISTS` | 0 | 1 = docker image inspect succeeds |
| `C2W_MOCK_PULL_FAIL` | 0 | 1 = docker pull fails |
| `C2W_MOCK_CREATE_FAIL` | 0 | 1 = docker create fails |
| `C2W_MOCK_EXPORT_FAIL` | 0 | 1 = docker export fails |
| `C2W_MOCK_WSL_IMPORT_FAIL` | 0 | 1 = wsl --import fails |
| `C2W_MOCK_WSL_BASH_FAIL` | 0 | 1 = wsl bash commands fail |
| `C2W_MOCK_WSL_DISTRO_EXISTS` | (unset) | name to report as existing in wsl --list --quiet |
| `C2W_MOCK_CONTAINER_ID` | mock-container-abc123 | ID returned by docker create |
| `C2W_MOCK_LOG` | (unset) | path to log file for mock calls |
