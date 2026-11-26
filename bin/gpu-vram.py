#!/usr/bin/env python3
"""Multi-vendor GPU VRAM snapshot for cornerstone.gpu.

Auto-discovers:
  1. AMD / discrete DRM sysfs (mem_info_vram_total + /proc/*/fdinfo)
  2. NVIDIA via nvidia-smi (VRAM, utilization, temp, per-process VRAM)
  3. Unified / integrated GPUs (Apple Silicon Asahi AGX, Intel, Mesa)

Pass --brief for bar-only readout (skips per-process walk when panel is closed).
"""
import glob
import json
import os
import shutil
import subprocess
import sys

BRIEF = "--brief" in sys.argv
HOME = os.path.expanduser("~")
UNIT_DIRS = (
    os.path.join(HOME, ".config/systemd/user"),
    "/etc/systemd/user",
    "/usr/lib/systemd/user",
)


def read_text(path):
    try:
        with open(path, "rb") as f:
            return f.read().replace(b"\x00", b"").decode("utf-8", errors="ignore").strip()
    except Exception:
        return ""


def read_int(path):
    try:
        return int(read_text(path))
    except Exception:
        return 0


def unit_exists(unit):
    fname = f"{unit}.service"
    return any(os.path.exists(os.path.join(d, fname)) for d in UNIT_DIRS)


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


def pick_amd_card():
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


def scan_drm_procs():
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
        comm = read_text(f"/proc/{pid}/comm") or "?"
        rows.append({
            "pid": int(pid),
            "comm": comm,
            "unit": unit_for_pid(pid),
            "vramMb": round(kb / 1024.0, 1),
        })
    return rows


def probe_nvidia():
    if not shutil.which("nvidia-smi"):
        return None
    try:
        r = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True, text=True, timeout=2.0,
        )
        if r.returncode != 0 or not r.stdout.strip():
            return None
        parts = [p.strip() for p in r.stdout.strip().splitlines()[0].split(",")]
        if len(parts) < 5:
            return None
        name = parts[0]
        used_mb = float(parts[1]) if parts[1].replace(".", "", 1).isdigit() else 0.0
        total_mb = float(parts[2]) if parts[2].replace(".", "", 1).isdigit() else 0.0
        busy = int(float(parts[3])) if parts[3].replace(".", "", 1).isdigit() else 0
        temp = float(parts[4]) if parts[4].replace(".", "", 1).isdigit() else 0.0
    except Exception:
        return None

    procs = []
    if not BRIEF:
        by_pid = {}
        for flag in ("--query-compute-apps=pid,process_name,used_memory", "--query-graphics-apps=pid,process_name,used_memory"):
            try:
                pr = subprocess.run(
                    ["nvidia-smi", flag, "--format=csv,noheader,nounits"],
                    capture_output=True, text=True, timeout=2.0,
                )
                if pr.returncode != 0:
                    continue
                for line in pr.stdout.splitlines():
                    cols = [c.strip() for c in line.split(",")]
                    if len(cols) < 3 or not cols[0].isdigit():
                        continue
                    pid = int(cols[0])
                    comm = os.path.basename(cols[1]) or read_text(f"/proc/{pid}/comm") or "?"
                    mb = float(cols[2]) if cols[2].replace(".", "", 1).isdigit() else 0.0
                    if mb > by_pid.get(pid, (0, ""))[0]:
                        by_pid[pid] = (mb, comm)
            except Exception:
                pass
        for pid, (mb, comm) in sorted(by_pid.items(), key=lambda x: -x[1][0])[:10]:
            if mb < 8:
                continue
            procs.append({
                "pid": pid,
                "comm": comm,
                "unit": unit_for_pid(pid),
                "vramMb": round(mb, 1),
            })

    return {
        "backend": "nvidia",
        "gpuName": name,
        "unified": total_mb <= 0,
        "usedMb": round(used_mb, 1),
        "totalMb": round(total_mb, 1),
        "busyPct": busy,
        "tempC": round(temp, 1),
        "procs": procs,
    }


def detect_unified_name():
    for p in sorted(glob.glob("/sys/class/drm/card*/device/uevent")):
        txt = read_text(p)
        if "DRIVER=asahi" in txt or "DRIVER=apple-drm" in txt:
            return "Apple Silicon (Unified)"
        if "DRIVER=i915" in txt or "DRIVER=xe" in txt:
            return "Intel Graphics (Unified)"
    return "Unified Memory GPU"


def main():
    has_lan_mouse = unit_exists("lan-mouse") or bool(shutil.which("lan-mouse"))

    dev, total_bytes = pick_amd_card()
    if dev and total_bytes > 0:
        used_bytes = read_int(os.path.join(dev, "mem_info_vram_used"))
        out = {
            "backend": "amd",
            "gpuName": "AMD GPU",
            "unified": False,
            "usedMb": round(used_bytes / (1024 * 1024), 1),
            "totalMb": round(total_bytes / (1024 * 1024), 1),
            "busyPct": read_int(os.path.join(dev, "gpu_busy_percent")),
            "tempC": read_temp(dev),
            "procs": [] if BRIEF else scan_drm_procs(),
        }
    else:
        nv = probe_nvidia()
        if nv:
            out = nv
        else:
            out = {
                "backend": "unified",
                "gpuName": detect_unified_name(),
                "unified": True,
                "usedMb": 0.0,
                "totalMb": 0.0,
                "busyPct": 0,
                "tempC": 0,
                "procs": [],
            }

    has_local_stt = (not out["unified"]) and (unit_exists("cornerstone-stt-qwen") or unit_exists("cornerstone-stt-gpu"))
    out["hasLocalStt"] = has_local_stt
    out["hasLanMouse"] = has_lan_mouse
    out["qwenActive"] = False if (BRIEF or not has_local_stt) else service_active("cornerstone-stt-qwen")
    out["whisperActive"] = False if (BRIEF or not has_local_stt) else service_active("cornerstone-stt-gpu")
    out["lanMouseActive"] = False if (BRIEF or not has_lan_mouse) else service_active("lan-mouse")
    print(json.dumps(out))


if __name__ == "__main__":
    main()
