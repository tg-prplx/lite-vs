#!/bin/sh
set -eu

USER_DIR=${LITE_USERDIR:-"$HOME/.config/lite-xl"}
RESTORE=${1:-}
FILES='colors/lite-vs-dark.lua
plugins/lite_vs_bootstrap.lua
plugins/lite_vs_layout.lua
plugins/lite_vs_workbench.lua
plugins/lite_vs_workbench_full.lua
plugins/language_python_lite_vs.lua'

backup_root=''
if [ "$RESTORE" = '--restore-latest' ]; then
  backup_root=$(find "$USER_DIR/lite-vs-backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -n 1 || true)
  [ -n "$backup_root" ] || { echo 'No lite-vs backup was found.' >&2; exit 1; }
fi

for relative in $FILES; do
  target="$USER_DIR/$relative"
  if [ -n "$backup_root" ] && [ -f "$backup_root/$relative" ]; then
    mkdir -p "$(dirname "$target")"
    cp "$backup_root/$relative" "$target"
  elif [ -f "$target" ]; then
    rm -f "$target"
  fi
done
rm -f "$USER_DIR/lite-vs-install.json"

if [ -n "$backup_root" ]; then
  echo "lite-vs removed and the backup from $backup_root restored."
else
  echo 'lite-vs removed. Shared LPM dependencies and backups were kept.'
fi
