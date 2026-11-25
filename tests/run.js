const assert = require("node:assert/strict")
const Gpu = require("../Gpu.js")

assert.equal(Gpu.fmtMb(512), "512 MB")
assert.equal(Gpu.fmtMb(2048), "2.0 GB")
assert.equal(Gpu.severity(40), "normal")
assert.equal(Gpu.severity(82), "warn")
assert.equal(Gpu.severity(95), "critical")
assert.equal(Gpu.friendlyProc("Godot_v4.7.2-st", ""), "Godot Engine")
assert.equal(Gpu.friendlyProc("cornerstone-qwe", "cornerstone-stt-qwen"), "Cornerstone Qwen STT")

const snap = Gpu.parseSnapshot(JSON.stringify({
  usedMb: 10240,
  totalMb: 20480,
  busyPct: 45,
  tempC: 62.5,
  qwenActive: true,
  procs: [{ pid: 100, comm: "Godot_v4.7", unit: "", vramMb: 4600 }]
}))
assert.equal(snap.percent, 50)
assert.equal(snap.qwenActive, true)
assert.equal(snap.procs[0].label, "Godot Engine")
assert.equal(Gpu.parseSnapshot("{"), null)

console.log("PASS cornerstone.gpu unit tests")
