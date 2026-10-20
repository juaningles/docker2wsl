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
5. Run bootstrap commands as root (if `-b` specified)
6. Run poststrap commands as user (if `-p` specified)
7. Clean up temporary containers and tar files

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
  --bootstrap, -b <file>  Run commands from file as root after setup (repeatable)
  --poststrap, -p <file>  Run commands from file as user after setup (repeatable)
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

:: Use built-in bootstrap files by name (no path needed)
container2wsl.bat ubuntu:22.04 -b sudo -b systemd-enable -b zsh

:: Run poststrap commands as the created user (not root)
container2wsl.bat ubuntu:22.04 -b sudo -p user-config.sh

:: Overwrite an existing distro
container2wsl.bat ubuntu:22.04 --name my-dev --force

:: Preview what would happen without executing
container2wsl.bat fedora:39 --dry-run
```

## Bootstrap Files

Bootstrap files let you automate post-install setup by running commands inside the new WSL distro. Each line in the file is executed as **root**, in order. Execution stops on the first command that fails.

- Use `--bootstrap` / `-b` to specify a file (repeatable for multiple files)
- Lines starting with `#` are treated as comments and skipped
- Empty lines are skipped
- Multiple `--bootstrap` flags are processed in the order given
- Use `--dry-run` to preview which commands would run without executing
- Bare names (e.g. `-b sudo`) auto-resolve to the built-in `bootstraps/` directory

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

## Built-in Bootstraps

The `bootstraps/` directory ships with ready-to-use files. Reference them by name:

```cmd
container2wsl.bat ubuntu:22.04 -b sudo -b systemd-enable -b zsh
```

| Name | What it does |
|------|--------------|
| `sudo` | Installs sudo, grants passwordless sudo to the created user |
| `systemd-enable` | Enables systemd in `/etc/wsl.conf` |
| `zsh` | Installs zsh, curl, git and Oh My Zsh for the created user |
| `devtools` | Installs git, curl, build-essential, jq, and other dev tools |
| `homebrew` | Installs Homebrew (Linuxbrew), pre-creates the Linuxbrew prefix with the right ownership, and adds `brew shellenv` to `~/.profile` |
| `k8s-tools` | Installs kubectl (latest stable), kubelogin, Helm 4 and yq into `/usr/local/bin` (amd64/arm64, apt or apk); skips any already on PATH |
| `data-tools` | Installs jq, miller (`mlr`), make, unzip and curl (apt or apk) |
| `azure-cli` | Installs the Azure CLI (`az`) from Microsoft's apt repository (Debian/Ubuntu only); skipped if present |

The `k8s-tools`, `data-tools` and `azure-cli` files use no `%C2W_*%` variables, so they also work on a distro you already have: `sudo bash bootstraps/k8s-tools`.

## Poststrap Files

Poststrap files work like bootstrap files but run as the **created user** instead of root. This is useful for user-level configuration (dotfiles, shell setup, etc.).

- Use `--poststrap` / `-p` to specify a file (repeatable for multiple files)
- Same syntax as bootstrap: one command per line, `#` comments, `%VAR%` expansion
- Runs after all bootstrap files complete
- Bare names auto-resolve from `poststraps/` directory
- Intended for user-level setup such as shell themes, dotfiles, and editor config

```cmd
:: Install packages as root, then configure user environment
container2wsl.bat ubuntu:22.04 -b sudo -b devtools -p user-setup.sh
```

## Built-in Poststraps

The `poststraps/` directory ships with user-level setup files. Reference them by name:

```cmd
container2wsl.bat ubuntu:22.04 -b zsh -p powerlevel10k
```

| Name | What it does |
|------|--------------|
| `powerlevel10k` | Installs Oh My Zsh if missing, installs Powerlevel10k and zsh plugins, and updates `~/.zshrc` |
| `uv` | Installs [uv](https://docs.astral.sh/uv/) into `~/.local/bin` and a uv-managed CPython with `python`/`python3` shims. Set `C2W_UV_PYTHON=3.12` (on the Windows side) to pick a version |
| `devtools-shell` | Clones [devtools](https://github.com/juaningles/devtools) to `~/devtools` and runs its `install.sh` (bash and zsh setup, aliases, `bin/` scripts). Source: `C2W_DEVTOOLS_REPO` if set, else `C:\code\devtools` if present, else GitHub |
| `brew-python` | `brew install python` and a `python` symlink. Prefer `uv` |
| `claude` | Installs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with the native installer (no npm) into `~/.local/bin`. `C2W_CLAUDE_VERSION=stable`, `latest` or a version picks the release |
| `databricks-ug` | Installs [Databricks Unity Gateway](https://github.com/databricks/unity-gateway) (`ug`, formerly `ucode`) with `uv tool install git+https://github.com/databricks/unity-gateway`, falling back to the legacy `databricks/ucode` URL if that fails, plus the Databricks CLI it signs in with; replaces an old `ucode` install. Needs `-p uv` and `-b sudo`. Then run `ug configure` (or `ug claude`) once in the distro |

`powerlevel10k` expects `zsh` to already be installed. Pair it with the built-in `zsh` bootstrap when creating a fresh distro. `uv` needs curl and `devtools-shell` needs git (`-b devtools` provides both).

A full developer distro:

```cmd
container2wsl.bat ubuntu:24.04 -n dev -u alice ^
  -b sudo -b systemd-enable -b devtools -b zsh -b k8s-tools -b data-tools -b azure-cli ^
  -p powerlevel10k -p uv -p devtools-shell
```

Straps you keep elsewhere (for example in a private repo) are passed by path: `-p C:\code\my-overlay\straps\overlay`.

### Writing strap files

Each strap is joined into one bash script with `set -e`, so multi-line `if`/`case` blocks work. Three things to know:

- Lines starting with `#` and blank lines are dropped before running, including inside heredocs.
- `%NAME%` is replaced with the Windows environment variable when it is defined, and left as literal text when it is not. Test for the literal: `X=%MY_VAR%` then `case $X in *MY_VAR*) X= ;; esac`.
- The command list is echoed through CMD first, which re-parses each line. Never put `>`, `<`, `|` or `&` inside double quotes, and avoid `%*`. A redirect outside quotes, or inside single quotes, is fine.

## Build manifest

Every build records what went into the distro, so you can tell later exactly which image and which strap versions produced it, and rebuild it the same way:

| Where | What |
|---|---|
| `/etc/container2wsl/manifest.jsonl` | the manifest, inside the distro (readable by everyone) |
| `<location>\<name>\container2wsl-manifest.jsonl` | the same file on Windows, next to `ext4.vhdx`; readable without starting the distro |
| `/etc/container2wsl/straps/NN-<kind>-<name>.sh` | the exact script each strap ran, after `%VAR%` expansion (root only, mode 600, because expanded variables can hold secrets) |

It is [JSON Lines](https://jsonlines.org/): one record per line, appended as the build goes:

| `event` | Recorded | Contents |
|---|---|---|
| `create` | once the distro exists | the command line as typed and its working folder; the image as requested, its image ID (`sha256:...`), registry digests (`repo@sha256:...`), tags, OS/arch, build date, size and whether this run pulled it; distro name, user, install path and `/etc/os-release` name; requested straps (as typed and resolved); container2wsl version and git commit; Windows host, build, WSL version and container engine |
| `strap` | after each bootstrap/poststrap, pass or fail | kind, order, name as requested, resolved path, sha256 and git commit (with a dirty flag) of the strap file, sha256 of the rendered script and where it was saved, user it ran as, command count, duration, `ok`/`failed` |
| `complete` | at the end | `ok` or `failed`, the failed step (for example `poststrap 2: uv`), total duration |

```bash
cat /etc/container2wsl/manifest.jsonl | jq .                       # everything
jq -r 'select(.event=="create") | .image.digests[]' /etc/container2wsl/manifest.jsonl
jq -r 'select(.event=="strap") | "\(.kind) \(.requested) \(.result) \(.duration_s)s"' /etc/container2wsl/manifest.jsonl
```

A `--force` rebuild keeps the previous Windows copy as `container2wsl-manifest.prev.jsonl`. `--dry-run` writes nothing. Straps you run by hand later (`sudo bash bootstraps/k8s-tools`) are not recorded.

The manifest needs `lib\manifest.ps1` next to `container2wsl.bat`. Without it the script still works on its own; the banner says `Manifest : off` and nothing is recorded. Writing the manifest never fails a build: a problem only prints a `[WARN]`.

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
