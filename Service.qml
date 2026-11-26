import QtQuick
import Quickshell
import Quickshell.Io
import "Gpu.js" as Gpu

// Single session-wide service for Cornerstone GPU: reads AMD VRAM sysfs
// lightly for the bar readout and runs the per-process fdinfo scan only while
// a panel is open. Also manages Game / Dev Mode (unloads local GPU STT and
// pauses LAN Mouse while enabled, restoring them on exit).
Item {
  id: service

  property var shell: null
  readonly property string pluginId: "cornerstone.gpu"
  readonly property string probePath: Qt.resolvedUrl("bin/gpu-vram.py").toString().replace(/^file:\/\//, "")

  property string backend: "amd"
  property string gpuName: ""
  property bool unified: false
  property bool hasLocalStt: true
  property bool hasLanMouse: true
  property real usedMb: 0
  property real totalMb: 0
  property int percent: 0
  property int busyPct: 0
  property real tempC: 0
  property bool qwenActive: false
  property bool whisperActive: false
  property bool lanMouseActive: false
  property var procs: []
  property int watchers: 0
  property bool gameMode: false
  property bool restoreLanMouse: false
  property bool restoreQwen: false
  property bool restoreWhisper: false

  readonly property string severity: Gpu.severity(percent)
  readonly property bool detailed: watchers > 0

  function refresh() {
    if (probeProc.running) return
    probeProc.command = detailed ? ["python3", probePath] : ["python3", probePath, "--brief"]
    probeProc.running = true
  }

  function apply(text) {
    var snap = Gpu.parseSnapshot(text)
    if (!snap) return
    backend = snap.backend
    gpuName = snap.gpuName
    unified = snap.unified
    hasLocalStt = snap.hasLocalStt
    hasLanMouse = snap.hasLanMouse
    usedMb = snap.usedMb
    totalMb = snap.totalMb
    percent = snap.percent
    busyPct = snap.busyPct
    tempC = snap.tempC
    if (detailed || snap.procs.length > 0) {
      qwenActive = snap.qwenActive
      whisperActive = snap.whisperActive
      lanMouseActive = snap.lanMouseActive
      procs = snap.procs
    }
  }

  function runCmd(argv) {
    Quickshell.execDetached(argv)
    refreshSoon.restart()
  }

  function toggleService(unit, active) {
    if (["cornerstone-stt-qwen", "cornerstone-stt-gpu", "cornerstone-clips"].indexOf(unit) === -1) return
    runCmd(["systemctl", "--user", active ? "stop" : "start", unit + ".service"])
  }

  function freeDictationVram() {
    runCmd(["systemctl", "--user", "stop", "cornerstone-stt-qwen.service", "cornerstone-stt-gpu.service"])
  }

  function restoreDictationVram() {
    runCmd(["systemctl", "--user", "start", "cornerstone-stt-gpu.service", "cornerstone-stt-qwen.service"])
  }

  function toggleGameMode() {
    if (!gameMode) {
      restoreQwen = qwenActive
      restoreWhisper = whisperActive
      restoreLanMouse = lanMouseActive
      gameMode = true
      var stopUnits = ["cornerstone-stt-qwen.service", "cornerstone-stt-gpu.service"]
      if (lanMouseActive) stopUnits.push("lan-mouse.service")
      runCmd(["systemctl", "--user", "stop"].concat(stopUnits))
      Quickshell.execDetached(["omarchy-shell", "dynamic-island", "toast",
        "Game / Godot Mode ON", "Local GPU STT unloaded" + (lanMouseActive ? " · LAN Mouse paused" : ""), "󰊗", "green"])
    } else {
      gameMode = false
      var startUnits = []
      if (restoreWhisper) startUnits.push("cornerstone-stt-gpu.service")
      if (restoreQwen) startUnits.push("cornerstone-stt-qwen.service")
      if (restoreLanMouse) startUnits.push("lan-mouse.service")
      if (startUnits.length > 0) runCmd(["systemctl", "--user", "start"].concat(startUnits))
      Quickshell.execDetached(["omarchy-shell", "dynamic-island", "toast",
        "Game / Godot Mode OFF", "Restored background services", "󰊗", "accent"])
    }
  }

  function terminateProc(proc) {
    if (!proc) return
    if (proc.unit) {
      toggleService(proc.unit, true)
      return
    }
    var pid = parseInt(proc.pid, 10) || 0
    // Never allow killing Hyprland or the shell itself from a stray tap.
    if (pid <= 1 || /^(Hyprland|quickshell|omarchy-shell)$/i.test(String(proc.comm || ""))) return
    runCmd(["kill", "-TERM", String(pid)])
  }

  Process {
    id: probeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.apply(this.text)
    }
  }

  Timer {
    interval: service.detailed ? 2000 : 4000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: service.refresh()
  }

  Timer {
    id: refreshSoon
    interval: 900
    onTriggered: service.refresh()
  }

  IpcHandler {
    target: "cornerstone-gpu"

    function toggle(): string { if (service.shell) service.shell.toggle(service.pluginId); return "ok" }
    function gameModeToggle(): string { service.toggleGameMode(); return service.gameMode ? "on" : "off" }
    function freeVram(): string { service.freeDictationVram(); return "ok" }
    function refresh(): string { service.refresh(); return "ok" }
  }
}
