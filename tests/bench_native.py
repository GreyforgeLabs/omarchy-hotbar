#!/usr/bin/env python3
"""Compare Hotbar's native fast path with the portable shell path.

Runs against the live widget: the CLI through omarchy-shell (HOTBAR_NO_NATIVE=1)
versus through bin/hotbar-native, the raw transports, and the two Places
helpers. Median wall time and child CPU time (rusage) over N launches.
Read-only calls only; nothing here changes pins or settings.
"""
import os
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
N = int(os.environ.get("N", "40"))
HOME = Path.home()


def measure(argv, env=None):
    walls, cpus = [], []
    for _ in range(N):
        start = time.perf_counter_ns()
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE, env=env)
        _, status, usage = os.wait4(proc.pid, 0)
        walls.append((time.perf_counter_ns() - start) / 1e6)
        cpus.append((usage.ru_utime + usage.ru_stime) * 1000)
        if os.WEXITSTATUS(status) != 0:
            raise SystemExit(f"{argv} exited {os.WEXITSTATUS(status)}: {proc.stderr.read().decode().strip()}")
        proc.stderr.close()
    return statistics.median(walls), statistics.median(cpus)


def report(label, old, new):
    print(f"{label}")
    print(f"  portable  {old[0]:7.1f} ms wall  {old[1]:7.1f} ms CPU")
    print(f"  native    {new[0]:7.1f} ms wall  {new[1]:7.1f} ms CPU")
    print(f"  {old[0] / new[0]:.0f}x lower latency, {old[1] / new[1]:.0f}x less CPU")


def main():
    native = ROOT / "bin/hotbar-native"
    places_native = ROOT / "bin/hotbar-places-native"
    if not native.is_file() or not places_native.is_file():
        raise SystemExit("Run make native first")
    if shutil.which("omarchy-shell") is None:
        raise SystemExit("omarchy-shell not found; this benchmark needs the live shell")
    probe = subprocess.run([str(native), "ping"], capture_output=True)
    if probe.returncode != 0:
        raise SystemExit("the widget socket is not answering (is Hotbar >= 0.3.0 loaded?)")

    portable_env = dict(os.environ, HOTBAR_NO_NATIVE="1")
    cli = str(ROOT / "bin/hotbar")
    report("hotbar pins (the CLI end to end)",
           measure([cli, "pins"], portable_env), measure([cli, "pins"]))
    report("hotbar activate 1 as a keybind would run it (preflight + call; 'no pin' answers count)",
           measure([cli, "get", "iconSize"], portable_env), measure([cli, "get", "iconSize"]))
    report("one call to the widget (omarchy-shell hotbar ping vs hotbar-native ping)",
           measure(["omarchy-shell", "hotbar", "ping"]), measure([str(native), "ping"]))
    paths = [str(HOME), str(HOME / "Downloads"), str(HOME / "Documents"), str(HOME / "Pictures"),
             str(HOME / "Music"), str(HOME / "Videos"), str(HOME / ".local/share/Trash/files")]
    report("Places helper (bin/hotbar-places vs bin/hotbar-places-native)",
           measure([str(ROOT / "bin/hotbar-places")] + paths), measure([str(places_native)] + paths))
    print(f"(medians of {N} launches each)")


if __name__ == "__main__":
    sys.exit(main())
