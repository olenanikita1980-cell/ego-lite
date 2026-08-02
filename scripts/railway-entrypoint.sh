#!/usr/bin/env bash
set -euo pipefail
umask 077

volume_root="${RAILWAY_VOLUME_MOUNT_PATH:-/data}"
runtime_dir="${EGO_RUNTIME_DIR:-/run/ego-lite}"
data_dir="${EGO_DATA_DIR:-${volume_root%/}/ego-lite}"
profile_dir="${EGO_USER_DATA_DIR:-${data_dir%/}/profile}"
visual_mode="${EGO_VISUAL_MODE:-headless}"

cleanup_chromium_singleton_links() {
  local profile_root="$1"
  local singleton_name
  local singleton_path

  # Validate the complete set before unlinking anything so an unexpected entry
  # cannot leave the singleton set partially modified.
  for singleton_name in SingletonCookie SingletonLock SingletonSocket; do
    singleton_path="${profile_root%/}/${singleton_name}"
    if [[ ! -L "$singleton_path" && -e "$singleton_path" ]]; then
      echo "ego railway entrypoint: refusing to remove non-symlink Chromium ${singleton_name}" >&2
      return 73
    fi
  done

  for singleton_name in SingletonCookie SingletonLock SingletonSocket; do
    singleton_path="${profile_root%/}/${singleton_name}"
    if [[ -L "$singleton_path" ]]; then
      unlink -- "$singleton_path"
      echo "ego railway entrypoint: removed stale Chromium ${singleton_name} symlink" >&2
    fi
  done
}

if [[ "${EGO_RAILWAY_ENTRYPOINT_SOURCE_ONLY:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

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

# Hold an advisory lock for the complete container lifetime. The descriptor is
# inherited across gosu/tini/daemon exec, and the kernel releases it on exit.
profile_owner_lock="${data_dir%/}/profile-owner.lock"
if [[ -L "$profile_owner_lock" || ( -e "$profile_owner_lock" && ! -f "$profile_owner_lock" ) ]]; then
  echo "ego railway entrypoint: profile owner lock must be a regular file" >&2
  exit 73
fi
if [[ ! -e "$profile_owner_lock" ]]; then
  install -m 0600 -o ego -g ego /dev/null "$profile_owner_lock"
fi
if ! command -v flock >/dev/null 2>&1; then
  echo "ego railway entrypoint: required executable not found: flock" >&2
  exit 69
fi
exec {profile_owner_fd}>"$profile_owner_lock"
if ! flock -n "$profile_owner_fd"; then
  echo "ego railway entrypoint: persistent Chromium profile already has a live owner" >&2
  exit 75
fi

# Chromium's Linux singleton links contain the previous container hostname.
# A Railway restart can move the volume to a new host, where Chromium otherwise
# exits with PROFILE_IN_USE even though the previous container is already gone.
# The owner lock plus one-replica/zero-overlap configuration makes entrypoint
# startup the safe ownership boundary for reclaiming only these lock links.
cleanup_chromium_singleton_links "$profile_dir"

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
