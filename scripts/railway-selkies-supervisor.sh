#!/usr/bin/env bash
set -euo pipefail
umask 077

public_port="${PORT:-8080}"
internal_health_port="${EGO_INTERNAL_HEALTH_PORT:-8082}"
display="${DISPLAY:-:99}"
viewer_width="${EGO_VIEWER_WIDTH:-1920}"
viewer_height="${EGO_VIEWER_HEIGHT:-1080}"
bootstrap_script="${EGO_TOKEN_BOOTSTRAP_SCRIPT:-/usr/local/libexec/ego-selkies-token-bootstrap.mjs}"

validate_port() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 || value > 65535 )); then
    echo "ego Selkies supervisor: $name must be an integer between 1 and 65535" >&2
    exit 64
  fi
}

validate_dimension() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 640 || value > 8192 )); then
    echo "ego Selkies supervisor: $name must be an integer between 640 and 8192" >&2
    exit 64
  fi
}

validate_port PORT "$public_port"
validate_port EGO_INTERNAL_HEALTH_PORT "$internal_health_port"
if [[ "$public_port" == "$internal_health_port" ]]; then
  echo "ego Selkies supervisor: public and internal health ports must differ" >&2
  exit 64
fi
if [[ ! "$display" =~ ^:[0-9]+$ ]]; then
  echo "ego Selkies supervisor: DISPLAY must look like :99" >&2
  exit 64
fi
validate_dimension EGO_VIEWER_WIDTH "$viewer_width"
validate_dimension EGO_VIEWER_HEIGHT "$viewer_height"

export DISPLAY="$display"
export SELKIES_ADDR="0.0.0.0"
export SELKIES_PORT="$public_port"
export SELKIES_MODE="websockets"
export SELKIES_ENABLE_DUAL_MODE="false"
export SELKIES_ENABLE_HTTPS="false"
export SELKIES_ENABLE_BASIC_AUTH="false"
export SELKIES_ENABLE_RESIZE="false"
export SELKIES_IS_MANUAL_RESOLUTION_MODE="true"
export SELKIES_MANUAL_WIDTH="$viewer_width"
export SELKIES_MANUAL_HEIGHT="$viewer_height"
export SELKIES_USE_CPU="true"
export SELKIES_COMMAND_ENABLED="false"
export SELKIES_FILE_TRANSFERS="none"
export SELKIES_MICROPHONE_ENABLED="false"
export SELKIES_GAMEPAD_ENABLED="false"
export SELKIES_ENABLE_SHARING="false"
export SELKIES_ENABLE_COLLAB="false"
export SELKIES_ENABLE_SHARED="false"
export EGO_HEALTH_HOST="127.0.0.1"
export PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:?}/pulse}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH}/native}"

node "$bootstrap_script" --check >/dev/null

if [[ "${1:-}" == "--check" ]]; then
  printf '{"ok":true,"port":%s,"healthPort":%s,"healthHost":"%s","display":"%s","resolution":"%sx%s","cpuEncoding":true}\n' \
    "$public_port" "$internal_health_port" "$EGO_HEALTH_HOST" "$display" "$viewer_width" "$viewer_height"
  exit 0
fi

if (( $# == 0 )); then
  echo "ego Selkies supervisor: missing Ego host command" >&2
  exit 64
fi

for executable in Xvfb openbox pulseaudio curl node selkies; do
  if ! command -v "$executable" >/dev/null 2>&1; then
    echo "ego Selkies supervisor: required executable not found: $executable" >&2
    exit 69
  fi
done

runtime_dir="${EGO_RUNTIME_DIR:?}"
mkdir -p "$runtime_dir/openbox" "$PULSE_RUNTIME_PATH"
chmod 0700 "$runtime_dir/openbox" "$PULSE_RUNTIME_PATH"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$runtime_dir/openbox}"

pids=()
shutting_down=0

remember_pid() {
  local pid="$1"
  if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 )); then
    pids+=("$pid")
  fi
}

signal_children() {
  local signal_name="$1"
  local pid
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "-$signal_name" "$pid" 2>/dev/null || true
    fi
  done
}

shutdown() {
  if (( shutting_down == 1 )); then
    return
  fi
  shutting_down=1
  trap - INT TERM
  signal_children TERM

  local deadline=$((SECONDS + 12))
  local alive=1
  local pid
  while (( alive == 1 && SECONDS < deadline )); do
    alive=0
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        alive=1
        break
      fi
    done
    if (( alive == 1 )); then
      sleep 0.2
    fi
  done
  signal_children KILL
  wait 2>/dev/null || true
}

trap 'shutdown; exit 0' INT TERM

Xvfb "$DISPLAY" \
  -screen 0 "${viewer_width}x${viewer_height}x24" \
  +extension COMPOSITE +extension DAMAGE +extension GLX +extension RANDR \
  +extension RENDER +extension MIT-SHM +extension XFIXES +extension XTEST \
  +render -nolisten tcp -ac -noreset -shmem \
  >"$runtime_dir/xvfb.log" 2>&1 &
xvfb_pid=$!
remember_pid "$xvfb_pid"

x_socket="/tmp/.X11-unix/X${DISPLAY#:}"
for _ in {1..100}; do
  [[ -S "$x_socket" ]] && break
  if ! kill -0 "$xvfb_pid" 2>/dev/null; then
    echo "ego Selkies supervisor: Xvfb exited before its socket became ready" >&2
    shutdown
    exit 70
  fi
  sleep 0.1
done
if [[ ! -S "$x_socket" ]]; then
  echo "ego Selkies supervisor: Xvfb socket did not become ready" >&2
  shutdown
  exit 70
fi

pulseaudio --daemonize=no --exit-idle-time=-1 --disallow-exit \
  --load="module-null-sink sink_name=output sink_properties=device.description=EgoOutput" \
  >"$runtime_dir/pulseaudio.log" 2>&1 &
pulse_pid=$!
remember_pid "$pulse_pid"

openbox --sm-disable >"$runtime_dir/openbox.log" 2>&1 &
openbox_pid=$!
remember_pid "$openbox_pid"

PORT="$internal_health_port" "$@" &
host_pid=$!
remember_pid "$host_pid"

for _ in {1..120}; do
  if curl --fail --silent --show-error "http://127.0.0.1:${internal_health_port}/readyz" >/dev/null; then
    break
  fi
  if ! kill -0 "$host_pid" 2>/dev/null; then
    echo "ego Selkies supervisor: Ego host exited before readiness" >&2
    shutdown
    exit 70
  fi
  sleep 0.25
done
if ! curl --fail --silent --show-error "http://127.0.0.1:${internal_health_port}/readyz" >/dev/null; then
  echo "ego Selkies supervisor: Ego host readiness timed out" >&2
  shutdown
  exit 70
fi

selkies > >(tee "$runtime_dir/selkies.log") 2>&1 &
selkies_pid=$!
remember_pid "$selkies_pid"

if ! node "$bootstrap_script"; then
  echo "ego Selkies supervisor: token bootstrap failed" >&2
  shutdown
  exit 70
fi

set +e
wait -n "$xvfb_pid" "$pulse_pid" "$openbox_pid" "$host_pid" "$selkies_pid"
exit_status=$?
set -e
echo "ego Selkies supervisor: a critical process exited (status=$exit_status)" >&2
shutdown
if (( exit_status == 0 )); then
  exit 1
fi
exit "$exit_status"
