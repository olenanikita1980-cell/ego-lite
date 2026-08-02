#!/usr/bin/env bash
set -euo pipefail
umask 077

volume_root="${RAILWAY_VOLUME_MOUNT_PATH:-/data}"
runtime_dir="${EGO_RUNTIME_DIR:-/run/ego-lite}"
data_dir="${EGO_DATA_DIR:-${volume_root%/}/ego-lite}"
profile_dir="${EGO_USER_DATA_DIR:-${data_dir%/}/profile}"
visual_mode="${EGO_VISUAL_MODE:-headless}"

for directory in "$volume_root" "$runtime_dir" "$data_dir" "$profile_dir"; do
  if [[ -z "$directory" || "$directory" != /* ]]; then
    echo "ego railway entrypoint: all storage paths must be non-empty absolute paths" >&2
    exit 64
  fi
done

if [[ "$volume_root" == "/" ]]; then
  echo "ego railway entrypoint: refusing to use / as the volume root" >&2
  exit 64
fi

case "${runtime_dir%/}/" in
  "${volume_root%/}/"*)
    echo "ego railway entrypoint: EGO_RUNTIME_DIR must not live on the persistent volume" >&2
    exit 64
    ;;
esac

case "$visual_mode" in
  headless|selkies) ;;
  *)
    echo "ego railway entrypoint: EGO_VISUAL_MODE must be headless or selkies" >&2
    exit 64
    ;;
esac

install -d -m 0700 -o ego -g ego \
  "$data_dir" \
  "$profile_dir" \
  "$runtime_dir" \
  "$runtime_dir/xdg"

export EGO_DATA_DIR="$data_dir"
export EGO_USER_DATA_DIR="$profile_dir"
export EGO_RUNTIME_DIR="$runtime_dir"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$runtime_dir/xdg}"

command=("$@")
if [[ "$visual_mode" == "selkies" ]]; then
  export EGO_HEADLESS=0
  command=(/usr/local/bin/ego-railway-selkies-supervisor "$@")
fi

if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu ego:ego tini -- "${command[@]}"
fi
exec tini -- "${command[@]}"
