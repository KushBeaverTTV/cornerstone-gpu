const assert = require("node:assert/strict")
const Gpu = require("../Gpu.js")

assert.equal(Gpu.fmtMb(512), "512 MB")
assert.equal(Gpu.fmtMb(2048), "2.0 GB")
assert.equal(Gpu.severity(40), "normal")
assert.equal(Gpu.severity(82), "warn")
assert.equal(Gpu.severity(95), "critical")
assert.equal(Gpu.friendlyProc("Godot_v4.7.2-st", ""), "Godot Engine")
assert.equal(Gpu.friendlyProc("cornerstone-qwe", "cornerstone-stt-qwen"), "Cornerstone Qwen STT")

// AMD discrete snapshot (legacy shape preserved)
const snap = Gpu.parseSnapshot(JSON.stringify({
  usedMb: 10240,
  totalMb: 20480,
  busyPct: 45,
  tempC: 62.5,
  qwenActive: true,
  procs: [{ pid: 100, comm: "Godot_v4.7", unit: "", vramMb: 4600 }]
}))
assert.equal(snap.backend, "amd")
assert.equal(snap.unified, false)
assert.equal(snap.percent, 50)
assert.equal(snap.qwenActive, true)
assert.equal(snap.procs[0].label, "Godot Engine")

// NVIDIA discrete snapshot
const nv = Gpu.parseSnapshot(JSON.stringify({
  backend: "nvidia",
  gpuName: "NVIDIA GeForce RTX 4090",
  unified: false,
  usedMb: 6144,
  totalMb: 24576,
  busyPct: 30,
  tempC: 54,
  hasLocalStt: false,
  procs: [{ pid: 200, comm: "blender", unit: "", vramMb: 3200 }]
}))
assert.equal(nv.backend, "nvidia")
assert.equal(nv.percent, 25)
assert.equal(nv.hasLocalStt, false)

// Apple Silicon unified memory snapshot
const unified = Gpu.parseSnapshot(JSON.stringify({
  backend: "unified",
  gpuName: "Apple Silicon (Unified)",
  unified: true,
  usedMb: 0,
  totalMb: 0,
  hasLocalStt: false,
  procs: []
}))
assert.equal(unified.unified, true)
assert.equal(unified.percent, 0)
assert.equal(unified.hasLocalStt, false)

assert.equal(Gpu.parseSnapshot("{"), null)

console.log("PASS cornerstone.gpu unit tests")
