# Cornerstone GPU

VRAM budget monitor and one-click Game / Godot Mode switcher for the Omarchy status bar.

- **Bar pill**: `VRAM XX%` styled beside `CPU` / `MEM`, tinted amber at 70%+ and red at 85%+, switching to a green gamepad icon in Game Mode. Left-click opens the panel; right-click toggles Game / Godot Mode.
- **Per-process VRAM**: reads `/sys/class/drm/card*/device/mem_info_vram_used` and `/proc/*/fdinfo/*` (`drm-memory-vram:`) natively with zero external GPU tools.
- **Quick actions**: unload/start the local GPU STT servers (`cornerstone-stt-qwen` + `cornerstone-stt-gpu`) to free ~4.2 GB of VRAM, or toggle Game / Godot Mode (unloads AI STT and pauses LAN Mouse together).

## Tests

```bash
node tests/run.js
```
