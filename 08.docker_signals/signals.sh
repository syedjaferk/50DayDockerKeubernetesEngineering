#!/usr/bin/env bash
# Sending signals to a container, and what happens.
#
# Usage: ./signals.sh build | stop | dockerkill | shellkill | inside | hostkill | inflight | init | all
#
# Ways to deliver a signal to a container:
#   docker stop <c>                 SIGTERM to PID 1, wait (10 s default), then SIGKILL
#   docker stop -t 30 <c>           same, with a 30 s grace period
#   docker kill <c>                 SIGKILL to PID 1 immediately
#   docker kill -s SIGTERM <c>      any signal you name, to PID 1
#   docker exec <c> kill -TERM 1    from INSIDE the container's PID namespace
#   kill -TERM $(docker inspect -f '{{.State.Pid}}' <c>)
#                                   from the HOST shell, using the container's host-side PID
#                                   (Linux host; on Docker Desktop the host PID lives inside a VM)

set -u
EXEC_IMG=demo:exec
SHELL_IMG=demo:shell

build() {
  docker build -f Dockerfile.exec  -t "$EXEC_IMG" .
  docker build -f Dockerfile.shell -t "$SHELL_IMG" .
}

# ---------- helpers ----------
state()   { docker inspect -f '{{.State.Status}}, exit code {{.State.ExitCode}}' "$1"; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1")" = "true" ]; }

# start_c NAME IMAGE PORT [extra docker run args]
start_c() {
  local name=$1 image=$2 port=$3; shift 3
  docker rm -f "$name" >/dev/null 2>&1
  docker run -d --name "$name" -p "$port:8000" "$@" "$image" >/dev/null
  sleep 2
}

# restart a container that exited (keeps the same name and port mapping)
ensure_running() {
  if ! running "$1"; then docker start "$1" >/dev/null; sleep 2; fi
}

# show PID 1 and the process list as the container sees it
show_pids() {
  echo "    PID 1: $(docker exec "$1" cat /proc/1/cmdline | tr '\0' ' ')"
  docker exec "$1" sh -c 'for p in /proc/[0-9]*; do
    n=${p#/proc/}; c=$(tr "\0" " " < $p/cmdline 2>/dev/null)
    [ -n "$c" ] && echo "    PID $n: $c"; done' | sort -t' ' -k2 -n
}

# send one signal with `docker kill -s`, then report
try_signal() {
  local name=$1 sig=$2
  ensure_running "$name"
  local since; since=$(date +%s)
  echo ">>> docker kill -s $sig $name"
  docker kill -s "$sig" "$name" >/dev/null
  sleep 3
  echo "    -> $(state "$name")"
  docker logs --since "$since" "$name" 2>&1 | tail -n 5 | sed 's/^/    | /'
}

cleanup() { docker rm -f demo-sig demo-sig-shell demo-host demo-host-shell demo-fly demo-init >/dev/null 2>&1; }

# ---------- 1. docker stop ----------
stop() {
  echo "===== docker stop: SIGTERM, wait 10 s, SIGKILL ====="
  for pair in "exec:$EXEC_IMG:8000" "shell:$SHELL_IMG:8001"; do
    IFS=: read -r label image port <<<"$pair"
    start_c "demo-$label" "$image" "$port"
    echo "--- $label form"; show_pids "demo-$label"
    curl -s "localhost:$port/slow?seconds=5" >/dev/null &   # in-flight request
    sleep 1
    time docker stop "demo-$label" >/dev/null
    wait 2>/dev/null
    echo "    -> $(state "demo-$label")"
    docker logs "demo-$label" 2>&1 | tail -n 4 | sed 's/^/    | /'
    docker rm "demo-$label" >/dev/null
  done
  echo "Longer grace period:  docker stop -t 30 <c>   or   docker run --stop-timeout 30 ..."
}

# ---------- 2. docker kill -s on the exec-form container ----------
dockerkill() {
  echo "===== docker kill -s <SIG> on EXEC form (uvicorn is PID 1) ====="
  start_c demo-sig "$EXEC_IMG" 8002
  show_pids demo-sig
  # Ignored: PID 1 gets no default action, and uvicorn has no handler for these.
  try_signal demo-sig SIGHUP     # expect: still running
  try_signal demo-sig SIGUSR1    # expect: still running
  # Handled: uvicorn catches SIGINT and SIGTERM -> graceful shutdown, lifespan hook runs.
  try_signal demo-sig SIGINT     # expect: exited (usually 0), shutdown logs
  try_signal demo-sig SIGTERM    # expect: exited (usually 0, or 143 on some uvicorn builds)
  # Uncatchable: no cleanup at all.
  try_signal demo-sig SIGKILL    # expect: exited, 137, no shutdown logs
  docker rm -f demo-sig >/dev/null
}

# ---------- 3. docker kill -s on the shell-form container ----------
shellkill() {
  echo "===== docker kill -s <SIG> on SHELL form (sh is PID 1) ====="
  start_c demo-sig-shell "$SHELL_IMG" 8003
  show_pids demo-sig-shell
  try_signal demo-sig-shell SIGTERM   # expect: STILL RUNNING, the shell ignores it
  try_signal demo-sig-shell SIGINT    # expect: still running
  try_signal demo-sig-shell SIGKILL   # expect: exited 137, no shutdown logs
  docker rm -f demo-sig-shell >/dev/null
}

# ---------- 4. kill from INSIDE the container ----------
inside() {
  echo "===== docker exec <c> kill ... 1  (signals sent from inside the PID namespace) ====="
  start_c demo-sig "$EXEC_IMG" 8002
  echo ">>> docker exec demo-sig sh -c 'kill -KILL 1'"
  docker exec demo-sig sh -c 'kill -KILL 1'
  sleep 2
  echo "    -> $(state demo-sig)   (expect: still running; PID 1 cannot be killed from inside)"
  echo ">>> docker exec demo-sig sh -c 'kill -TERM 1'"
  docker exec demo-sig sh -c 'kill -TERM 1'
  sleep 3
  echo "    -> $(state demo-sig)   (expect: exited, because uvicorn HAS a SIGTERM handler)"
  docker logs --tail 5 demo-sig 2>&1 | sed 's/^/    | /'
  docker rm -f demo-sig >/dev/null
}

# ---------- 5. kill from the HOST shell ----------
hostkill() {
  echo "===== kill from the host shell (Linux host, needs sudo) ====="
  start_c demo-host "$EXEC_IMG" 8004
  local pid; pid=$(docker inspect -f '{{.State.Pid}}' demo-host)
  echo "Exec form: container PID 1 is host PID $pid"
  ps -o pid,ppid,cmd -p "$pid"
  echo ">>> sudo kill -TERM $pid"
  sudo kill -TERM "$pid"; sleep 3
  echo "    -> $(state demo-host)"
  docker logs --tail 5 demo-host 2>&1 | sed 's/^/    | /'

  start_c demo-host-shell "$SHELL_IMG" 8005
  pid=$(docker inspect -f '{{.State.Pid}}' demo-host-shell)
  echo; echo "Shell form: container PID 1 (the shell) is host PID $pid"
  ps -o pid,ppid,cmd --ppid "$pid" -p "$pid"
  echo ">>> sudo kill -TERM $pid   (to the shell)"
  sudo kill -TERM "$pid"; sleep 3
  echo "    -> $(state demo-host-shell)   (expect: still running)"
  local child; child=$(pgrep -P "$pid" | head -n1)
  if [ -n "$child" ]; then
    echo ">>> sudo kill -TERM $child   (straight to uvicorn, the child)"
    sudo kill -TERM "$child"; sleep 3
    echo "    -> $(state demo-host-shell)   (expect: exited, the shell ends when its child ends)"
    docker logs --tail 5 demo-host-shell 2>&1 | sed 's/^/    | /'
  else
    echo "(no child process: this shell exec'd uvicorn directly, so PID 1 is uvicorn)"
  fi
  docker rm -f demo-host demo-host-shell >/dev/null
}

# ---------- 6. what an in-flight request sees ----------
inflight() {
  echo "===== SIGTERM vs SIGKILL while a 5 s request is running ====="
  for sig in SIGTERM SIGKILL; do
    start_c demo-fly "$EXEC_IMG" 8006
    echo ">>> request /slow?seconds=5, then docker kill -s $sig after 1 s"
    ( curl -s -m 20 -w '  [http %{http_code}]\n' "localhost:8006/slow?seconds=5" \
        || echo "  curl failed (exit $?): connection dropped" ) &
    sleep 1
    docker kill -s "$sig" demo-fly >/dev/null
    wait 2>/dev/null
    echo "    -> $(state demo-fly)"
    docker rm -f demo-fly >/dev/null
  done
}

# ---------- 7. shell form rescued with --init ----------
init() {
  echo "===== SHELL form + docker run --init (tini is PID 1 and forwards signals) ====="
  start_c demo-init "$SHELL_IMG" 8007 --init
  show_pids demo-init
  try_signal demo-init SIGTERM    # expect: exited gracefully, shutdown logs appear
  docker rm -f demo-init >/dev/null
}

trap cleanup EXIT
case "${1:-all}" in
  build) build ;;
  stop) stop ;;
  dockerkill) dockerkill ;;
  shellkill) shellkill ;;
  inside) inside ;;
  hostkill) hostkill ;;
  inflight) inflight ;;
  init) init ;;
  all) build; stop; dockerkill; shellkill; inside; hostkill; inflight; init ;;
  *) echo "usage: $0 build|stop|dockerkill|shellkill|inside|hostkill|inflight|init|all"; exit 1 ;;
esac
