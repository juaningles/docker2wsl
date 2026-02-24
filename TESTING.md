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

## Mock Details

### `tests\mocks\docker.bat`

Simulates `docker image inspect`, `docker pull`, `docker create`, `docker export`, and `docker rm`. Behavior is controlled by environment variables:

| Variable | Default | Effect |
|----------|---------|--------|
| `C2W_MOCK_IMAGE_EXISTS` | `0` | `1` = `docker image inspect` succeeds |
| `C2W_MOCK_PULL_FAIL` | `0` | `1` = `docker pull` returns error |
| `C2W_MOCK_CREATE_FAIL` | `0` | `1` = `docker create` returns error |
| `C2W_MOCK_EXPORT_FAIL` | `0` | `1` = `docker export` returns error |
| `C2W_MOCK_CONTAINER_ID` | `mock-container-abc123` | ID echoed by `docker create` |
| `C2W_MOCK_LOG` | (unset) | Path to log file recording all mock calls |

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
2. Removes storage directories under `C:\wsl-storage` matching the test ID
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
