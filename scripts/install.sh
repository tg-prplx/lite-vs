#!/bin/sh
set -eu

REPOSITORY=${LITE_VS_REPOSITORY:-https://github.com/tg-prplx/lite-vs}
BRANCH=${LITE_VS_BRANCH:-main}
USER_DIR=${LITE_USERDIR:-"$HOME/.config/lite-xl"}
SKIP_DEPENDENCIES=${LITE_VS_SKIP_DEPENDENCIES:-0}

FILES='colors/lite-vs-dark.lua
plugins/lite_vs_bootstrap.lua
plugins/lite_vs_layout.lua
plugins/lite_vs_workbench.lua
plugins/lite_vs_workbench_full.lua
plugins/language_python_lite_vs.lua'
DEPENDENCIES='font_symbols_nerdfont_mono_regular navigate nerdicons plugin_manager scm tab_switcher terminal json'

download() {
  url=$1
  target=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$target"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$target"
  else
    echo 'curl or wget is required.' >&2
    exit 1
  fi
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lite-vs.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
STAGING_ROOT="$TMP_ROOT/source"
mkdir -p "$STAGING_ROOT"

SCRIPT_DIR=''
case $0 in
  */*) SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true) ;;
esac
LOCAL_ROOT=''
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../plugins/lite_vs_layout.lua" ]; then
  LOCAL_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
fi

if [ -n "$LOCAL_ROOT" ]; then
  echo "Installing from $LOCAL_ROOT"
  for relative in $FILES; do
    mkdir -p "$STAGING_ROOT/$(dirname "$relative")"
    cp "$LOCAL_ROOT/$relative" "$STAGING_ROOT/$relative"
  done
else
  owner_repo=${REPOSITORY#https://github.com/}
  owner_repo=${owner_repo%.git}
  if [ "$owner_repo" = "$REPOSITORY" ] || [ "$(printf '%s' "$owner_repo" | awk -F/ '{print NF}')" -ne 2 ]; then
    echo "Repository must be a GitHub HTTPS URL: $REPOSITORY" >&2
    exit 1
  fi
  raw_base="https://raw.githubusercontent.com/$owner_repo/$BRANCH"
  echo "Downloading $REPOSITORY ($BRANCH)..."
  for relative in $FILES; do
    mkdir -p "$STAGING_ROOT/$(dirname "$relative")"
    download "$raw_base/$relative" "$STAGING_ROOT/$relative"
    [ -s "$STAGING_ROOT/$relative" ] || { echo "Missing file: $relative" >&2; exit 1; }
  done
fi

if [ "$SKIP_DEPENDENCIES" != 1 ]; then
  LPM=${LPM_BIN:-}
  if [ -z "$LPM" ] && command -v lpm >/dev/null 2>&1; then LPM=$(command -v lpm); fi
  if [ -z "$LPM" ] && [ -d "$USER_DIR/plugins/plugin_manager" ]; then
    LPM=$(find "$USER_DIR/plugins/plugin_manager" -maxdepth 1 -type f -name 'lpm.*' -perm -u+x 2>/dev/null | head -n 1 || true)
  fi
  if [ -z "$LPM" ]; then
    case $(uname -m) in
      x86_64|amd64) arch=x86_64 ;;
      arm64|aarch64) arch=aarch64 ;;
      *) echo "Unsupported LPM architecture: $(uname -m)" >&2; exit 1 ;;
    esac
    case $(uname -s) in
      Linux) os=linux ;;
      Darwin) os=darwin ;;
      *) echo "Unsupported LPM platform: $(uname -s)" >&2; exit 1 ;;
    esac
    LPM="$TMP_ROOT/lpm"
    echo 'Downloading the official Lite XL Plugin Manager...'
    download "https://github.com/lite-xl/lite-xl-plugin-manager/releases/download/latest/lpm.$arch-$os" "$LPM"
    chmod +x "$LPM"
  fi
  echo 'Installing cross-platform dependencies through LPM...'
  # shellcheck disable=SC2086
  "$LPM" install $DEPENDENCIES "--userdir=$USER_DIR" --mod-version=3 --assume-yes --no-color
fi

timestamp=$(date '+%Y%m%d-%H%M%S')
backup_root="$USER_DIR/lite-vs-backups/$timestamp"
has_backup=0
for relative in $FILES; do
  target="$USER_DIR/$relative"
  if [ -f "$target" ]; then
    mkdir -p "$backup_root/$(dirname "$relative")"
    cp "$target" "$backup_root/$relative"
    has_backup=1
  fi
  mkdir -p "$(dirname "$target")"
  cp "$STAGING_ROOT/$relative" "$target"
done

printf '{\n  "repository": "%s",\n  "branch": "%s",\n  "backup": "%s"\n}\n' \
  "$REPOSITORY" "$BRANCH" "$backup_root" > "$USER_DIR/lite-vs-install.json"

echo
echo 'lite-vs installed successfully. Restart Lite XL to apply it.'
if [ "$has_backup" -eq 1 ]; then echo "Previous files were backed up to $backup_root"; fi
