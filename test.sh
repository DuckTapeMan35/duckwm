#!/usr/bin/env bash
# Run a duckwm build in Xephyr with two side-by-side monitors, without
# touching the duckwm you're running in.
#
#   ./xephyr-test.sh [path/to/duckwm] [extra duckwm args...]
#
# quack against it (from another terminal):
#   XDG_RUNTIME_DIR=/tmp/duckwm-test quack get_outputs
set -euo pipefail

BIN=${1:-./zig-out/bin/duckwm}
shift || true
DPY=:2
W=960 # each monitor's width
H=600
RUNTIME=/tmp/duckwm-test
LOG=$RUNTIME/duckwm.log

[[ -x $BIN ]] || {
  echo "no duckwm at $BIN (build with: zig build)"
  exit 1
}
mkdir -p "$RUNTIME"
chmod 700 "$RUNTIME"

pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
}
trap cleanup EXIT INT TERM

# -noreset: otherwise the server resets whenever its last client leaves,
# dropping the monitors set below.
Xephyr "$DPY" -screen "$((2 * W))x$H" -ac -br -noreset 2>/dev/null &
pids+=($!)

for _ in $(seq 50); do
  DISPLAY=$DPY xrandr >/dev/null 2>&1 && break
  sleep 0.1
done
DISPLAY=$DPY xrandr >/dev/null 2>&1 || {
  echo "Xephyr didn't come up on $DPY"
  exit 1
}

# Two monitors on the one Xephyr screen (sizes in mm are only for DPI).
DISPLAY=$DPY xrandr --setmonitor left "$W/254x$H/159+0+0" default
DISPLAY=$DPY xrandr --setmonitor right "$W/254x$H/159+$W+0" none
echo "monitors:"
DISPLAY=$DPY xrandr --listmonitors

# Apps started inside must use X, not the river session around Xephyr.
export DISPLAY=$DPY
unset WAYLAND_DISPLAY
export GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb SDL_VIDEODRIVER=x11 XDG_SESSION_TYPE=x11
export XDG_RUNTIME_DIR=$RUNTIME

echo "duckwm log: $LOG"
"$BIN" "$@" >"$LOG" 2>&1 &
pids+=($!)
sleep 1

# Something to look at on each monitor.
term=$(command -v kitty || command -v xterm || true)
if [[ -n $term ]]; then
  "$term" >/dev/null 2>&1 &
  sleep 2
  quack focus_output right >/dev/null 2>&1 || true
  sleep 0.5
  "$term" >/dev/null 2>&1 &
fi

echo "running; Ctrl+C here (or close Xephyr) to stop"
echo "  XDG_RUNTIME_DIR=$RUNTIME quack get_outputs"
wait "${pids[0]}"
