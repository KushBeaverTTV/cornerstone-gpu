#!/usr/bin/env python3
"""Fast AMD/DRM VRAM snapshot for cornerstone.gpu.
Reads sysfs VRAM + busy + temp and aggregates per-process VRAM from /proc/*/fdinfo.
Pass --brief for bar-only sysfs readout (skips /proc fdinfo walk when panel is closed)."""
import glob
import json
import os
import subprocess
import sys

BRIEF = "--brief" in sys.argv


def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except Exception:
        return 0


def pick_card():
    best = None
    best_total = 0
    for path in sorted(glob.glob("/sys/class/drm/card*/device/mem_info_vram_total")):
        total = read_int(path)
        if total > best_total:
            best_total = total
            best = os.path.dirname(path)
    return best, best_total


def read_temp(dev):
    for p in sorted(glob.glob(os.path.join(dev, "hwmon/hwmon*/temp*_input"))):
        v = read_int(p)
        if v > 0:
            return round(v / 1000.0, 1)
    return 0


def service_active(unit):
    try:
        r = subprocess.run(
            ["systemctl", "--user", "is-active", f"{unit}.service"],
            capture_output=True, text=True, timeout=1.5
        )
        return r.stdout.strip() == "active"
    except Exception:
        return False


def unit_for_pid(pid):
    try:
        with open(f"/proc/{pid}/cgroup") as f:
            txt = f.read()
        for name in ("cornerstone-stt-qwen", "cornerstone-stt-gpu", "cornerstone-clips"):
            if f"{name}.service" in txt:
                return name
    except Exception:
        pass
    return ""


def scan_procs():
    by_pid = {}
    for p in glob.glob("/proc/[0-9]*/fdinfo/*"):
        try:
            pid = p.split("/")[2]
            with open(p) as f:
                txt = f.read()
            if "drm-memory-vram:" not in txt:
                continue
            for line in txt.splitlines():
                if line.startswith("drm-memory-vram:"):
                    parts = line.split()
                    val = int(parts[1])
                    unit = parts[2] if len(parts) > 2 else "KiB"
                    if unit.startswith("G"):
                        kb = val * 1024 * 1024
                    elif unit.startswith("M"):
                        kb = val * 1024
                    elif unit.startswith("K"):
                        kb = val
                    else:
                        kb = val // 1024
                    if kb > by_pid.get(pid, 0):
                        by_pid[pid] = kb
        except Exception:
            pass

    rows = []
    for pid, kb in sorted(by_pid.items(), key=lambda x: -x[1])[:10]:
        if kb < 8192:
            continue
        try:
            with open(f"/proc/{pid}/comm") as f:
                comm = f.read().strip()
        except Exception:
            comm = "?"
        rows.append({
            "pid": int(pid),
            "comm": comm,
            "unit": unit_for_pid(pid),
            "vramMb": round(kb / 1024.0, 1),
        })
    return rows


def main():
    dev, total_bytes = pick_card()
    used_bytes = read_int(os.path.join(dev, "mem_info_vram_used")) if dev else 0
    busy = read_int(os.path.join(dev, "gpu_busy_percent")) if dev else 0
    temp = read_temp(dev) if dev else 0
    out = {
        "usedMb": round(used_bytes / (1024 * 1024), 1),
        "totalMb": round(total_bytes / (1024 * 1024), 1),
        "busyPct": busy,
        "tempC": temp,
        "qwenActive": False if BRIEF else service_active("cornerstone-stt-qwen"),
        "whisperActive": False if BRIEF else service_active("cornerstone-stt-gpu"),
        "lanMouseActive": False if BRIEF else service_active("lan-mouse"),
        "procs": [] if BRIEF else scan_procs(),
    }
    print(json.dumps(out))


if __name__ == "__main__":
    main()
