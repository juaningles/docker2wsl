# container2wsl

Create a WSL distribution from any Docker image, in one command. The same straps can also build a
running container instead: `--target container` on Windows, or `container2x.sh` on macOS and Linux
with docker, podman or Apple's `container` (see [Container targets](#container-targets)).

## Requirements

For a WSL distro (`container2wsl.bat`):

- Windows 10/11 with [WSL 2](https://learn.microsoft.com/en-us/windows/wsl/install) enabled
- A container engine to fetch the image: Docker (Desktop or CLI), or podman with a `docker` shim such as
  devtools' `docker.bat` (its machine must be running)
- Run from an **elevated** (Administrator) Command Prompt or PowerShell

For a container instead (`--target container` on Windows, `container2x.sh` on macOS / Linux): just the
engine, docker, podman or Apple's `container`, plus bash 3.2 or later on macOS / Linux.

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
  --location, -l <path>   WSL storage dir (default: %SystemDrive%\wsl-storage)
  --bootstrap, -b <file>  Run commands from file as root after setup (repeatable)
  --poststrap, -p <file>  Run commands from file as user after setup (repeatable)
  --private <dir>         Private overlay folder (repeatable; see Private overlays)
  --force,    -f          Overwrite existing WSL distro with same name
  --target <wsl|container>  WSL distro (default, or C2W_TARGET) or a running container
  --commit <image:tag>    Container target: also save the result as an image
  --recipe <name|file>    Defaults from a recipe (see Recipes); the other arguments override them
  --recipes               List the recipes in the private overlays
  --dry-run               Parse and print config, do not execute
  --help,     -h          Show help
```

The default storage root is `%SystemDrive%\wsl-storage`; set `C2W_LOCATION` to change it for every build.

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
| `%C2W_SCRIPT_DIR%` / `%C2W_SCRIPT_DIR_LX%` | container2wsl's own folder, as a Windows path (trailing `\`) and as `/mnt/<drive>/...` |
| `%C2W_STRAP_DIR%` / `%C2W_STRAP_DIR_LX%` | the folder of the strap being run, so a strap in a private repo reaches its repo with `..` |
| `%C2W_USERPROFILE_LX%` | your Windows profile as `/mnt/<drive>/Users/<name>` |
| `%C2W_PRIVATE_DIRS%` / `%C2W_PRIVATE_DIRS_LX%` | the private overlay folders, `;` separated Windows paths and `:` separated `/mnt` paths |

Nothing in container2wsl assumes `C:` or a fixed folder: clone it anywhere, on any drive, and use these variables instead of absolute paths in your own straps.

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
| `systemd-enable` | Enables systemd in `/etc/wsl.conf`, and writes `/etc/binfmt.d/WSLInterop.conf` so the distro's systemd does not clear Windows interop for every distro (microsoft/WSL#8843) |
| `zsh` | Installs zsh, curl, git and Oh My Zsh for the created user |
| `devtools` | Installs git, curl, wget, build-essential, jq, unzip/zip, openssh-client and other dev tools |
| `homebrew` | Installs Homebrew (Linuxbrew), pre-creates the Linuxbrew prefix with the right ownership, and adds `brew shellenv` to `~/.profile` |
| `k8s-tools` | Installs kubectl (latest stable), kubelogin, Helm 4 and yq into `/usr/local/bin` (amd64/arm64, apt or apk); skips any already on PATH. Also `nslookup`/`dig` (`dnsutils` or `bind-tools`) |
| `data-tools` | Installs jq, miller (`mlr`), make, unzip and curl (apt or apk) |
| `azure-cli` | Installs the Azure CLI (`az`) from Microsoft's apt repository (Debian/Ubuntu only); skipped if a Linux `az` is present. The Windows `az` that WSL's PATH exposes does not count: it would write credentials to the Windows kubeconfig |
| `motd` | Shows the build summary (`c2w-manifest --short`) at every zsh login, motd style, through `/etc/zsh/zlogin`. Run after `zsh`. Silence per user with `touch ~/.hushlogin` |

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
| `devtools-shell` | Clones [devtools](https://github.com/juaningles/devtools) to `~/devtools` and runs its `install.sh` (bash and zsh setup, aliases, `bin/` scripts). Source: `C2W_DEVTOOLS_REPO` if set, else the `devtools` clone next to container2wsl, else GitHub |
| `devtools-overlay` | Clones every private overlay folder (see below) to `~/<name>` and links it into devtools with `install.sh --overlay`. Run after `devtools-shell` |
| `keychain` | Installs [keychain](https://github.com/danielrobbins/keychain) (ssh-agent manager, formerly funtoo/keychain): the apt/apk package (with `openssh-client`) when `-b sudo` is present, else the upstream 2.8.5 script into `~/.local/bin`, which still needs `ssh-agent` from `openssh-client` (bootstrap `devtools` installs it). The agent starts empty, so login never asks for a passphrase; keys load on first use (see `ssh-keys`). To preload some, list their names in `~/.keychain_default_keys`; devtools starts the agent at shell start, and without devtools an `eval` line goes into `~/.profile` |
| `ssh-keys` | Copies keys, `config` and `known_hosts` into `~/.ssh` (700/600/644, CRs stripped) from each private overlay's `ssh\` folder in order, or from `C2W_SSH_SOURCE` (e.g. `%USERPROFILE%\.ssh`) when set. **Refuses** a Windows source whose ACL grants access beyond the owner, SYSTEM and Administrators (`lib\ssh-source-check.ps1`, the same rule Windows OpenSSH applies), or a Linux source that is group/other accessible or has a key not 600/400. Configs are concatenated in order, under a header with `AddKeysToAgent yes`: no key is loaded at login, each one joins the agent the first time ssh uses it (a passphrase key prompts once then). Owner-only Windows files appear as another uid's under `/mnt`, so the copy reads them as root: pair with `-b sudo` |
| `brew-python` | `brew install python` and a `python` symlink. Prefer `uv` |
| `claude` | Installs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with the native installer (no npm) into `~/.local/bin`. `C2W_CLAUDE_VERSION=stable`, `latest` or a version picks the release |
| `databricks-ug` | Installs [Databricks Unity Gateway](https://github.com/databricks/unity-gateway) (`ug`, formerly `ucode`) with `uv tool install git+https://github.com/databricks/unity-gateway`, falling back to the legacy `databricks/ucode` URL if that fails, plus the Databricks CLI it signs in with; replaces an old `ucode` install. Needs `-p uv` and `-b sudo`. Then run `ug configure` (or `ug claude`) once in the distro |
| `podman-machine` | Uses the Windows podman machine from the distro: installs the podman client and `podman-docker` (`docker` runs podman), copies the machine's ssh key to `~/.ssh/podman-machine`, adds the machine's ssh connection as the default and sets `remote = true` in `~/.config/containers/containers.conf`, so `podman` and `docker` work in every shell and script. `C2W_PODMAN_CONNECTION=podman-machine-default-root` picks the rootful one. When WSLg's `XDG_RUNTIME_DIR` belongs to another uid (the image already had a uid-1000 user), it adds `/usr/local/bin/podman` and `docker` wrappers that use a runtime dir the user owns. Needs Windows podman, `-b sudo`, and the machine running to use it. Bind mounts resolve inside the machine: `/mnt/c/...` works, the distro's `/home` does not |

`powerlevel10k` expects `zsh` to already be installed. Pair it with the built-in `zsh` bootstrap when creating a fresh distro. `uv` needs curl and `devtools-shell` needs git (`-b devtools` provides both).

A full developer distro:

```cmd
container2wsl.bat ubuntu:24.04 -n dev -u alice ^
  -b sudo -b systemd-enable -b devtools -b zsh -b motd -b k8s-tools -b data-tools -b azure-cli ^
  -p powerlevel10k -p uv -p devtools-shell
```

### Private overlays

A private overlay is a folder (usually a private git repo) with your own aliases, scripts, straps and ssh material, laid out as devtools' `docs/OVERLAY.md` describes. container2wsl finds them three ways, first match wins:

1. `--private DIR` on the command line (repeatable);
2. `C2W_PRIVATE_DIRS`, a `;`-separated list;
3. every sibling folder of the container2wsl clone that contains an empty `.devtools-overlay` marker file, in name order. Clone your overlays (say `devtools-private` and `devtools-work`) next to `docker2wsl` and nothing needs configuring.

What they get you: `-p devtools-overlay` installs each one into the distro; a bare strap name also resolves from each folder's `straps\`, `bootstraps\` and `poststraps\`; the `ssh-keys` poststrap reads their `ssh\` folders; and the build manifest records their paths and git commits. Straps kept anywhere else are still passed by path: `-p D:\somewhere\my-strap`.

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

Inside the distro, `c2w-manifest` prints a readable report. It is installed to `/usr/local/bin` with the manifest and needs only `sh` and `awk`:

```text
$ c2w-manifest --short
container2wsl: zdevnode from juaningles/devnode:noble @sha256:68ee22004a91, built 2026-10-20 14:58 UTC, ok in 25m31s
  straps: sudo systemd-enable zsh homebrew k8s-tools | powerlevel10k uv devtools-shell (8 ok)

$ c2w-manifest            # long: image id and digests, command line, host, one row per strap
$ c2w-manifest -f /mnt/c/wsl-storage/other/container2wsl-manifest.jsonl   # any manifest file
```

Add `-b motd` (after `-b zsh`) to show the short form at every zsh login.

With `jq` installed you can query the raw records:

```bash
cat /etc/container2wsl/manifest.jsonl | jq .                       # everything
jq -r 'select(.event=="create") | .image.digests[]' /etc/container2wsl/manifest.jsonl
jq -r 'select(.event=="strap") | "\(.kind) \(.requested) \(.result) \(.duration_s)s"' /etc/container2wsl/manifest.jsonl
```

A `--force` rebuild keeps the previous Windows copy as `container2wsl-manifest.prev.jsonl`. `--dry-run` writes nothing. Straps you run by hand later (`sudo bash bootstraps/k8s-tools`) are not recorded.

The manifest needs `lib\manifest.ps1` next to `container2wsl.bat`. Without it the script still works on its own; the banner says `Manifest : off` and nothing is recorded. Writing the manifest never fails a build: a problem only prints a `[WARN]`.

## Recipes

A recipe saves a build's options in a file, so `rebuild-wsl zdev` replaces a long command line. Recipes
are `<name>.conf` files in a `recipes/` folder: this repo's own (samples) and each private overlay's,
found in the same overlay folders container2wsl detects for the build (see
[Private overlays](#private-overlays)). This repo ships `recipes/default.conf`, a general dev box from
stock Ubuntu with the public straps only, so `rebuild-wsl default -n mydev -u alice` works on any
machine. Copy a sample into an overlay to change it.

```cmd
container2wsl.bat --recipes                          :: list them (name, overlay, image)
container2wsl.bat --recipe zdev                      :: build from <overlay>\recipes\zdev.conf
container2wsl.bat --recipe zdev -n zdev2 --force     :: anything after it overrides the recipe
container2wsl.bat --recipe zdev --target container   :: the same recipe as a running container
container2wsl.bat --recipe D:\x\dev.conf             :: a recipe file by path
rebuild-wsl zdev --force                             :: shorthand: rebuild-wsl.bat in this folder
```

On macOS / Linux the same recipes work with `container2x.sh --recipe NAME` or `./rebuild-container NAME`.

Format: `key=value` lines, no spaces around `=`, comments on their own line starting with `#`.

| key | meaning |
|---|---|
| `image` | required |
| `name` | distro / container name (default: the file name) |
| `user` | user to create |
| `bootstraps`, `poststraps` | space-separated strap names or paths |
| `location` | container2wsl.bat `-l` |
| `target` | container2wsl.bat: `wsl` or `container` |
| `commit` | image to commit to; used only when the build is a container, so a WSL recipe can carry it |
| `engine`, `arch` | container2x.sh: `docker` / `podman` / `apple`, and the image architecture |
| `extra` | other arguments, passed as written |

The recipe becomes arguments placed before the ones on the command line, so the command line wins.
When two folders have a recipe of the same name, the one searched last wins: this repo's `recipes/`
first, then the overlays in name order (like overlay aliases), so an overlay's `default.conf` replaces
the sample. The build manifest records which recipe was used.

## Container targets

The straps, private overlays, recipes and manifest also build a **running container**, for when a
WSL distro is not what you want (CI, a Mac, a throwaway environment, an image to share).
[docs/RUNNERS.md](docs/RUNNERS.md) is the contract all three runners keep.

**Windows** (docker or podman, e.g. through devtools' `docker.bat` shim):

```cmd
container2wsl.bat ubuntu:24.04 --target container -n dev -u alice ^
  -b sudo -b devtools -b k8s-tools -p uv -p devtools-shell -p devtools-overlay -p ssh-keys ^
  --commit localhost/dev:1
podman exec -it -u alice -w /home/alice dev bash -l
```

**macOS and Linux** (`container2x.sh`, bash 3.2 or later): the same options plus `--engine` and
`--arch`. On a Mac with [Apple's container](https://github.com/apple/container) installed and
started (`container system start`) it is the default engine; otherwise podman, then docker.

```bash
./container2x.sh ubuntu:24.04 -n dev -u alice -b sudo -b devtools -b k8s-tools \
  -p uv -p devtools-shell -p devtools-overlay -p ssh-keys --commit localhost/dev:1
container exec -it -u alice -w /home/alice dev bash -l      # Apple; podman/docker exec likewise
```

How it works: the container starts with `sleep infinity` as its entrypoint, the user is created,
and every strap runs through `<engine> exec`. Host folders the straps read (this repo, the
`devtools` clone next to it, the private overlays, `C2W_SSH_SOURCE`) are bind-mounted at the path
the straps already use. The result keeps running; `--commit` also saves it as an image whose default
command is the user's login shell (bind mounts are not part of the image). `--force` replaces an
existing container of the same name. Straps that only make sense in WSL (`systemd-enable`,
`podman-machine`) skip themselves.

[Recipes](#recipes) work for both: `rebuild-wsl NAME --target container` on Windows, and
`./rebuild-container NAME` on macOS / Linux.

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

`container2x.sh` has its own suite, run from macOS or Linux (WSL works):

```bash
tests/sh/run.sh           # mock engines for docker, podman and Apple container: fast, no engine needed
tests/sh/run.sh --real    # then real builds with every engine that works here; the others print SKIP
```

The real suite is how the Apple engine is verified: run it on a Mac with Apple's container CLI.

## License

MIT
