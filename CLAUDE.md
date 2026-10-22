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

**Container target** (`--target container`, `:ct_*` labels): steps 2-3 become `:ct_flow`
(`<engine> run -d --entrypoint sleep ... infinity` with bind mounts, then useradd/usermod), and the
run jumps back to the shared `:after_target_setup`. Every command into the target goes through the
`%T_ROOT%` / `%T_USER%` prefixes (`wsl -d NAME -u X --` or `<docker> exec -u X NAME`), set once in
`:main`; do not call `%WSL_CMD% -d` directly in shared code. `:ct_add_mount` mounts each host folder
at its `:win2lx` path so `*_LX` variables mean the same in both targets. `:ct_finish` commits
(`--change` resets the sleep entrypoint) and leaves the container running.
`container2x.sh` is the macOS/Linux runner for the same straps (docker, podman, Apple `container`);
it must stay bash 3.2 compatible (macOS `/bin/bash`): no associative arrays, `mapfile`, `${x^}`,
and guard empty arrays under `set -u` with `${a[@]+"${a[@]}"}`. docs/RUNNERS.md is the contract both
keep (rendering rules, variables, mounts, manifest).

**Recipes** (`--recipe NAME`, `--recipes`; `:recipe_*` labels, run before anything else):
`:recipe_scan` splits the command line, `:recipe_run` finds `recipes\NAME.conf` (`:recipe_dirs`:
this repo first, for the samples in `recipes\`, then `--private`, else `C2W_PRIVATE_DIRS`, else
marked siblings; the last match wins, so an overlay recipe replaces a sample of the same name),
turns the keys into arguments, and calls the script again with those first and the user's after, so
the command line wins. The recipe path reaches the inner run as `_C2W_FROM_RECIPE` (cleared at the
top, kept as `C2W_RECIPE` for the manifest). container2x.sh does the same with
`_C2X_FROM_RECIPE` and `exec`. `rebuild-wsl.bat` / `rebuild-container` are one-line wrappers.

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
- **Temp files live in a per-run folder** `%C2W_TMP%` (`%TEMP%\c2w-run-<random>`, made in `:after_dryrun`, removed by `:manifest_complete`, swept after a day if a build died early). Never use a fixed `%TEMP%\c2w_*` name: two builds, or a build and the test suite, would overwrite each other's rendered scripts and stamps. The test runner points `TEMP` at its own folder.
- **Strap names resolve to files only**: `if exist X` is also true for a folder, so every candidate in `:resolve_strap` also checks `if not exist X\`, and the runners refuse a folder. Run from `C:\code`, `-b devtools` once picked the devtools repo folder and "ran" 0 commands.
- **Windows → WSL paths** go through `:win2lx` (lowercase drive letter → `/mnt/<d>/...`, no trailing `/`). Never write `C:/=/mnt/c/` substitutions; `%TEMP%` or the clone may live on another drive.
- **Private overlay folders**: `--private` → `C2W_PRIVATE_DIRS` (the caller's value is saved as `C2W_PRIVATE_DIRS_IN` on line 1 because the script rebuilds the variable) → siblings of `%C2W_SCRIPT_DIR%..` with a `.devtools-overlay` marker. `:add_private` builds both the `;` Windows list and the `:` `/mnt` list; `:resolve_strap` searches them after the built-in folders; `:set_strap_dir` exposes the running strap's folder. Loop over the `;` list with `for %%d in ("!C2W_PRIVATE_DIRS:;=" "!")`, which keeps paths with spaces whole.
- **Poststraps run as a normal user**: on Alpine neither the user's PATH nor sudo's `secure_path` includes `/sbin`, so call `/sbin/apk` by full path; and `~/.local/bin` is not on PATH in a bare login shell, so anything you add to `~/.profile` must reference `$HOME/.local/bin/<tool>` explicitly.
- **drvfs owner mapping**: a Windows file that only its owner may read appears under `/mnt` as mode 600 owned by uid 1000, whatever the mount's `uid=` says. A distro user with another uid (the image's own first user takes 1000) gets `Permission denied` although Windows would allow it; root does not. ssh-keys reads such files through `sudo -n cat` (see `rd`). Also, inside a strap `set -e` kills a bare failing command before `RC=$?` runs: wrap it in `if`.
- **Strap text: the script that runs vs the listing.** The `.sh` that runs is rendered by PowerShell `ExpandEnvironmentVariables`: only `%NAME%` of a defined variable expands, so write a literal `%` as `%` (`stat -c %a`, `printf '%s'`), never `%%` (it stays `%%`). The `[N]` listing and `--dry-run` echo lines through cmd (`call set`), which drops `!` and lone `%`, eats from a lone `!` to a later `:` on the line (`if ! lx az; then curl https://...` lists as `if //...`), and cuts a line at nested double quotes followed by `2>` or `|`; that is cosmetic, but tests grep the listing, so keep strap lines free of `"..."$x"..." 2>` patterns where you can.
- **Windows PATH in WSL**: WSL appends the Windows PATH, and the Windows Azure CLI ships an extensionless bash wrapper (`.../CLI2/wbin/az`), so `command -v az` succeeds in a distro with no Linux az. Install checks use `lx NAME` (defined at the top of azure-cli, k8s-tools, databricks-ug), which ignores `/mnt/*` hits.
- **Strap scripts run under `set -e`**, so a trailing `while` loop or `cmd && other` whose last evaluation is false aborts the strap silently. Use `if`; and a pipeline's status is the last command's, so capture `powershell.exe` output to a file when its exit code matters (see ssh-keys).
- **`shift` also shifts `%0`**, so after argument parsing `%~dp0` in the main flow points at an argument, not the script. Use `%C2W_SCRIPT_DIR%`, captured at the top of the script. Inside a `call :label` subroutine `%~dp0` is fine. Mocked tests run from the repo folder can hide this; test_06 runs from `%TEMP%`.
- **`goto :label 2>nul || (fallback)`** does not work reliably. Use explicit `if` chains.
- **`>` in echo** is parsed as redirect. Don't use `>` as a display character in batch echo statements.
- **Unicode characters** (`---`, checkmarks, bullets) don't survive CMD's codepage. Use ASCII only for display.
- **Strap lines are re-parsed by CMD** in the command display loop (`call set "_BS_EXPANDED=!_BS_LINE!"`). The quoting flips, so `>`, `<`, `|`, `&` inside a strap's double quotes become live CMD operators and can create stray files. `%*` expands to the subroutine's args. Keep those characters outside double quotes. test_04 #21 checks the built-ins for stray files.

## Testing

```
tests\run_tests.bat                        # run all (402 assertions)
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
- `test_07_container` tests `--target container` (mocked docker; the wsl mock must never be called)
- `test_08_recipe` tests `--recipe` / `--recipes` and the `rebuild-wsl.bat` wrapper (dry runs)
- `tests/sh/run.sh` (bash, run from WSL/Linux/macOS) tests `container2x.sh` with `tests/sh/mock-engine`;
  run it under bash 3.2 too: `podman run --rm -v C:\code\docker2wsl:/src:ro docker.io/library/bash:3.2 bash -c 'cp -r /src /w && cd /w && bash tests/sh/run.sh'`
- `tests/sh/real.sh` does real builds; the Apple suite only runs on a Mac, so a real Apple run is
  something the user does after pulling (`tests/sh/run.sh --real`)
- Assertion helpers use `setlocal enabledelayedexpansion` + flat `if/goto` to avoid block-parsing bugs
- ANSI colors in output: green PASS, red FAIL, yellow test headers, cyan file names

## File Layout

```
container2wsl.bat            # main script (works alone): WSL distro, or --target container
container2x.sh               # macOS/Linux runner: running container via docker, podman or Apple container
rebuild-wsl.bat              # shorthand: container2wsl.bat --recipe NAME (alone: --recipes)
recipes/
  default.conf               # sample recipe: stock Ubuntu + public straps; an overlay's default.conf replaces it
rebuild-container            # shorthand: container2x.sh --recipe NAME (alone: --recipes)
docs/RUNNERS.md              # the contract both runners keep (rendering, variables, mounts, manifest)
lib/
  manifest.ps1               # optional: build manifest (JSON Lines) writer
  ssh-source-check.ps1       # Windows ACL check for ssh-keys sources (owner/SYSTEM/Administrators only)
  c2w-manifest               # sh+awk report, installed in the distro as /usr/local/bin/c2w-manifest (LF only, see .gitattributes)
bootstraps/
  devtools                   # git, curl, build-essential, jq, etc.
  homebrew                   # Linuxbrew + dependencies + prefix ownership setup
  sudo                       # install sudo + passwordless sudoers entry
  systemd-enable             # enable systemd in wsl.conf + /etc/binfmt.d/WSLInterop.conf (keeps interop alive)
  zsh                        # zsh + Oh My Zsh
  k8s-tools                  # kubectl, kubelogin, helm 4, yq -> /usr/local/bin (apt/apk), + dnsutils/bind-tools
  data-tools                 # jq, miller, make, unzip, curl (apt/apk)
  azure-cli                  # az via Microsoft's apt repo
  motd                       # zsh login header: c2w-manifest --short via /etc/zsh/zlogin
poststraps/
  powerlevel10k             # installs Oh My Zsh if needed, theme, and plugins
  brew-python               # brew python (superseded by uv)
  uv                        # uv + uv-managed default python (C2W_UV_PYTHON pins)
  devtools-shell            # clone devtools to ~/devtools + install.sh (C2W_DEVTOOLS_REPO, else ../devtools)
  devtools-overlay          # clone each private overlay folder + devtools install.sh --overlay
  ssh-keys                  # ~/.ssh from <private>/ssh or C2W_SSH_SOURCE; refuses open ACLs/modes; AddKeysToAgent yes
  keychain                  # keychain package or upstream 2.8.5 script; agent starts empty, keys lazy-load
  claude                    # Claude Code, native installer (C2W_CLAUDE_VERSION)
  databricks-ug             # Databricks Unity Gateway (ug, formerly ucode) + Databricks CLI
  podman-machine            # podman + podman-docker client, default ssh connection to the Windows podman machine, remote = true
tests/
  run_tests.bat              # test runner with --html, --force, pre-flight checks
  helpers.bat                # assertion library (10 assertion types)
  test_01_args.bat           # argument parsing tests (--dry-run, no mocks)
  test_02_docker.bat         # docker step tests (mocked)
  test_03_wsl.bat            # wsl import + user config tests (mocked)
  test_04_bootstrap.bat      # bootstrap feature tests (mocked)
  test_05_poststrap.bat      # poststrap feature tests (mocked)
  test_06_manifest.bat       # build manifest tests (mocked)
  test_07_container.bat      # --target container tests (mocked docker; no wsl calls allowed)
  test_08_recipe.bat         # --recipe / --recipes and rebuild-wsl.bat (--dry-run, no mocks)
  sh/run.sh                  # container2x.sh mock suite (bash 3.2+); --real adds sh/real.sh
  sh/real.sh                 # real container2x.sh builds per engine; SKIP where an engine is missing
  sh/mock-engine             # fake docker / podman / container CLI (behaves by the name it is called as)
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
| `C2W_MOCK_CT_EXISTS` | 0 | 1 = docker container inspect finds the container (container target) |
| `C2W_MOCK_RUN_FAIL` | 0 | 1 = docker run fails |
| `C2W_MOCK_EXEC_FAIL` | 0 | 1 = docker exec fails |
| `C2W_MOCK_COMMIT_FAIL` | 0 | 1 = docker commit fails |
| `C2W_MOCK_LOG` | (unset) | path to log file for mock calls |

`tests/sh/mock-engine` (installed as `docker`, `podman` and `container` for `tests/sh/run.sh`; behaves by the name it is called as):

| Variable | Default | Effect |
|---|---|---|
| `C2X_MOCK_LOG` | (unset) | every call appended as `<name> <args>` |
| `C2X_MOCK_IMAGE_EXISTS` | 1 | 0 = image inspect fails (triggers a pull) |
| `C2X_MOCK_EXISTS` | 0 | 1 = the container already exists (`C2X_MOCK_NAME` is what Apple `list` prints) |
| `C2X_MOCK_RUN_FAIL`, `C2X_MOCK_STRAP_FAIL`, `C2X_MOCK_COMMIT_FAIL`, `C2X_MOCK_BUILD_FAIL` | 0 | 1 = that step fails (`BUILD` is the build in Apple's commit step) |
| `C2X_MOCK_SCRIPTS` | (unset) | folder that receives a copy of every rendered script run through exec |
| `C2X_MOCK_SHELL` | /usr/bin/zsh | login shell reported by `getent passwd` |
