#!/usr/bin/env bash
# container2x.sh - build a running container from an image and run the docker2wsl straps in it.
# The macOS / Linux counterpart of "container2wsl.bat --target container", for three engines:
#   docker, podman, and Apple's container CLI (macOS, Apple silicon: github.com/apple/container).
# Same straps, private overlays, recipes and manifest as container2wsl.bat; docs/RUNNERS.md has
# the shared contract. Written for bash 3.2 (the macOS /bin/bash): no associative arrays.
#
#   container2x.sh IMAGE [options]
#     -n, --name NAME        container name (default: derived from IMAGE)
#     -u, --user USER        user to create (default: wsluser)
#     -b, --bootstrap FILE   strap run as root (repeatable; bare names resolve as below)
#     -p, --poststrap FILE   strap run as the user (repeatable)
#         --private DIR      private overlay folder (repeatable; default C2W_PRIVATE_DIRS, a : list,
#                            else sibling folders of this script with a .devtools-overlay marker)
#         --engine E         docker | podman | apple (default C2W_ENGINE, else apple on macOS when
#                            the container CLI exists, else podman, else docker)
#         --arch A           image architecture (amd64, arm64), passed to the engine
#         --commit REF       also save the result as image REF
#     -l, --location DIR     where the manifest copy goes (default C2W_LOCATION, else
#                            ~/.local/share/container2x); DIR/NAME/container2wsl-manifest.jsonl
#     -f, --force            replace an existing container of that name
#         --dry-run          show the plan and the rendered straps, change nothing
#         --recipe NAME      defaults from recipes/NAME.conf here or in a private overlay (or a path);
#                            the other arguments still override them. --recipes lists them.
#     -h, --help
# Bare strap names resolve from bootstraps/ or poststraps/ next to this script, then from each
# private folder's straps/, bootstraps/ and poststraps/. Host folders the straps read are
# bind-mounted at the same path, so every path variable means the same inside the container.
# When the engine runs on another machine (podman remote, a Docker context), those paths must
# exist there too: keep the repos and C2X_RUN_ROOT on a path both sides share (e.g. /mnt/c).
set -euo pipefail
VERSION=1.0.0
SELF="$0"; while [ -L "$SELF" ]; do L=$(readlink "$SELF"); case "$L" in /*) SELF="$L" ;; *) SELF="$(dirname "$SELF")/$L" ;; esac; done
SCRIPT_DIR=$(cd "$(dirname "$SELF")" && pwd)
ARGV="$*"; CWD=$(pwd)

say()  { printf '%s\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
warn() { printf '      [WARN] %s\n' "$*"; }
usage() { sed -n '2,28p' "$SELF" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- recipes
# --recipe expands a recipe (key=value: image name user bootstraps poststraps engine arch commit
# extra; location and target are for container2wsl.bat) into arguments placed BEFORE the others,
# then runs this script again, so command line arguments win ("last one wins").
RECIPE="${_C2X_FROM_RECIPE:-}"; unset _C2X_FROM_RECIPE
_rc= _rc_set=0 _rc_list=0; _rest=(); _rpriv=(); _a=("$@"); _i=0
while [ $_i -lt ${#_a[@]} ]; do
  case "${_a[$_i]}" in
    --recipes) _rc_list=1 ;;
    --recipe) _rc_set=1; _i=$((_i+1)); _rc="${_a[$_i]:-}" ;;
    --private) _rest+=(--private); _i=$((_i+1)); _rest+=("${_a[$_i]:-}")
               [ -d "${_a[$_i]:-/nonexistent}" ] && _rpriv+=("$(cd "${_a[$_i]}" && pwd -P)") ;;
    *) _rest+=("${_a[$_i]}") ;;
  esac
  _i=$((_i+1))
done
recipe_dirs() {   # one folder per line, a later match wins: this repo (built-in samples such as
  local d         # default), then --private given, else C2W_PRIVATE_DIRS, else marked siblings
  printf '%s\n' "$SCRIPT_DIR"
  if [ ${#_rpriv[@]} -gt 0 ]; then printf '%s\n' "${_rpriv[@]}"
  elif [ -n "${C2W_PRIVATE_DIRS:-}" ]; then printf '%s\n' "$C2W_PRIVATE_DIRS" | tr ':' '\n'
  else for d in "$SCRIPT_DIR"/../*/; do [ -f "$d.devtools-overlay" ] && (cd "$d" && pwd -P); done; fi
}
recipe_list() {
  echo "Recipes (name, overlay, image):"
  local d f n=0
  while IFS= read -r d; do
    for f in "$d"/recipes/*.conf; do
      [ -f "$f" ] || continue; n=$((n+1))
      printf '  %-12s (%s)  %s\n' "$(basename "$f" .conf)" "$(basename "$d")" "$(sed -n 's/^image=//p' "$f" | tr -d '\r' | tail -1)"
    done
  done <<EOF
$(recipe_dirs)
EOF
  [ $n -gt 0 ] || echo "  none: no recipes/*.conf in the private overlay folders (--private, C2W_PRIVATE_DIRS or a sibling .devtools-overlay marker)"
}
if [ "$_rc_list" = 1 ]; then recipe_list; exit 0; fi
if [ "$_rc_set" = 1 ]; then
  [ -n "$_rc" ] || { echo "[ERROR] --recipe needs a recipe name or a .conf path." >&2; recipe_list >&2; exit 2; }
  _rf=
  case "$_rc" in
    */*|*.conf) [ -f "$_rc" ] || { echo "[ERROR] Recipe file not found: $_rc" >&2; exit 2; }; _rf="$(cd "$(dirname "$_rc")" && pwd -P)/$(basename "$_rc")" ;;
    *) while IFS= read -r _d; do [ -n "$_d" ] && [ -f "$_d/recipes/$_rc.conf" ] && _rf="$_d/recipes/$_rc.conf"; done <<EOF
$(recipe_dirs)
EOF
       ;;
  esac
  [ -n "$_rf" ] || { echo "[ERROR] No recipe \"$_rc\" in docker2wsl/recipes or the recipes folder of any private overlay." >&2; recipe_list >&2; exit 2; }
  _get() { sed -n "s/^$1=//p" "$_rf" | tr -d '\r' | tail -1; }
  _v=$(_get image); [ -n "$_v" ] || { echo "[ERROR] Recipe $_rf has no image= line." >&2; exit 2; }
  _ra=("$_v"); _v=$(_get name); _ra+=(-n "${_v:-$(basename "$_rf" .conf)}")
  _v=$(_get user); [ -n "$_v" ] && _ra+=(-u "$_v")
  for _x in $(_get bootstraps); do _ra+=(-b "$_x"); done
  for _x in $(_get poststraps); do _ra+=(-p "$_x"); done
  _v=$(_get engine); [ -n "$_v" ] && _ra+=(--engine "$_v")
  _v=$(_get arch); [ -n "$_v" ] && _ra+=(--arch "$_v")
  _v=$(_get commit); [ -n "$_v" ] && _ra+=(--commit "$_v")
  _v=$(_get extra); if [ -n "$_v" ]; then read -r -a _ex <<< "$_v"; _ra+=("${_ex[@]}"); fi
  echo "container2x: recipe $_rf"
  echo "container2x: ${_ra[*]} ${_rest[*]+${_rest[*]}}"
  export _C2X_FROM_RECIPE="$_rf"
  exec bash "$SELF" "${_ra[@]}" ${_rest[@]+"${_rest[@]}"}
fi

# ---------------------------------------------------------------- arguments
IMAGE= NAME= USER_NAME= ENGINE="${C2W_ENGINE:-}" ARCH= COMMIT= FORCE=0 DRY=0
LOCATION="${C2W_LOCATION:-$HOME/.local/share/container2x}"
BOOT=() POST=() BOOT_REQ=() POST_REQ=() PRIV_ARG=()
need() { [ $# -ge 2 ] && [ -n "$2" ] || die "Missing value for option: $1"; }
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY=1 ;;
    -f|--force) FORCE=1 ;;
    -n|--name) need "$@"; NAME="$2"; shift ;;
    -u|--user) need "$@"; USER_NAME="$2"; shift ;;
    -l|--location) need "$@"; LOCATION="$2"; shift ;;
    -b|--bootstrap) need "$@"; BOOT_REQ[${#BOOT_REQ[@]}]="$2"; shift ;;
    -p|--poststrap) need "$@"; POST_REQ[${#POST_REQ[@]}]="$2"; shift ;;
    --private) need "$@"; [ -d "$2" ] || die "--private folder not found: $2"; PRIV_ARG[${#PRIV_ARG[@]}]="$(cd "$2" && pwd)"; shift ;;
    --engine) need "$@"; ENGINE="$2"; shift ;;
    --arch) need "$@"; ARCH="$2"; shift ;;
    --commit) need "$@"; COMMIT="$2"; shift ;;
    -*) die "Unknown option: $1 (try --help)" ;;
    *) [ -z "$IMAGE" ] || die "Unexpected argument: $1"; IMAGE="$1" ;;
  esac
  shift
done
[ -n "$IMAGE" ] || { usage; die "An image is required."; }
USER_NAME="${USER_NAME:-wsluser}"
if [ -z "$NAME" ]; then NAME=$(printf '%s' "$IMAGE" | tr ':/\\' '---'); fi

# ---------------------------------------------------------------- engine
if [ -z "$ENGINE" ]; then
  if [ "$(uname -s)" = Darwin ] && command -v container >/dev/null 2>&1; then ENGINE=apple
  elif command -v podman >/dev/null 2>&1; then ENGINE=podman
  elif command -v docker >/dev/null 2>&1; then ENGINE=docker
  else die "No container engine found (container, podman or docker). Use --engine."; fi
fi
case "$ENGINE" in
  docker|podman) E="$ENGINE" ;;
  apple) E=container ;;
  *) die "--engine must be docker, podman or apple, not: $ENGINE" ;;
esac
if [ "$DRY" = 0 ]; then command -v "$E" >/dev/null 2>&1 || die "$E not found on PATH (engine $ENGINE)."; fi

# One function per verb; docker and podman share the CLI, Apple maps a few names.
e_image_exists() { "$E" image inspect "$1" >/dev/null 2>&1; }
e_pull() { if [ "$ENGINE" = apple ]; then "$E" image pull "$1"; else "$E" pull ${ARCH:+--platform "linux/$ARCH"} "$1"; fi; }
e_exists() {
  if [ "$ENGINE" = apple ]; then "$E" list --all --quiet 2>/dev/null | grep -qx "$1"
  else "$E" container inspect "$1" >/dev/null 2>&1; fi
}
e_rm() { if [ "$ENGINE" = apple ]; then "$E" delete --force "$1"; else "$E" rm -f "$1"; fi; }
e_run_cmd() {   # prints nothing; fills RUN_CMD with the full run command
  RUN_CMD=("$E" run -d --name "$NAME")
  if [ "$ENGINE" = apple ]; then RUN_CMD+=(${ARCH:+--arch "$ARCH"})
  else RUN_CMD+=(--hostname "$NAME" ${ARCH:+--platform "linux/$ARCH"}); fi
  RUN_CMD+=(--entrypoint sleep)
  local m; for m in "${MOUNTS[@]}"; do RUN_CMD+=(-v "$m:$m"); done
  RUN_CMD+=("$IMAGE" infinity)
}
e_exec() { local u="$1"; shift; "$E" exec -u "$u" "$NAME" "$@"; }
e_commit() {   # $1 = login shell of the user
  if [ "$ENGINE" != apple ]; then
    "$E" commit --change 'ENTRYPOINT []' --change "CMD $1 -l" --change "USER $USER_NAME" \
      --change "WORKDIR /home/$USER_NAME" "$NAME" "$COMMIT" >/dev/null
    return
  fi
  # Apple's commit takes no --change: commit, then a three-line build sets entrypoint, user, workdir
  local tmp="localhost/c2x-commit:$NAME-$$" d
  "$E" commit "$NAME" "$tmp" >/dev/null
  d=$(mktemp -d)
  printf 'FROM %s\nENTRYPOINT []\nCMD ["%s", "-l"]\nUSER %s\nWORKDIR /home/%s\n' "$tmp" "$1" "$USER_NAME" "$USER_NAME" > "$d/Dockerfile"
  if "$E" build -t "$COMMIT" -f "$d/Dockerfile" "$d" >/dev/null 2>&1; then
    "$E" image delete --force "$tmp" >/dev/null 2>&1 || true
  else
    "$E" image tag "$tmp" "$COMMIT" >/dev/null 2>&1 || "$E" commit "$NAME" "$COMMIT" >/dev/null
    "$E" image delete --force "$tmp" >/dev/null 2>&1 || true
    warn "container build could not reset the entrypoint: $COMMIT still starts 'sleep infinity'. Run it detached and exec in."
  fi
  rm -rf "$d"
}

# ---------------------------------------------------------------- private folders and straps
PRIV=()
add_priv() {
  local d x
  d=$(cd "$1" 2>/dev/null && pwd) || return 0
  for x in ${PRIV[@]+"${PRIV[@]}"}; do [ "$x" = "$d" ] && return 0; done
  PRIV[${#PRIV[@]}]="$d"
}
if [ ${#PRIV_ARG[@]} -gt 0 ]; then for d in "${PRIV_ARG[@]}"; do add_priv "$d"; done
elif [ -n "${C2W_PRIVATE_DIRS:-}" ]; then IFS=: read -r -a _pd <<< "$C2W_PRIVATE_DIRS"; for d in "${_pd[@]}"; do [ -d "$d" ] && add_priv "$d"; done
else for d in "$SCRIPT_DIR"/../*/; do [ -f "$d.devtools-overlay" ] && add_priv "$d"; done; fi

resolve() {   # $1 = strap as given, $2 = bootstraps|poststraps; prints the file or fails
  local s="$1" k="$2" d
  if [ -f "$s" ]; then (cd "$(dirname "$s")" && printf '%s/%s\n' "$(pwd)" "$(basename "$s")"); return; fi
  for d in "$SCRIPT_DIR/$k/$s" "$SCRIPT_DIR/$s"; do [ -f "$d" ] && { printf '%s\n' "$d"; return; }; done
  for d in ${PRIV[@]+"${PRIV[@]}"}; do
    [ -f "$d/straps/$s" ] && { printf '%s\n' "$d/straps/$s"; return; }
    [ -f "$d/$k/$s" ] && { printf '%s\n' "$d/$k/$s"; return; }
  done
  return 1
}
for r in ${BOOT_REQ[@]+"${BOOT_REQ[@]}"}; do f=$(resolve "$r" bootstraps) || die "Bootstrap not found: $r"; BOOT[${#BOOT[@]}]="$f"; done
for r in ${POST_REQ[@]+"${POST_REQ[@]}"}; do f=$(resolve "$r" poststraps) || die "Poststrap not found: $r"; POST[${#POST[@]}]="$f"; done

# ---------------------------------------------------------------- variables the straps see
join() { local IFS="$1"; shift; printf '%s' "$*"; }
export C2W_NAME="$NAME" C2W_USER="$USER_NAME" C2W_IMAGE="$IMAGE" C2W_LOCATION="$LOCATION"
export C2W_TARGET=container C2W_ENGINE="$ENGINE"
export C2W_SCRIPT_DIR="$SCRIPT_DIR/" C2W_SCRIPT_DIR_LX="$SCRIPT_DIR" C2W_USERPROFILE_LX="$HOME"
export C2W_PRIVATE_DIRS="$(join : ${PRIV[@]+"${PRIV[@]}"})"
export C2W_PRIVATE_DIRS_LX="$C2W_PRIVATE_DIRS"

# ---------------------------------------------------------------- mounts
MOUNTS=()
add_mount() {
  local d x
  d=$(cd "$1" 2>/dev/null && pwd) || return 0
  for x in ${MOUNTS[@]+"${MOUNTS[@]}"}; do [ "$x" = "$d" ] && return 0; done
  MOUNTS[${#MOUNTS[@]}]="$d"
}
add_mount "$SCRIPT_DIR"
[ -d "$SCRIPT_DIR/../devtools" ] && add_mount "$SCRIPT_DIR/../devtools"
for d in ${PRIV[@]+"${PRIV[@]}"}; do add_mount "$d"; done
[ -n "${C2W_SSH_SOURCE:-}" ] && [ -d "${C2W_SSH_SOURCE}" ] && add_mount "$C2W_SSH_SOURCE"

# ---------------------------------------------------------------- rendering (docs/RUNNERS.md)
# Drop blank and #-comment lines, trim trailing blanks, expand %NAME% only for a defined NAME
# (anything else, %% included, stays as it is), prepend set -e. Same as container2wsl.bat.
render() {
  { printf 'set -e\n'
    tr -d '\r' < "$1" | awk '
      { sub(/[ \t]+$/, "") }
      $0 == "" || /^#/ { next }
      { out = ""; s = $0
        while (match(s, /%[^%]+%/)) {
          nm = substr(s, RSTART + 1, RLENGTH - 2)
          if (nm in ENVIRON) { out = out substr(s, 1, RSTART - 1) ENVIRON[nm]; s = substr(s, RSTART + RLENGTH) }
          else { out = out substr(s, 1, RSTART); s = substr(s, RSTART + 1) }
        }
        print out s }'
  } > "$2"
}
strap_dir_vars() { export C2W_STRAP_DIR="$(dirname "$1")/" C2W_STRAP_DIR_LX="$(dirname "$1")"; }

# ---------------------------------------------------------------- ssh-keys host-side checks
# ssh-keys checks a /mnt (Windows) source with powershell.exe, which a container cannot start;
# other sources get mode checks inside. Run the Windows check here when we are on WSL.
ssh_host_check() {
  local want=0 r; for r in ${POST_REQ[@]+"${POST_REQ[@]}"}; do [ "$(basename "$r")" = ssh-keys ] && want=1; done
  [ "$want" = 1 ] || return 0
  [ "${C2W_SSH_ACL_CHECK:-}" = off ] && return 0
  local srcs=() d
  if [ -n "${C2W_SSH_SOURCE:-}" ]; then srcs=("$C2W_SSH_SOURCE"); else for d in ${PRIV[@]+"${PRIV[@]}"}; do [ -d "$d/ssh" ] && srcs+=("$d/ssh"); done; fi
  local ps; ps=$(command -v powershell.exe 2>/dev/null || true)
  local win=0
  for d in ${srcs[@]+"${srcs[@]}"}; do
    case "$d" in
      /mnt/*)
        [ -n "$ps" ] || die "ssh-keys: $d is a Windows folder but powershell.exe is not reachable for the ACL check. Set C2W_SSH_ACL_CHECK=off to skip it."
        "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$SCRIPT_DIR/lib/ssh-source-check.ps1")" -Path "$(wslpath -w "$d")" | tr -d '\r' \
          || die "ssh-keys: $d failed the Windows ACL check above. Refusing."
        win=1 ;;
      *)
        local m; m=$(stat -c %a "$d" 2>/dev/null || stat -f %Lp "$d")
        case "$m" in *00) ;; *) die "ssh-keys: $d is mode $m; needs 700. Refusing (chmod 700 $d)." ;; esac ;;
    esac
  done
  [ "$win" = 1 ] && export C2W_SSH_ACL_CHECK=host
  return 0
}

# ---------------------------------------------------------------- manifest (JSON Lines, no jq)
js() { local s="$1"; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/\\t}; s=${s//$'\r'/}; s=${s//$'\n'/\\n}; printf '"%s"' "$s"; }
jsn() { if [ -n "$1" ]; then js "$1"; else printf null; fi; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
epoch() { date -u +%s; }
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
gitj() {   # git info of the repo holding $1, as JSON or null
  local d="$1"; [ -d "$d" ] || d=$(dirname "$d")
  local c; c=$(git -C "$d" rev-parse --short HEAD 2>/dev/null) || { printf null; return; }
  local dirty=false; [ -n "$(git -C "$d" status --porcelain -- "$1" 2>/dev/null)" ] && dirty=true
  local rem; rem=$(git -C "$d" remote get-url origin 2>/dev/null || true)
  printf '{"commit":%s,"dirty":%s,"remote":%s}' "$(js "$c")" "$dirty" "$(jsn "$rem")"
}
strap_list() { local first=1 i=0; local -a req; local -a path
  if [ "$1" = boot ]; then req=(${BOOT_REQ[@]+"${BOOT_REQ[@]}"}); path=(${BOOT[@]+"${BOOT[@]}"}); else req=(${POST_REQ[@]+"${POST_REQ[@]}"}); path=(${POST[@]+"${POST[@]}"}); fi
  printf '['; while [ $i -lt ${#req[@]} ]; do [ $first = 1 ] || printf ','; first=0; printf '{"requested":%s,"path":%s}' "$(js "${req[$i]}")" "$(js "${path[$i]}")"; i=$((i+1)); done; printf ']'; }
M_MASTER= M_TMP=
m_write() {   # $1 = one JSON record
  [ -n "$M_MASTER" ] || return 0
  printf '%s\n' "$1" >> "$M_MASTER" && cp "$M_MASTER" "$M_TMP" \
    && e_exec root install -D -m 644 "$M_TMP" /etc/container2wsl/manifest.jsonl >/dev/null 2>&1 \
    || warn "Manifest: could not record. The build itself is unaffected."
}
m_create() {
  local ver os p first=1 priv='['
  ver=$("$E" --version 2>/dev/null | head -1 || true)
  os=$(e_exec root sh -c '. /etc/os-release 2>/dev/null && printf %s "$PRETTY_NAME"' 2>/dev/null || true)
  for p in ${PRIV[@]+"${PRIV[@]}"}; do [ $first = 1 ] || priv="$priv,"; first=0; priv="$priv{\"path\":$(js "$p"),\"git\":$(gitj "$p")}"; done; priv="$priv]"
  m_write "{\"schema\":1,\"event\":\"create\",\"time\":\"$(now)\",\"build_started\":\"$BUILD_TIME\",\
\"command\":{\"line\":$(js "container2x.sh $ARGV"),\"cwd\":$(js "$CWD"),\"recipe\":$(jsn "$RECIPE")},\
\"image\":{\"requested\":$(js "$IMAGE"),\"id\":null,\"digests\":[],\"tags\":[],\"pulled\":$PULLED,\"arch\":$(jsn "$ARCH")},\
\"distro\":{\"name\":$(js "$NAME"),\"user\":$(js "$USER_NAME"),\"install_path\":$(js "$LOCATION/$NAME"),\"os\":$(jsn "$os"),\
\"replaced_existing\":$([ "$FORCE" = 1 ] && echo true || echo false),\"target\":\"container\",\"engine\":\"$ENGINE\",\"commit\":$(jsn "$COMMIT")},\
\"straps\":{\"bootstrap\":$(strap_list boot),\"poststrap\":$(strap_list post)},\"private\":$priv,\
\"tool\":{\"name\":\"container2x\",\"version\":\"$VERSION\",\"path\":$(js "$SCRIPT_DIR"),\"git\":$(gitj "$SCRIPT_DIR")},\
\"host\":{\"computer\":$(js "$(hostname 2>/dev/null || uname -n)"),\"windows_user\":$(js "${USER:-$(id -un)}"),\"windows\":null,\
\"os\":$(js "$(uname -sr)"),\"wsl\":null,\"engine\":$(jsn "$ver")}}"
}

# ---------------------------------------------------------------- plan
say ""
say " container2x v$VERSION"
say " ----------------------------------------"
say " Image    : $IMAGE${ARCH:+ ($ARCH)}"
say " Container: $NAME ($ENGINE, via $E)"
say " User     : $USER_NAME"
[ -n "$COMMIT" ] && say " Commit   : $COMMIT"
say " Records  : $LOCATION/$NAME (manifest copy)"
for f in ${BOOT[@]+"${BOOT[@]}"}; do say " Bootstrap: $f"; done
for f in ${POST[@]+"${POST[@]}"}; do say " Poststrap: $f"; done
if [ ${#PRIV[@]} -gt 0 ]; then for d in "${PRIV[@]}"; do say " Private  : $d"; done; else say " Private  : none (no --private, C2W_PRIVATE_DIRS or sibling .devtools-overlay marker)"; fi
for d in "${MOUNTS[@]}"; do say " Mount    : $d"; done
[ "$FORCE" = 1 ] && say " Force    : yes (remove an existing container of that name)"
[ "$DRY" = 1 ] && say " Mode     : DRY RUN (no changes will be made)"
say " ----------------------------------------"
say ""

STEPS=3; [ ${#BOOT[@]} -gt 0 ] && STEPS=$((STEPS+1)); [ ${#POST[@]} -gt 0 ] && STEPS=$((STEPS+1)); [ -n "$COMMIT" ] && STEPS=$((STEPS+1))

if [ "$DRY" = 1 ]; then
  d=$(mktemp -d); MOUNTS+=("<run folder>")
  e_run_cmd; say "[DRY-RUN] ${RUN_CMD[*]}"
  for f in ${BOOT[@]+"${BOOT[@]}"}; do strap_dir_vars "$f"; render "$f" "$d/s.sh"; say "[DRY-RUN] Bootstrap commands from: $f (as root)"; sed -n '2,$s/^/  /p' "$d/s.sh"; done
  for f in ${POST[@]+"${POST[@]}"}; do strap_dir_vars "$f"; render "$f" "$d/s.sh"; say "[DRY-RUN] Poststrap commands from: $f (as $USER_NAME)"; sed -n '2,$s/^/  /p' "$d/s.sh"; done
  rm -rf "$d"; say "[DRY-RUN] All steps skipped."; exit 0
fi

# ---------------------------------------------------------------- build
RUN_ROOT="${C2X_RUN_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/container2x}"
mkdir -p "$RUN_ROOT"; RUN_DIR=$(cd "$(mktemp -d "$RUN_ROOT/run.XXXXXX")" && pwd)
trap 'rm -rf "$RUN_DIR"' EXIT
add_mount "$RUN_DIR"
BUILD_TIME=$(now); BUILD_T0=$(epoch); PULLED=false

say "[1/$STEPS] Checking for image: $IMAGE"
if e_image_exists "$IMAGE"; then say "      Found locally."
else say "      Not found locally. Pulling..."; e_pull "$IMAGE" || die "pull failed for: $IMAGE"; PULLED=true; fi

say "[2/$STEPS] Starting container '$NAME'..."
if e_exists "$NAME"; then
  [ "$FORCE" = 1 ] || die "Container '$NAME' already exists. Use --force to replace it."
  say "      Removing existing container '$NAME'..."; e_rm "$NAME" >/dev/null 2>&1 || true
fi
e_run_cmd; say "      ${RUN_CMD[*]}"
"${RUN_CMD[@]}" >/dev/null || die "$E run failed for $IMAGE. The image needs a sleep command (coreutils or busybox)."

say "[3/$STEPS] Creating user '$USER_NAME'..."
e_exec root useradd -m -s /bin/bash "$USER_NAME" >/dev/null 2>&1 || true
e_exec root usermod -aG sudo "$USER_NAME" >/dev/null 2>&1 || true
e_exec root id "$USER_NAME" >/dev/null 2>&1 || die "Could not create user '$USER_NAME' in the container (useradd missing?)."
say "      User '$USER_NAME' ready."
ssh_host_check

mkdir -p "$LOCATION/$NAME"
M_MASTER="$LOCATION/$NAME/container2wsl-manifest.jsonl"; M_TMP="$RUN_DIR/manifest.jsonl"
[ -f "$M_MASTER" ] && mv -f "$M_MASTER" "$LOCATION/$NAME/container2wsl-manifest.prev.jsonl"
m_create
if [ -f "$SCRIPT_DIR/lib/c2w-manifest" ]; then
  tr -d '\r' < "$SCRIPT_DIR/lib/c2w-manifest" > "$RUN_DIR/c2w-manifest"
  e_exec root install -D -m 755 "$RUN_DIR/c2w-manifest" /usr/local/bin/c2w-manifest >/dev/null 2>&1 || true
fi

SEQ=0 FAILED=
run_straps() {   # $1 = boot|post
  local kind as list step i=0 f n out rc t0 copy cnt
  if [ "$1" = boot ]; then kind=bootstrap; as=root; list=(${BOOT[@]+"${BOOT[@]}"}); local reqs=(${BOOT_REQ[@]+"${BOOT_REQ[@]}"})
  else kind=poststrap; as="$USER_NAME"; list=(${POST[@]+"${POST[@]}"}); local reqs=(${POST_REQ[@]+"${POST_REQ[@]}"}); fi
  step=$2
  for f in ${list[@]+"${list[@]}"}; do
    i=$((i+1)); SEQ=$((SEQ+1)); n=$(printf '%02d' "$SEQ")
    say "[$step/$STEPS] Running $kind ${i}/${#list[@]}: $f (as $as)"
    strap_dir_vars "$f"; out="$RUN_DIR/$n-$kind-$(basename "$f").sh"; render "$f" "$out"
    cnt=$(($(wc -l < "$out") - 1))
    t0=$(epoch); rc=0
    e_exec "$as" bash "$out" || rc=$?
    copy="/etc/container2wsl/straps/$n-$kind-$(basename "$f").sh"
    e_exec root install -D -m 600 "$out" "$copy" >/dev/null 2>&1 || true
    m_write "{\"event\":\"strap\",\"time\":\"$(now)\",\"kind\":\"$kind\",\"index\":$i,\"seq\":$SEQ,\"requested\":$(js "${reqs[$((i-1))]}"),\
\"path\":$(js "$f"),\"sha256\":$(js "$(sha "$f")"),\"git\":$(gitj "$f"),\"rendered_sha256\":$(js "$(sha "$out")"),\
\"rendered_copy\":$(js "$copy"),\"run_as\":$(js "$as"),\"commands\":$cnt,\"duration_s\":$(( $(epoch) - t0 )),\"result\":\"$([ $rc = 0 ] && echo ok || echo failed)\"}"
    if [ "$rc" != 0 ]; then FAILED="$kind $i: ${reqs[$((i-1))]}"; return 1; fi
    say "      Complete ($cnt commands executed)."
  done
}
complete_rec() { m_write "{\"event\":\"complete\",\"time\":\"$(now)\",\"result\":\"$1\",\"failed\":$(jsn "$FAILED"),\"duration_s\":$(( $(epoch) - BUILD_T0 ))}"; }
STEP=4
if [ ${#BOOT[@]} -gt 0 ]; then run_straps boot $STEP || { complete_rec failed; die "Bootstrap failed: $FAILED"; }; STEP=$((STEP+1)); fi
if [ ${#POST[@]} -gt 0 ]; then run_straps post $STEP || { complete_rec failed; die "Poststrap failed: $FAILED"; }; STEP=$((STEP+1)); fi

SH=$(e_exec root getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f7 || true); SH="${SH:-/bin/bash}"
if [ -n "$COMMIT" ]; then
  say "[$STEP/$STEPS] Committing container to image $COMMIT..."
  e_commit "$SH" || { FAILED="commit $COMMIT"; complete_rec failed; die "$E commit failed."; }
  say "      Committed. Bind mounts are not part of the image."
fi
complete_rec ok
say ""
say "[SUCCESS] Container created and running."
say "          Name   : $NAME"
say "          Enter  : $E exec -it -u $USER_NAME -w /home/$USER_NAME $NAME $SH -l"
[ -n "$COMMIT" ] && say "          Image  : $COMMIT  ($E run -it --rm $COMMIT)"
if [ "$ENGINE" = apple ]; then say "          Remove : $E delete --force $NAME"; else say "          Remove : $E rm -f $NAME"; fi
say "          Record : c2w-manifest inside the container  (copy: $M_MASTER)"
say ""
