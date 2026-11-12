// Audit the animation clips of the rigged cast: does every looping clip return to its
// first pose, and is the standing idle calm enough for a queue or a counter?
//   cd tools && node clip_seams.mjs [--json] [file.glb ...]
// With no files it checks assets/models/customers and assets/models/crew. Exits 1 on a
// failed check. "Seam" is the largest joint rotation between a clip's last and first key;
// a looping clip pops by that much every cycle unless the seam is no bigger than one
// ordinary frame step (a cycle exported without its duplicated end frame).
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { readdirSync } from 'node:fs';
import { dirname, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const LOOPS = ['idle', 'sit', 'walk', 'carry'];
const SEAM_MAX_DEG = 2.0;        // a visible pop on a phone
const STEP_FACTOR = 1.5;         // seam may equal one frame step of the same joint
const IDLE_HIPS_MAX_DEG = 12.0;  // a standing idle does not turn the body
const IDLE_HEAD_MAX_DEG = 30.0;
const DRIFT_MAX = 0.04;          // root translation seam, as a share of hip height

const args = process.argv.slice(2);
const asJson = args.includes('--json');
let files = args.filter((a) => !a.startsWith('--'));
if (files.length === 0) {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'assets', 'models');
  for (const dir of ['customers', 'crew']) {
    for (const f of readdirSync(join(root, dir)).sort()) {
      if (f.endsWith('.glb')) files.push(join(root, dir, f));
    }
  }
}

const angle = (a, b) => {
  const dot = Math.abs(a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]);
  return (2 * Math.acos(Math.min(1, dot)) * 180) / Math.PI;
};
const quat = (out, i) => [0, 1, 2, 3].map((k) => out[i * 4 + k]);
const vec = (out, i) => [0, 1, 2].map((k) => out[i * 3 + k]);

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const rows = [];
let failed = 0;
for (const file of files) {
  const doc = await io.read(file);
  const model = basename(file, '.glb');
  for (const anim of doc.getRoot().listAnimations()) {
    const clip = anim.getName();
    let duration = 0;
    let keys = 0;
    let seam = { deg: 0, joint: '' };
    let seamStep = 0;
    let hipsTravel = 0;
    let headTravel = 0;
    let drift = 0;
    for (const channel of anim.listChannels()) {
      const sampler = channel.getSampler();
      const node = channel.getTargetNode();
      if (!sampler || !node) continue;
      const times = sampler.getInput().getArray();
      const out = sampler.getOutput().getArray();
      const n = times.length;
      duration = Math.max(duration, times[n - 1]);
      keys = Math.max(keys, n);
      const name = node.getName();
      if (channel.getTargetPath() === 'rotation' && n > 1) {
        const first = quat(out, 0);
        const deg = angle(first, quat(out, n - 1));
        let step = 0;
        let travel = 0;
        for (let i = 1; i < n; i++) {
          step = Math.max(step, angle(quat(out, i - 1), quat(out, i)));
          travel = Math.max(travel, angle(first, quat(out, i)));
        }
        if (deg > seam.deg) {
          seam = { deg, joint: name };
          seamStep = step;
        }
        if (/hips$/i.test(name)) hipsTravel = Math.max(hipsTravel, travel);
        if (/head$/i.test(name)) headTravel = Math.max(headTravel, travel);
      } else if (channel.getTargetPath() === 'translation' && /hips$/i.test(name) && n > 1) {
        const a = vec(out, 0);
        const b = vec(out, n - 1);
        const height = Math.max(1e-6, Math.abs(a[1]));
        drift = Math.hypot(b[0] - a[0], b[2] - a[2]) / height;
      }
    }
    const problems = [];
    if (LOOPS.includes(clip)) {
      if (seam.deg > SEAM_MAX_DEG && seam.deg > seamStep * STEP_FACTOR) {
        problems.push(`pops ${seam.deg.toFixed(1)} deg at ${seam.joint}`);
      }
      if (drift > DRIFT_MAX) problems.push(`root slides ${(drift * 100).toFixed(0)}% of hip height`);
    }
    if (clip === 'idle') {
      if (hipsTravel > IDLE_HIPS_MAX_DEG) problems.push(`hips turn ${hipsTravel.toFixed(0)} deg`);
      if (headTravel > IDLE_HEAD_MAX_DEG) problems.push(`head turns ${headTravel.toFixed(0)} deg`);
    }
    if (problems.length) failed += 1;
    rows.push({
      model, clip, seconds: +duration.toFixed(2), keys,
      seamDeg: +seam.deg.toFixed(1), seamJoint: seam.joint, frameStepDeg: +seamStep.toFixed(1),
      hipsTravelDeg: +hipsTravel.toFixed(1), headTravelDeg: +headTravel.toFixed(1),
      rootDrift: +drift.toFixed(3), loop: LOOPS.includes(clip), problems,
    });
  }
}

if (asJson) {
  console.log(JSON.stringify(rows, null, 1));
} else {
  for (const r of rows) {
    const tag = r.problems.length ? 'FAIL' : (r.loop ? 'ok  ' : '    ');
    console.log(
      `${tag} ${r.model.padEnd(20)} ${r.clip.padEnd(15)} ${String(r.seconds).padStart(5)}s ` +
      `seam ${String(r.seamDeg).padStart(5)} (${r.seamJoint || '-'}, step ${r.frameStepDeg}) ` +
      `hips ${r.hipsTravelDeg} head ${r.headTravelDeg} drift ${r.rootDrift}` +
      (r.problems.length ? `  <- ${r.problems.join('; ')}` : ''));
  }
  console.log(`clip seams: ${rows.length} clips, ${failed} failed`);
}
process.exit(failed ? 1 : 0);
