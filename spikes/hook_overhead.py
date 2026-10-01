#!/usr/bin/env python3
"""Auto-Context shell-hook spike: added time per prompt and delivery.

Drives interactive zsh and bash through a pseudo-terminal, alternating `cd`
between two directories, and times each command from the newline to the next
prompt, with and without the hook, with an isolated iClear daemon running and
not running. The daemon is observe-only, scope-locked to an empty lab registry
and lives in a temporary home, so it signals nothing.

    swift build -c release --product iclear && swift build -c release --product icleard
    python3 spikes/hook_overhead.py .build/release 1000
"""

import json
import os
import pty
import select
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time

BIN = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".build/release")
N = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(REPO, "Sources"), os.path.join(REPO, "Tests")]
MARK = "__ICX_PROMPT__"


def pct(xs, p):
    s = sorted(xs)
    return s[min(len(s) - 1, int(round(p / 100 * (len(s) - 1))))]


class Shell:
    def __init__(self, argv, env):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execve(argv[0], argv, env)
        self.buf = b""

    def read_until(self, token, timeout=10):
        end = time.monotonic() + timeout
        while token not in self.buf:
            r, _, _ = select.select([self.fd], [], [], max(0, end - time.monotonic()))
            if not r:
                raise TimeoutError(self.buf[-200:])
            self.buf += os.read(self.fd, 65536)
        self.buf = self.buf[self.buf.index(token) + len(token):]

    def run(self, line):
        """Seconds from sending the line to the next prompt."""
        t0 = time.perf_counter()
        os.write(self.fd, (line + "\n").encode())
        self.read_until(MARK.encode())
        return time.perf_counter() - t0

    def close(self):
        os.kill(self.pid, signal.SIGKILL)
        os.waitpid(self.pid, 0)
        os.close(self.fd)


def session(shell, hook, env):
    if shell == "zsh":
        argv = ["/bin/zsh", "-f", "-i"]
        setup = f"PS1='{MARK[:6]}''{MARK[6:]}'; unsetopt zle"
    else:
        argv = ["/bin/bash", "--noprofile", "--norc", "-i"]
        setup = f"PS1='{MARK[:6]}''{MARK[6:]}'; PS2=''"
    sh = Shell(argv, env)
    os.write(sh.fd, (setup + "\n").encode())
    sh.read_until(MARK.encode())
    if hook:
        snippet = subprocess.run([os.path.join(BIN, "iclear"), "hook", shell], capture_output=True, text=True, env=env).stdout
        path = os.path.join(env["ICLEAR_HOME"], f"hook.{shell}")
        with open(path, "w") as f:
            f.write(snippet)
        sh.run(f". {path}")
    for _ in range(20):  # warm up
        sh.run(f"cd {DIRS[0]}")
        sh.run(f"cd {DIRS[1]}")
    times = [sh.run(f"cd {DIRS[i % 2]}") * 1000 for i in range(N)]
    sh.close()
    return times


def events(env):
    out = subprocess.run([os.path.join(BIN, "iclear"), "context", "status"], capture_output=True, text=True, env=env).stdout
    for line in out.splitlines():
        if line.startswith("Shell events received:"):
            return int(line.split(":")[1].split()[0])
    return None


def main():
    home = tempfile.mkdtemp(prefix="icx.", dir="/tmp")
    env = {
        "HOME": home,
        "PATH": BIN + ":/usr/bin:/bin:/usr/sbin:/sbin",
        "ICLEAR_HOME": home,
        "ICLEAR_OBSERVE_ONLY": "1",
        "ICLEAR_LAB": "1",
        "TERM": "dumb",
        "LANG": "en_US.UTF-8",
    }
    sock = os.path.join(home, "Library/Application Support/iClear/icleard.sock")
    results, delivery, daemon = {}, {}, None
    try:
        for state in ["down", "up"]:
            if state == "up":
                daemon = subprocess.Popen([os.path.join(BIN, "icleard")], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                for _ in range(100):
                    if os.path.exists(sock) and events(env) is not None:
                        break
                    time.sleep(0.1)
                else:
                    raise SystemExit("daemon did not start")
            for shell in ["zsh", "bash"]:
                before = events(env) if state == "up" else None
                base = session(shell, False, env)
                hooked = session(shell, True, env)
                results[(shell, state)] = (base, hooked)
                if state == "up":
                    time.sleep(3)
                    delivery[shell] = events(env) - before
    finally:
        if daemon:
            daemon.terminate()
            daemon.wait(10)
        shutil.rmtree(home, ignore_errors=True)

    report = {"n": N, "rows": [], "delivery": {}}
    print(f"N = {N} directory changes per run; times in ms from Enter to the next prompt")
    print(f"{'shell':6} {'daemon':7} {'base p50':>9} {'base p95':>9} {'hook p50':>9} {'hook p95':>9} {'added p50':>10} {'added p95':>10}")
    for (shell, state), (base, hooked) in results.items():
        row = {
            "shell": shell, "daemon": state,
            "base_p50": pct(base, 50), "base_p95": pct(base, 95),
            "hook_p50": pct(hooked, 50), "hook_p95": pct(hooked, 95),
            "added_p50": pct(hooked, 50) - pct(base, 50), "added_p95": pct(hooked, 95) - pct(base, 95),
            "hook_max": max(hooked), "base_mean": statistics.mean(base), "hook_mean": statistics.mean(hooked),
        }
        report["rows"].append(row)
        print(f"{shell:6} {state:7} {row['base_p50']:9.2f} {row['base_p95']:9.2f} {row['hook_p50']:9.2f} {row['hook_p95']:9.2f} "
              f"{row['added_p50']:10.2f} {row['added_p95']:10.2f}")
    for shell, got in delivery.items():
        # Each hooked run sends 40 warm-up events plus N measured ones; bash also
        # reports the starting directory at its first prompt after the hook is added.
        sent = N + 40 + (1 if shell == "bash" else 0)
        report["delivery"][shell] = {"sent": sent, "received": got}
        print(f"delivery {shell}: {got}/{sent} events received by the daemon")
    print(json.dumps(report))


main()
