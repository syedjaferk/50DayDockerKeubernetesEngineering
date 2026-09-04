## 1. Processes, Parent-Child Relationships, and PIDs

### Core concepts

- A **process** is a running instance of a program. Every process has a unique **PID** (Process ID).
- Every process (except PID 1) has a **parent process**, identified by its **PPID** (Parent Process ID).
- The very first process started by the kernel at boot is **PID 1** (historically `init`, on modern systems usually `systemd`). It is the ancestor of every other process.
- When a process starts another process, it does so via `fork()` (creates a copy of itself) followed by `exec()` (replaces that copy's memory with the new program). This is why child processes inherit environment variables, open file descriptors, and permissions from their parent.
- If a parent dies before its child, the child becomes an **orphan** and is "re-parented" to PID 1 (or the nearest subreaper).
- A process that has finished executing but still has an entry in the process table (because its parent hasn't read its exit status) is called a **zombie**.

### Useful commands

```bash
ps aux              # Snapshot of all processes (BSD style)
ps -ef               # Snapshot of all processes (UNIX style, shows PPID)
ps --forest          # Show process tree using ps
pstree               # Visual tree of parent-child relationships
pstree -p            # Include PIDs in the tree
echo $$              # PID of the current shell
echo $PPID           # PPID of the current shell
```

### Why this matters for Docker

A container is, at its core, just a **process tree** isolated from the host using namespaces. Understanding PID 1 is critical — the process you specify as `ENTRYPOINT`/`CMD` in a Dockerfile becomes **PID 1 inside the container's PID namespace**, which has special responsibilities (like reaping zombies and handling termination signals).

---

## 2. Inspecting and Controlling Processes

### `ps` — snapshot of processes

```bash
ps aux                        # all processes, all users
ps aux --sort=-%cpu           # sorted by CPU usage
ps aux --sort=-%mem           # sorted by memory usage
ps -p <PID> -o pid,ppid,cmd   # custom columns for a specific PID
```

### `kill` — send a signal to a process by PID

```bash
kill <PID>              # sends SIGTERM by default
kill -9 <PID>            # sends SIGKILL (force kill)
kill -SIGHUP <PID>       # sends SIGHUP by name
kill -l                  # list all available signals
```

### `pkill` / `killall` — send a signal by process name

```bash
pkill nginx              # SIGTERM to all processes named "nginx"
pkill -9 -f "python app.py"   # SIGKILL matching full command line
killall node             # SIGTERM to all "node" processes
```

### Other useful inspection tools

```bash
jobs                      # background jobs in current shell
fg / bg                   # bring job to foreground/background
nice -n 10 <command>       # start a process with lower priority
renice -n 5 -p <PID>       # change priority of a running process
lsof -p <PID>              # files opened by a process
```

---

## 3. Linux Signals

Signals are software interrupts sent to a process to notify it of an event. A process can choose to **catch**, **ignore**, or let the **default action** occur (except for a couple of signals that can never be caught).

|Signal|Number|Default Action|Use Case|
|---|---|---|---|
|`SIGTERM`|15|Terminate|Polite request to shut down; process can catch it and clean up (close files, flush buffers, save state) before exiting. This is what `kill` sends by default and what Docker sends first on `docker stop`.|
|`SIGKILL`|9|Terminate|Immediate, forceful termination. **Cannot be caught, blocked, or ignored.** The kernel kills the process outright — no cleanup happens. Use only when a process is unresponsive.|
|`SIGINT`|2|Terminate|Sent when you press `Ctrl+C` in a terminal. Interrupts a foreground process; catchable, so many programs use it to exit gracefully.|
|`SIGHUP`|1|Terminate|Originally sent when a terminal closed ("hang up"). Now commonly repurposed by daemons to mean "reload your configuration file without restarting" (e.g. `nginx`, `sshd`).|
|`SIGSTOP`|19|Stop|Pauses a process. Cannot be caught (like `SIGKILL`).|
|`SIGCONT`|18|Continue|Resumes a stopped process.|

### Practical guidance: when to use which

1. **Always try `SIGTERM` first.** It gives the application a chance to shut down cleanly — close database connections, finish in-flight requests, delete temp files.
2. **Escalate to `SIGKILL` only if the process ignores `SIGTERM`** or is hung. This is a last resort since it skips all cleanup.
3. **Use `SIGHUP`** when you want a long-running daemon to reload config without a full restart (check the tool's docs — not all programs honor this convention).
4. **`SIGINT`** is mostly relevant for interactive/foreground processes you're running yourself in a terminal.

### Sending signals

```bash
kill -SIGTERM <PID>     # or: kill -15 <PID>
kill -SIGKILL <PID>      # or: kill -9 <PID>
kill -SIGHUP <PID>       # or: kill -1 <PID>
```

### Why this matters for Docker

- `docker stop` sends `SIGTERM`, waits a grace period (default 10s), then sends `SIGKILL` if the container hasn't exited.
- `docker kill` sends `SIGKILL` (or a custom signal) immediately.
- If your container's PID 1 doesn't properly handle/forward `SIGTERM` (common with shell-script entrypoints or `sh -c`), `docker stop` can hang for the full timeout and then force-kill, causing unclean shutdowns. This is why tools like `tini` or `dumb-init` are often used as an init process inside containers.
