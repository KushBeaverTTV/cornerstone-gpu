# Cornerstone GPU

Multi-vendor VRAM budget monitor and one-click Game / Godot Mode switcher for the Omarchy status bar.

- **Auto-discovery**: supports **AMD** DRM sysfs (`/sys/class/drm/card*/device/mem_info_vram_used` + `/proc/*/fdinfo/*`), **NVIDIA** (`nvidia-smi` VRAM, temp, utilization, and per-process compute/graphics VRAM), and **Unified Memory** GPUs (Apple Silicon Asahi AGX, Intel).
- **Bar pill**: `VRAM XX%` styled beside `CPU` / `MEM`, tinted amber at 80%+ and red at 90%+, switching to a green gamepad icon in Game Mode. Left-click opens the panel; right-click toggles Game / Focus Mode.
- **Quick actions**: toggle Game / Godot Mode (pauses LAN Mouse and unloads local GPU STT servers when installed) and unload/start `cornerstone-stt-qwen` + `cornerstone-stt-gpu` on discrete-GPU hosts.

## Tests

```bash
node tests/run.js
```
