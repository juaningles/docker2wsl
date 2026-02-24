# container2wsl

Create a WSL distribution from any Docker image, in one command.

## Requirements

- Windows 10/11 with [WSL 2](https://learn.microsoft.com/en-us/windows/wsl/install) enabled
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker CLI) running
- Run from an **elevated** (Administrator) Command Prompt

## Quick Start

```cmd
container2wsl.bat ubuntu:22.04
```

This will:

1. Pull the image (if not already local)
2. Export a root filesystem tarball via `docker create` + `docker export`
3. Import it into WSL with `wsl --import`
4. Create a default user (`wsluser`) and configure `/etc/wsl.conf`
5. Clean up temporary containers and tar files

When finished, start your new distro:

```cmd
wsl -d ubuntu-22.04
```

## Usage

```
container2wsl.bat <image> [options]

Options:
  --name,     -n <name>   WSL distro name (default: derived from image)
  --user,     -u <user>   Default user    (default: wsluser)
  --location, -l <path>   WSL storage dir (default: C:\wsl-storage)
  --bootstrap, -b <file>  Run commands from file after setup (repeatable)
  --force,    -f          Overwrite existing WSL distro with same name
  --dry-run               Parse and print config, do not execute
  --help,     -h          Show help
```

## Examples

```cmd
:: Use defaults — name derived from image, user = wsluser
container2wsl.bat alpine:3.19

:: Custom distro name and user
container2wsl.bat ubuntu:22.04 --name my-dev --user alice

:: Custom storage location
container2wsl.bat debian:bookworm --location D:\wsl-distros

:: Run bootstrap commands after setup (multiple files supported)
container2wsl.bat ubuntu:22.04 --bootstrap packages.sh --bootstrap config.sh

:: Overwrite an existing distro
container2wsl.bat ubuntu:22.04 --name my-dev --force

:: Preview what would happen without executing
container2wsl.bat fedora:39 --dry-run
```

## Bootstrap Files

Bootstrap files let you automate post-install setup by running commands inside the new WSL distro. Each line in the file is executed as root, in order. Execution stops on the first command that fails.

- Use `--bootstrap` / `-b` to specify a file (repeatable for multiple files)
- Lines starting with `#` are treated as comments and skipped
- Empty lines are skipped
- Multiple `--bootstrap` flags are processed in the order given
- Use `--dry-run` to preview which commands would run without executing

```cmd
:: Single bootstrap file
container2wsl.bat ubuntu:22.04 --bootstrap setup.sh

:: Multiple files run in sequence
container2wsl.bat ubuntu:22.04 --bootstrap packages.sh --bootstrap config.sh
```

## Bootstrap Variables

Bootstrap files support `%VAR%` expansion. The following built-in variables are available, along with any standard environment variables:

| Variable | Value |
|----------|-------|
| `%C2W_NAME%` | WSL distro name |
| `%C2W_USER%` | Default Linux user |
| `%C2W_IMAGE%` | Docker image name |
| `%C2W_LOCATION%` | WSL storage root path |

Example bootstrap file:

```sh
# setup.sh
useradd -m -s /bin/bash %C2W_USER%
echo "Welcome to %C2W_NAME%" > /etc/motd
```

## Testing

The test suite uses mock `docker` and `wsl` commands so it can run without Docker or real WSL imports.

```cmd
:: Run all tests
tests\run_tests.bat

:: Run a specific test file
tests\run_tests.bat test_01

:: Generate an HTML report
tests\run_tests.bat --html report.html
```

Test distro names are randomized (`c2wt<random>-*`) to avoid collisions. If leftover test distros exist from a previous run, the runner will refuse to start unless `--force` is passed:

```cmd
tests\run_tests.bat --force
```

## License

MIT
