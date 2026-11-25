// Pure formatting and parsing helpers for Cornerstone GPU.
// No Qt dependencies so `node tests/run.js` tests it directly.

function fmtMb(mb) {
  var n = Number(mb)
  if (!isFinite(n) || n < 0) return "0 MB"
  if (n >= 1024) return (n / 1024).toFixed(1) + " GB"
  return Math.round(n) + " MB"
}

function friendlyProc(comm, unit) {
  var u = String(unit || "")
  if (u === "cornerstone-stt-qwen") return "Cornerstone Qwen STT"
  if (u === "cornerstone-stt-gpu") return "Cornerstone Whisper GPU"
  if (u === "cornerstone-clips") return "Cornerstone Clip Buffer"
  var c = String(comm || "").trim()
  if (/^Godot/i.test(c)) return "Godot Engine"
  if (/^cornerstone-qwe/i.test(c)) return "Cornerstone Qwen STT"
  if (/^whisper-server/i.test(c)) return "Cornerstone Whisper GPU"
  if (/^cornerstone-cli/i.test(c)) return "Cornerstone Clip Buffer"
  if (/^chrome$/i.test(c)) return "Google Chrome"
  if (/^quickshell$/i.test(c)) return "Omarchy Shell"
  return c || "Process"
}

function severity(percent) {
  var p = Number(percent) || 0
  if (p >= 90) return "critical"
  if (p >= 80) return "warn"
  return "normal"
}

function parseSnapshot(text) {
  var d
  try { d = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!d || typeof d !== "object" || Array.isArray(d)) return null
  var usedMb = Math.max(0, Number(d.usedMb) || 0)
  var totalMb = Math.max(0, Number(d.totalMb) || 0)
  var pct = totalMb > 0 ? Math.min(100, Math.max(0, Math.round((usedMb / totalMb) * 100))) : 0
  var procs = Array.isArray(d.procs) ? d.procs.slice(0, 10).map(function(p) {
    return {
      pid: parseInt(p.pid, 10) || 0,
      comm: String(p.comm || "").slice(0, 48),
      label: friendlyProc(p.comm, p.unit),
      unit: String(p.unit || "").slice(0, 48),
      vramMb: Math.max(0, Number(p.vramMb) || 0)
    }
  }) : []
  return {
    usedMb: usedMb,
    totalMb: totalMb,
    percent: pct,
    busyPct: Math.min(100, Math.max(0, Number(d.busyPct) || 0)),
    tempC: Number(d.tempC) || 0,
    qwenActive: d.qwenActive === true,
    whisperActive: d.whisperActive === true,
    lanMouseActive: d.lanMouseActive === true,
    procs: procs
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    fmtMb: fmtMb,
    friendlyProc: friendlyProc,
    severity: severity,
    parseSnapshot: parseSnapshot
  }
}
