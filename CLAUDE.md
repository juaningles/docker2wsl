# CLAUDE.md - container2wsl

## Project Overview

Windows batch script that creates a WSL distribution from any Docker image.
Single file (`container2wsl.bat`), no dependencies beyond Docker and WSL.

## Architecture

The main script runs 4 sequential steps via `call :subroutine` labels:
1. `docker_ensure_image` - check local / pull from registry
2. `docker_export_image` - `docker create` + `docker export` to tar
3. `wsl_import` - `wsl --import` with error detection
4. `wsl_configure_user` - create user, write `/etc/wsl.conf`, restart distro

## Critical WSL Quirks

These are hard-won lessons. Do not "simplify" these workarounds:

- **`wsl -d` rejects quoted names**: `wsl -d "name"` silently fails with "no distribution found". Always use `wsl -d name` (unquoted). `--import` and `--terminate` handle quotes fine.
- **WSL exits 0 on failure**: Both `wsl --import` and `wsl -d ... -- cmd` return exit code 0 even when they fail. Must capture output to a file and check for UTF-16 LE error text via `findstr /c:"E r r o r"`.
- **`bash -c` quoting is broken**: `wsl -d NAME -- bash -c "cmd 'arg'"` includes the trailing `"` in the argument. Use direct commands instead: `wsl -d NAME -u root -- useradd -m -s /bin/bash USERNAME`.
- **Windows line endings corrupt wsl.conf**: CMD `echo` writes `\r\n`. After copying a file into WSL, run `sed -i "s/\r//" /etc/wsl.conf` or the `[user]` section won't parse.
- **Distro readiness after import**: The distro is registered immediately after `wsl --import` but may take a moment to accept commands. The readiness check must capture output and look for error text (not just check exit code, since exit code is always 0).

## CMD Batch Scripting Gotchas

- **`)` in echo inside if/else blocks** closes the block early. Use delayed expansion variables (`!var!`) for any content that might contain `)`, or restructure to avoid if/else blocks entirely (use `goto` or flat `if` chains).
- **Calling a `.bat` without `call`** transfers control permanently. Always `call script.bat`.
- **`goto :label 2>nul || (fallback)`** does not work reliably. Use explicit `if` chains.
- **`>` in echo** is parsed as redirect. Don't use `>` as a display character in batch echo statements.
- **Unicode characters** (`---`, checkmarks, bullets) don't survive CMD's codepage. Use ASCII only for display.

## Testing

```
tests\run_tests.bat                        # run all (51 assertions)
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
- Assertion helpers use `setlocal enabledelayedexpansion` + flat `if/goto` to avoid block-parsing bugs
- ANSI colors in output: green PASS, red FAIL, yellow test headers, cyan file names

## File Layout

```
container2wsl.bat            # main script (the only file users need)
tests/
  run_tests.bat              # test runner with --html, --force, pre-flight checks
  helpers.bat                # assertion library (10 assertion types)
  test_01_args.bat           # argument parsing tests (--dry-run, no mocks)
  test_02_docker.bat         # docker step tests (mocked)
  test_03_wsl.bat            # wsl import + user config tests (mocked)
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
| `C2W_MOCK_CONTAINER_ID` | mock-container-abc123 | ID returned by docker create |
| `C2W_MOCK_LOG` | (unset) | path to log file for mock calls |
