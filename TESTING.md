# Testing container2wsl

## Running Tests

```cmd
:: Run all tests
tests\run_tests.bat

:: Run a specific test file
tests\run_tests.bat test_01

:: Generate an HTML report (useful when ANSI colors don't render)
tests\run_tests.bat --html report.html

:: Force-run even if leftover test distros exist
tests\run_tests.bat --force
```

## Test Architecture

Tests use **mock** `docker.bat` and `wsl.bat` scripts injected via `PATH` override. The mocks are copied from `tests\mocks\` into a per-run temp directory, which is prepended to `PATH` so they are found before the real executables. No real Docker containers are created and no real WSL imports happen during testing.

WSL distro names are randomized (`c2wt<random>-<testname>`) to avoid collisions with real distros.

## Test Files

### `test_01_args.bat` — Argument Parsing (NO MOCKS)

These tests use `--dry-run` mode, which parses arguments and prints the resolved configuration without calling Docker or WSL at all. No mocks are needed.

| Test | What it verifies |
|------|-----------------|
| No arguments | Shows help, exits non-zero |
| `--help` / `-h` | Shows help with all option names |
| Image only (dry-run) | Derived name, default user, default storage |
| `--name` / `-n` | Custom distro name used instead of derived |
| `--user` | Custom user replaces default `wsluser` |
| `--location` | Custom storage path |
| Name derivation | `/` and `:` in image name become `-` |
| `--force` dry-run | Force label shown in config display |
| Unknown flag | Exits non-zero |
| Bare bootstrap name resolves | `-b sudo` resolves to `bootstraps\sudo`, commands listed |
| Multiple bare names resolve | `-b zsh -b devtools` both resolve, commands listed |
| Nonexistent bare name warns | `-b bogus` shows WARNING in dry-run |
| Mixed bare + explicit path | `-b sudo -b <tmpfile>` both resolve |
| `bootstraps\name` from different CWD | Resolves via script dir when CWD differs |
| Bare poststrap name resolves | `-p powerlevel10k` resolves to `poststraps\powerlevel10k`, commands listed |

### `test_02_docker.bat` — Docker Operations (MOCKED docker + wsl)

Both `docker.bat` and `wsl.bat` mocks are active. The WSL mock always succeeds so only Docker behavior is exercised.

| Test | Mock config | What it verifies |
|------|------------|-----------------|
| Image exists locally | `IMAGE_EXISTS=1` | No pull attempted, "Found locally" message |
| Image not local, pull succeeds | `IMAGE_EXISTS=0`, `PULL_FAIL=0` | Pull attempted, "Pull complete" message |
| Image not local, pull fails | `IMAGE_EXISTS=0`, `PULL_FAIL=1` | Non-zero exit, ERROR message |
| Export succeeds | `IMAGE_EXISTS=1`, `EXPORT_FAIL=0` | "Export complete" message |
| `docker create` fails | `CREATE_FAIL=1` | Non-zero exit, ERROR message |
| `docker export` fails | `EXPORT_FAIL=1` | Non-zero exit |

### `test_03_wsl.bat` — WSL Operations (MOCKED docker + wsl)

Both mocks are active. The Docker mock always succeeds so only WSL behavior is exercised.

| Test | Mock config | What it verifies |
|------|------------|-----------------|
| WSL import succeeds | (defaults) | Exit 0, "Import complete" message |
| WSL import fails | `WSL_IMPORT_FAIL=1` | Non-zero exit, ERROR message |
| Default user configured | (defaults) | `wsluser` appears, "Default user set" message |
| Custom user configured | `--user alice` | `alice` appears in output |
| WSL bash commands fail | `WSL_BASH_FAIL=1` | Non-zero exit, ERROR message |
| Custom storage location | `--location <path>` | Storage directory created at specified path |
| SUCCESS banner | (defaults) | "SUCCESS" and `wsl -d <name>` shown |
| Distro exists, no `--force` | `WSL_DISTRO_EXISTS=<name>` | Non-zero exit, "already exists" error |
| Distro exists, with `--force` | `WSL_DISTRO_EXISTS=<name>`, `--force` | Exit 0, unregister message, SUCCESS |

### `test_04_bootstrap.bat` — Bootstrap Feature (MOCKED docker + wsl)

Both mocks are active. The Docker mock always succeeds so only bootstrap behavior is exercised.

| Test | Setup | What it verifies |
|------|-------|-----------------|
| Bootstrap succeeds | 2-command file | Exit 0, commands shown, "Bootstrap complete" message |
| Bootstrap file not found | nonexistent path | Non-zero exit, ERROR message |
| Bootstrap command fails | `WSL_BASH_FAIL=1` | Non-zero exit, ERROR message |
| Bootstrap shown in dry-run | `--dry-run --bootstrap` | Exit 0, bootstrap file and commands listed |
| Comments and empty lines | file with `#`, blank, command | Only real command runs, comment not executed |
| Multiple files in order | two `--bootstrap` flags | Both files run, file 1/2 and 2/2 headers shown |
| Multiple files in dry-run | `--dry-run` + two `--bootstrap` flags | Both files' commands listed |
| Second file fails | first valid + second missing | Non-zero exit, ERROR message |
| Variable expansion | file with `%C2W_NAME%`, `%C2W_USER%` | Variables expanded in executed commands |
| Env variable expansion | file with `%COMPUTERNAME%` | Standard env vars expanded |
| Variables in dry-run | `--dry-run` + file with `%C2W_USER%` | Variables expanded in listed commands |
| devtools built-in bootstrap | `bootstraps\devtools` path | Exit 0, apt-get install and jq shown |
| zsh built-in bootstrap | `bootstraps\zsh` path | Exit 0, chsh shown, C2W_USER expanded |
| systemd-enable built-in bootstrap | `bootstraps\systemd-enable` path | Exit 0, systemd=true and WSLInterop.conf shown |
| sudo built-in bootstrap | `bootstraps\sudo` path | Exit 0, NOPASSWD shown, C2W_USER expanded |
| Bare name resolves and executes | `-b sudo` (no path) | Resolves to script dir, exit 0, commands run |
| Bare name resolves from different CWD | `pushd %TEMP%` + `-b systemd-enable` | Resolves via script dir even when CWD differs |

### `test_05_poststrap.bat` — Poststrap Feature (MOCKED docker + wsl)

Both mocks are active. The Docker mock always succeeds so only poststrap behavior is exercised.
Poststrap runs commands as the created user (not root), unlike bootstrap.

| Test | Setup | What it verifies |
|------|-------|------------------|
| Poststrap succeeds | 2-command file | Exit 0, commands shown, "Poststrap complete" message |
| Poststrap file not found | nonexistent path | Non-zero exit, ERROR message |
| Poststrap command fails | `WSL_BASH_FAIL=1` | Non-zero exit, ERROR message |
| Poststrap shown in dry-run | `--dry-run --poststrap` | Exit 0, poststrap file and commands listed, shows user |
| Comments and empty lines | file with `#`, blank, command | Only real command runs, comment not executed |
| Multiple files in order | two `-p` flags | Both files run, file 1/2 and 2/2 headers shown |
| Second file fails | first valid + second missing | Non-zero exit, ERROR message |
| Variable expansion | file with `%C2W_NAME%`, `%C2W_USER%` | Variables expanded in executed commands |
| Variables in dry-run | `--dry-run` + file with `%C2W_USER%` | Variables expanded in listed commands |
| Username in header | `--user alice -p file` | Output contains "(as alice)" |
| Bootstrap + poststrap combo | `-b file -p file` | Both Bootstrap complete and Poststrap complete |
| `-p` shorthand | `-p file` | Poststrap complete shown |
| Poststrap in config banner | `--dry-run -p file` | "Poststrap:" label in banner |
| powerlevel10k built-in poststrap | `-p powerlevel10k` | Exit 0, Oh My Zsh install command and theme setup shown |
| Homebrew built-in bootstrap | `bootstraps\homebrew` path | Exit 0, build-essential, Linuxbrew prefix ownership fix, and Homebrew shown |
| uv, devtools-shell, claude, databricks-ug | built-in poststraps (`-p` by name) | Installer URLs shown; `C2W_UV_PYTHON`, `C2W_DEVTOOLS_REPO`, `C2W_CLAUDE_VERSION` expand; devtools-shell falls back to the `devtools` clone next to container2wsl; databricks-ug shows the legacy ucode URL fallback |
| devtools-overlay | `--private DIR -p devtools-overlay` | `C2W_PRIVATE_DIRS_LX` expanded into the script, `install.sh --overlay`, `safe.directory` |
| ssh-keys | `-p ssh-keys` | Windows ACL check wired in, a clear message when WSL interop is down (after trying to re-register it), Linux 700 / 600 mode checks, empty source folders skipped, `AddKeysToAgent yes` (lazy loading) |
| ssh-keys `C2W_SSH_SOURCE` | env var + `--dry-run` | the source folder is expanded into the script |
| keychain | `-p keychain` | package install, upstream script fallback, `~/.keychain_default_keys` as the opt-in preload list |
| podman-machine | `C2W_PODMAN_CONNECTION` + `-p podman-machine` | podman and podman-docker install, the variable expanded into the script, the default ssh connection, `remote = true`, the `XDG_RUNTIME_DIR` wrapper |

Also in `test_04_bootstrap.bat`: the new bootstraps (`k8s-tools` with `dnsutils` / `bind-tools`, `data-tools`, `azure-cli` with the `lx` check that ignores a Windows `az` on the WSL PATH, `motd`); bare names resolving from a private folder's `straps\` and `poststraps\`, with `C2W_STRAP_DIR_LX`, `C2W_SCRIPT_DIR_LX`, `C2W_PRIVATE_DIRS_LX` and `C2W_USERPROFILE_LX` expanded and a built-in strap winning over a private one of the same name; and a dry run of every built-in strap at once, from an empty folder, asserting that CMD's command display creates no stray files.

Also in `test_01_args.bat`: `--private` (folder with a space, missing folder is an error), `C2W_PRIVATE_DIRS` with two folders, auto-detection of a sibling with a `.devtools-overlay` marker from a copy of the script (an unmarked sibling is ignored), and the storage root default (`%SystemDrive%\wsl-storage`) and its `C2W_LOCATION` override.

### `test_06_manifest.bat` — Build manifest (MOCKED docker + wsl)

Distros are stored under `%C2W_TMPDIR%\store`; `tests\manifest_summary.ps1` parses the JSON Lines manifest (any parse failure is reported) into quote-free `key=value` lines for `findstr`.

| Test | Setup | What it verifies |
|------|-------|------------------|
| Full build | run from `%TEMP%`, `-b sudo -p uv --private DIR`, canned `image inspect` JSON | create, two strap records, complete; command line, image id and digests (as an array), pulled flag, user, requested strap names, private folder, rendered-script copies root-only, `c2w-manifest` installed |
| Pulled image | `C2W_MOCK_IMAGE_EXISTS=0` | `pulled=true`; create + complete only |
| Failed build | poststrap file missing | strap and complete records, complete names the failed step |
| `--force` | distro reported as existing | previous manifest kept as `.prev.jsonl`, `replaced_existing=true` |
| Dry run | `--dry-run` | banner names the manifest, nothing written |
| No helper | copy of the script without `lib\` | builds, banner says `Manifest : off`, no warnings, nothing written |

### `test_07_container.bat` — Container target (MOCKED docker)

`--target container`: option validation (`--target bogus`, `--commit` without the container
target), the dry-run plan and mount list, `C2W_TARGET` as the default, a build that must call
`docker run -d --name ... --entrypoint sleep -v ...`, `docker exec -u root` for bootstraps and
`-u USER` for poststraps and never wsl, an existing container (refused, `--force` replaces), `--commit`
(`ENTRYPOINT []` reset), run and commit failures, and `systemd-enable` / `podman-machine` skipping
themselves.

### `test_08_recipe.bat` — Recipes (--dry-run, NO MOCKS)

`--recipes` lists recipes from `--private` folders; `--recipe NAME` applies `user=`, `bootstraps=`,
`poststraps=`, names the build after the file, and ignores `commit=` for a WSL build; command line
`-n` / `-u` override it; `--target container` (or `target=container` in the recipe) builds a
container and then `commit=` applies; with `C2W_PRIVATE_DIRS=a;b` the recipe in `b` wins; a `.conf`
path works; a missing recipe, a recipe without `image=` and a missing path fail with a message; the
`rebuild-wsl.bat` wrapper lists with no arguments and forwards a recipe plus overrides; the built-in
`recipes\default.conf` is listed and builds, and an overlay's `default.conf` replaces it.

### `tests/sh/` — container2x.sh (macOS / Linux)

```bash
tests/sh/run.sh            # mock suite: 108 checks, every engine, no engine installed needed
tests/sh/run.sh --real     # mock suite, then tests/sh/real.sh
bash tests/sh/real.sh podman   # real builds for one engine only
```

`run.sh` puts `tests/sh/mock-engine` on PATH as `docker`, `podman` and `container`; it logs every
call. It covers arguments, rendering (expanded `%C2W_*%`, untouched undefined `%NAME%` and `%%`,
dropped comments), overlay strap lookup, the run/exec/commit command lines per engine (Apple: `list
--all --quiet`, `--arch`, no `--hostname`, `delete --force`, and commit as stop, export, start, build, with a build
failure reported), existing containers, failures, the manifest (read back with `lib/c2w-manifest`),
the ssh folder mode check, and recipes (`--recipe`, `--recipes`, overrides, last overlay wins, the
recorded recipe, the `rebuild-container` wrapper). Run it under bash 3.2 as well, since that is what macOS ships:

```cmd
podman run --rm -v C:\code\docker2wsl:/src:ro docker.io/library/bash:3.2 bash -c "cp -r /src /w && cd /w && bash tests/sh/run.sh"
```

`real.sh` builds `c2x-real-<engine>` from `ubuntu:24.04` with `-b sudo -b devtools -b k8s-tools
-p uv -p devtools-shell -p devtools-overlay -p ssh-keys`, a throwaway overlay (git repo, shell file,
test key pair) and `--commit`, then checks inside: the user and passwordless sudo, kubectl and helm,
devtools installed and the overlay linked, `~/.ssh` 700 with the key 600, the ssh config header
naming its source, `c2w-manifest` reporting 7 of 7 straps ok, the committed image starting as the
user, a second build without `--force` refusing, and `--force` rebuilding. Containers, images and
scratch files (`tests/sh/.real-tmp`, gitignored) are removed afterwards, also on failure.

An engine that cannot run prints `SKIP <engine>: <reason>` and does not fail the run:

| engine | runs when |
|---|---|
| apple | macOS, the `container` CLI installed, and `container system status` answers |
| podman | `podman info` answers (local or remote) |
| docker | `docker info` answers and `docker` is not podman-docker |

### macOS / Apple container

On a Mac (Apple silicon, macOS 26 recommended), after `git pull`:

```bash
container system start          # once per boot, if it is not running
cd docker2wsl && tests/sh/run.sh --real
```

Expect the mock suite to pass and `real: apple`, all checks PASS, with `arm64 userland` among
them. Last verified 2026-10-22 on macOS 26.6 (Apple silicon) with Apple's container CLI 1.1.0
(13/13) and Docker 29.7 (12/12). Over ssh, macOS starts with a minimal PATH; put Homebrew first:
`PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tests/sh/run.sh --real`.

`--commit` on Apple stops the container, exports it, starts it again and builds the image; a failure
in any of those steps fails the build with the step's last log lines. A failed build prints the last
lines of its log under the FAIL line; for more, rerun one engine with
`bash -x tests/sh/real.sh apple`.

## Mock Details

### `tests\mocks\docker.bat`

Simulates `docker image inspect`, `docker pull`, `docker create`, `docker export`, `docker rm`, and for the container target `docker container inspect`, `run`, `exec`, `commit` and `--version`. Behavior is controlled by environment variables:

| Variable | Default | Effect |
|----------|---------|--------|
| `C2W_MOCK_IMAGE_EXISTS` | `0` | `1` = `docker image inspect` succeeds |
| `C2W_MOCK_INSPECT_FILE` | (unset) | file whose content `docker image inspect` prints (canned JSON for the manifest tests) |
| `C2W_MOCK_PULL_FAIL` | `0` | `1` = `docker pull` returns error |
| `C2W_MOCK_CREATE_FAIL` | `0` | `1` = `docker create` returns error |
| `C2W_MOCK_EXPORT_FAIL` | `0` | `1` = `docker export` returns error |
| `C2W_MOCK_CONTAINER_ID` | `mock-container-abc123` | ID echoed by `docker create` |
| `C2W_MOCK_LOG` | (unset) | Path to log file recording all mock calls |
| `C2W_MOCK_CT_EXISTS` | `0` | `1` = `docker container inspect` finds the container |
| `C2W_MOCK_RUN_FAIL` | `0` | `1` = `docker run` returns error |
| `C2W_MOCK_EXEC_FAIL` | `0` | `1` = `docker exec` returns error |
| `C2W_MOCK_COMMIT_FAIL` | `0` | `1` = `docker commit` returns error |

On `docker export`, the mock creates an empty file at the output path (simulating a tar).

### `tests\mocks\wsl.bat`

Simulates `wsl --import`, `wsl --terminate`, `wsl -d ... -- <cmd>`, and `wsl --list`.

| Variable | Default | Effect |
|----------|---------|--------|
| `C2W_MOCK_WSL_IMPORT_FAIL` | `0` | `1` = `wsl --import` returns error |
| `C2W_MOCK_WSL_BASH_FAIL` | `0` | `1` = `wsl -d <name> ... -- <cmd>` returns error |
| `C2W_MOCK_WSL_DISTRO_EXISTS` | (unset) | Name to report as existing in `wsl --list --quiet` |
| `C2W_MOCK_LOG` | (unset) | Path to log file recording all mock calls |

## Test Runner Features

### Safety: Collision Detection

Before running, the runner checks `wsl --list` for any distro names starting with `c2wt` (the test prefix). If found, it refuses to run unless `--force` is passed, which unregisters the colliding distros first.

### Cleanup

After all tests complete, the runner:
1. Unregisters any WSL distros matching `c2wt*`
2. Removes storage directories under the storage root (`C2W_LOCATION`, else `%SystemDrive%\wsl-storage`) matching the test ID
3. Deletes the temporary directory (`C2W_TMPDIR`)

### HTML Reports

`--html report.html` re-runs the test suite via `cmd /c`, captures raw ANSI output, and converts escape codes to styled HTML spans via PowerShell. The result is a self-contained HTML file with a dark background and colored text.

## Assertion Library (`tests\helpers.bat`)

Called as `call "%HELPERS%" <assertion> <args...>`:

| Assertion | Arguments | Passes when |
|-----------|-----------|-------------|
| `assert_equal` | `actual` `expected` `desc` | Values match |
| `assert_not_equal` | `actual` `expected` `desc` | Values differ |
| `assert_not_empty` | `value` `desc` | Value is non-empty |
| `assert_empty` | `value` `desc` | Value is empty |
| `assert_exit_zero` | `code` `desc` | Exit code is `0` |
| `assert_exit_nonzero` | `code` `desc` | Exit code is not `0` |
| `assert_file_exists` | `path` `desc` | File/dir exists |
| `assert_file_not_exists` | `path` `desc` | File/dir does not exist |
| `assert_output_contains` | `file` `needle` `desc` | File contains string |
| `assert_output_not_contains` | `file` `needle` `desc` | File does not contain string |

Each assertion increments the global `C2W_PASS` or `C2W_FAIL` counter.
