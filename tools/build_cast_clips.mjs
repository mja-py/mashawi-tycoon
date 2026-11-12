// Animation-only cast repair. Run from any directory; --check never writes.
// Original BIN bytes/accessors are retained, including PNGs, mesh and skin data.
// New animation accessors are appended, without a glTF export/optimizer pass.
// Build metadata lives on idle, so reruns are byte-idempotent and recipe changes
// can rebuild from the original tracks without accumulating previous repairs.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO } from '@gltf-transform/core';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const check = process.argv.includes('--check');
assert(process.argv.slice(2).every(a => a === '--check'), 'Usage: node tools/build_cast_clips.mjs [--check]');
const recipe = createHash('sha256').update(await fs.readFile(fileURLToPath(import.meta.url))).digest('hex');
const customers = ['beach-walker', 'city-commuter', 'creek-abaya', 'creek-kandura',
  'downtown-fashion', 'downtown-tailored', 'jbr-local-swimmer', 'jbr-modest-swimmer', 'souq-man', 'village-evening'];
const io = new NodeIO();
const copy = value => structuredClone(value);
const sizes = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };
const norm = q => q.map(x => x / Math.hypot(...q));
const dot = (a, b) => a.reduce((sum, x, i) => sum + x * b[i], 0);
const add = (a, b) => a.map((x, i) => x + b[i]);
const sub = (a, b) => a.map((x, i) => x - b[i]);
const mul = (a, s) => a.map(x => x * s);
const unit = a => mul(a, 1 / Math.hypot(...a));
const cross = (a, b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
const qmul = (a, b) => [
  a[3]*b[0]+a[0]*b[3]+a[1]*b[2]-a[2]*b[1],
  a[3]*b[1]-a[0]*b[2]+a[1]*b[3]+a[2]*b[0],
  a[3]*b[2]+a[0]*b[1]-a[1]*b[0]+a[2]*b[3],
  a[3]*b[3]-a[0]*b[0]-a[1]*b[1]-a[2]*b[2]];
const inverse = q => [-q[0], -q[1], -q[2], q[3]];
const rotate = (q, v) => qmul(qmul(q, [...v, 0]), inverse(q)).slice(0, 3);
const axis = (v, degrees) => [...mul(v, Math.sin(degrees * Math.PI / 360)), Math.cos(degrees * Math.PI / 360)];
const angle = (a, b) => 2 * Math.acos(Math.min(1, Math.abs(dot(norm(a), norm(b))))) * 180 / Math.PI;
const smooth = u => u*u*u*(10 + u*(-15 + 6*u));
function slerp(a, b, u) {
  a = norm(a); b = norm(b);
  let d = dot(a, b);
  if (d < 0) { b = mul(b, -1); d = -d; }
  if (d > 0.9995) return norm(add(mul(a, 1-u), mul(b, u)));
  const theta = Math.acos(Math.min(1, d));
  return add(mul(a, Math.sin((1-u)*theta)/Math.sin(theta)), mul(b, Math.sin(u*theta)/Math.sin(theta)));
}
function fromTo(a, b) {
  a = unit(a); b = unit(b);
  assert(dot(a, b) > -0.99999, 'Unexpected opposite IK directions');
  return norm([...cross(a, b), 1 + dot(a, b)]);
}

function parse(bytes) {
  assert.equal(bytes.readUInt32LE(0), 0x46546c67);
  assert.equal(bytes.readUInt32LE(4), 2);
  assert.equal(bytes.readUInt32LE(8), bytes.length);
  const jsonLength = bytes.readUInt32LE(12);
  assert.equal(bytes.readUInt32LE(16), 0x4e4f534a);
  const binOffset = 20 + jsonLength;
  assert.equal(bytes.readUInt32LE(binOffset + 4), 0x004e4942);
  assert.equal(binOffset + 8 + bytes.readUInt32LE(binOffset), bytes.length);
  const json = JSON.parse(bytes.subarray(20, binOffset).toString());
  assert.equal(json.buffers.length, 1);
  return { json, bin: bytes.subarray(binOffset + 8) };
}
async function load(relative) { return parse(await fs.readFile(path.join(project, relative))); }
function values(d, index) {
  const a = d.json.accessors[index], view = d.json.bufferViews[a.bufferView];
  assert.equal(a.componentType, 5126, 'Animation accessors must contain floats');
  assert(!a.sparse && !view.byteStride && !a.normalized, 'Expected packed animation accessors');
  const offset = (view.byteOffset || 0) + (a.byteOffset || 0);
  return Array.from({ length: a.count * sizes[a.type] }, (_, i) => d.bin.readFloatLE(offset + 4*i));
}
const duration = (d, a) => Math.max(...a.samplers.map(s => values(d, s.input).at(-1)));
function tracks(d, a) {
  return a.channels.map(c => {
    const s = a.samplers[c.sampler];
    assert(['LINEAR','STEP'].includes(s.interpolation || 'LINEAR'));
    const size = sizes[d.json.accessors[s.output].type];
    const out = values(d, s.output);
    return { node: c.target.node, name: d.json.nodes[c.target.node].name, path: c.target.path, interpolation:s.interpolation || 'LINEAR',
      times: values(d, s.input), rows: Array.from({length: out.length / size}, (_, i) => out.slice(i*size, (i+1)*size)) };
  });
}
function sample(track, time) {
  const { times, rows } = track;
  let hi = times.findIndex(t => t >= time);
  if (hi < 0) return rows.at(-1).slice();
  if (!hi) return rows[0].slice();
  if (track.interpolation === 'STEP' && times[hi] !== time) return rows[hi-1].slice();
  const u = (time-times[hi-1])/(times[hi]-times[hi-1]);
  return track.path === 'rotation' ? slerp(rows[hi-1], rows[hi], u)
    : rows[hi-1].map((x, j) => x*(1-u) + rows[hi][j]*u);
}

// Skeleton calculations are in authored centimetres, beneath Armature's scale.
// Nothing is written back to nodes, skins, inverse bind matrices or meshes.
function serviceArmDirections(d) {
  const pose = d.json.nodes.map(n=>({t:n.translation || [0,0,0],q:n.rotation || [0,0,0,1]}));
  for (const t of tracks(d,d.json.animations[0])) {
    if (t.path==='rotation') pose[t.node].q = norm(t.rows[0]);
    if (t.path==='translation') pose[t.node].t = t.rows[0];
  }
  const world = [], nodes = d.json.nodes;
  function visit(i,parent) {
    world[i] = parent ? {t:add(parent.t,rotate(parent.q,pose[i].t)),q:norm(qmul(parent.q,pose[i].q))} : pose[i];
    for (const child of nodes[i].children || []) visit(child,world[i]);
  }
  visit(nodes.findIndex(n=>n.name==='Hips'),null);
  const result = {};
  for (const side of ['Left','Right']) {
    const [upper,lower,hand] = ['Arm','ForeArm','Hand'].map(part=>nodes.findIndex(n=>n.name===side+part));
    result[side] = [unit(sub(world[lower].t,world[upper].t)),unit(sub(world[hand].t,world[lower].t))];
  }
  return result;
}
function standingFrames(d, armDirections) {
  const nodes = d.json.nodes;
  const hips = nodes.findIndex(n => n.name === 'Hips');
  const skeleton = new Set(d.json.skins[0].joints);
  const base = nodes.map(n => ({ t: (n.translation || [0,0,0]).slice(), q: norm(n.rotation || [0,0,0,1]) }));
  const fk = pose => {
    const world = [];
    function visit(i, parent) {
      const p = pose[i];
      world[i] = parent ? { t: add(parent.t, rotate(parent.q, p.t)), q: norm(qmul(parent.q, p.q)) }
        : { t: p.t.slice(), q: p.q.slice() };
      for (const child of nodes[i].children || []) if (skeleton.has(child)) visit(child, world[i]);
    }
    visit(hips, null);
    return world;
  };
  // Retarget only the relaxed service stance's arm directions, preserving native
  // bone rolls and proportions. A little extra abduction keeps the long sleeves
  // clear of the torso; the native A-pose itself is too wide for a queue idle.
  for (const side of ['Left','Right']) {
    const [shoulder,upper,lower,hand] = ['Shoulder','Arm','ForeArm','Hand'].map(part=>nodes.findIndex(n=>n.name===side+part));
    const [sourceUpper,sourceLower] = armDirections[side];
    const desiredUpper = unit([side==='Left'?0.26:-0.26,sourceUpper[1],sourceUpper[2]]);
    let world = fk(base);
    let desired = norm(qmul(fromTo(sub(world[lower].t,world[upper].t),desiredUpper),world[upper].q));
    base[upper].q = norm(qmul(inverse(world[shoulder].q),desired));
    world = fk(base);
    desired = norm(qmul(fromTo(sub(world[hand].t,world[lower].t),sourceLower),world[lower].q));
    base[lower].q = norm(qmul(inverse(world[upper].q),desired));
  }
  const frames = Array.from({length: 121}, (_, frame) => {
    const u = frame === 120 ? 0 : frame/120; // identical endpoint, including trig rounding
    const phase = 2*Math.PI*u, breath = Math.sin(phase), sway = Math.sin(phase + 0.35);
    const pose = copy(base);
    // Settle the upper body's weight over the support foot through the spine.
    // Lock pelvis and lower body: Godot's existing 15 Hz animation importer can
    // discard sub-degree IK corrections, so animated hip sway would slide feet.
    for (let i = 0; i < nodes.length; i++) {
      const name = nodes[i].name;
      let delta = [0,0,0,1];
      if (name === 'Spine02') delta = qmul(axis([1,0,0], 0.45*breath), axis([0,0,1], -0.45*sway));
      if (name === 'Spine01') delta = axis([1,0,0], 0.55*breath);
      if (name === 'Spine') delta = qmul(axis([1,0,0], 0.35*breath), axis([0,0,1], 0.20*sway));
      if (name === 'neck') delta = axis([1,0,0], -0.3*breath);
      if (name === 'Head') delta = qmul(axis([0,1,0], 1.8*Math.sin(phase-0.6)), axis([0,0,1], 0.35*Math.sin(phase+0.8)));
      if (/^(Left|Right)Shoulder$/.test(name)) delta = axis([1,0,0], 0.20*breath);
      if (/^(Left|Right)Arm$/.test(name)) delta = axis([1,0,0], 0.45*Math.sin(phase+(name.startsWith('Left') ? 0.5 : -0.4)));
      if (/^(Left|Right)ForeArm$/.test(name)) delta = axis([1,0,0], 1.0+0.4*Math.sin(phase-0.3));
      if (/^(Left|Right)Hand$/.test(name)) delta = axis([0,0,1], 0.35*Math.sin(phase+0.6));
      if (i !== hips) pose[i].q = norm(qmul(base[i].q, delta));
    }
    return pose;
  });
  return frames;
}

function writer(d) {
  const chunks = [d.bin];
  let length = d.bin.length;
  const cached = new Map();
  function accessor(rows, type) {
    const bytes = Buffer.alloc(rows.length*sizes[type]*4);
    rows.flat().forEach((v,i) => bytes.writeFloatLE(v, i*4));
    const key = type+':'+createHash('sha256').update(bytes).digest('hex');
    if (cached.has(key)) return cached.get(key);
    assert.equal(length%4, 0);
    const view = d.json.bufferViews.push({buffer: 0, byteOffset: length, byteLength: bytes.length})-1;
    chunks.push(bytes); length += bytes.length;
    const a = {bufferView: view, componentType: 5126, count: rows.length, type};
    if (type === 'SCALAR') { a.min = [Math.min(...rows.flat())]; a.max = [Math.max(...rows.flat())]; }
    const index = d.json.accessors.push(a)-1;
    cached.set(key,index);
    return index;
  }
  function animation(name, ts) {
    const result = { name, channels: [], samplers: [] };
    for (const t of ts) {
      let times = t.times, rows = t.rows;
      // Constant channels still span the complete clip, but need only two keys.
      if (rows.every(row => row.every((v,j) => Math.abs(v-rows[0][j]) < 1e-9))) {
        times = [times[0], times.at(-1)]; rows = [rows[0], rows[0]];
      }
      const type = t.path === 'rotation' ? 'VEC4' : 'VEC3';
      result.channels.push({sampler: result.samplers.length, target: {node:t.node, path:t.path}});
      result.samplers.push({input: accessor(times.map(t => [t]), 'SCALAR'), output: accessor(rows, type), interpolation:t.interpolation || 'LINEAR'});
    }
    return result;
  }
  function finish() {
    d.bin = Buffer.concat(chunks);
    d.json.buffers[0].byteLength = length;
    let json = Buffer.from(JSON.stringify(d.json));
    json = Buffer.concat([json, Buffer.alloc((4-json.length%4)%4, 0x20)]);
    const header = Buffer.alloc(20), binHeader = Buffer.alloc(8);
    header.writeUInt32LE(0x46546c67,0); header.writeUInt32LE(2,4);
    header.writeUInt32LE(28+json.length+length,8);
    header.writeUInt32LE(json.length,12); header.writeUInt32LE(0x4e4f534a,16);
    binHeader.writeUInt32LE(length,0); binHeader.writeUInt32LE(0x004e4942,4);
    return Buffer.concat([header,json,binHeader,d.bin]);
  }
  return {animation, finish};
}

function closeLoop(ts, length) {
  return ts.map(t => {
    const first = t.rows[0], last = t.rows.at(-1);
    return {...t, rows: t.rows.map((row,i) => {
      if (!i || i === t.rows.length-1) return first.slice();
      const u = smooth(t.times[i]/length);
      // Distribute the small endpoint correction through the full cycle; no
      // one-frame snap or artificial pause at the carry gait's contact seam.
      if (t.path === 'rotation') return norm(qmul(row, slerp([0,0,0,1], qmul(inverse(norm(last)),norm(first)),u)));
      return row.map((x,j) => x + (first[j]-last[j])*u);
    })};
  });
}
function seatedLoop(ts, length) {
  return ts.map(t => {
    // Preserve every source pose value, including hips Y and every leg key.
    // Inverse cosine timestamps ease the existing motion to a stop at each
    // turnaround. Reversing the same path then closes all channels exactly.
    const forward = t.times.map(time => length/Math.PI*Math.acos(Math.max(-1,Math.min(1,1-2*time/length))));
    return {...t, times: [...forward, ...forward.slice(0,-1).reverse().map(time => 2*length-time)],
      rows: [...t.rows.map(row=>row.slice()), ...t.rows.slice(0,-1).reverse().map(row=>row.slice())]};
  });
}

function assertLoop(ts, name, limit) {
  for (const t of ts) {
    if (t.path === 'rotation') {
      assert(angle(t.rows[0], t.rows.at(-1)) < limit, `${name}: ${t.name} seam`);
      for (const q of t.rows) assert(Math.abs(Math.hypot(...q)-1) < 1e-5, `${name}: non-unit quaternion`);
    } else assert(Math.hypot(...sub(t.rows[0],t.rows.at(-1))) < 1e-5, `${name}: ${t.name} translation/scale seam`);
  }
}
function verifyFootPins(d) {
  const nodes = d.json.nodes, skeleton = new Set(d.json.skins[0].joints);
  const hips = nodes.findIndex(n=>n.name==='Hips');
  const ts = tracks(d,d.json.animations.find(a=>a.name==='idle'));
  const pins = [];
  let maximum = 0;
  // Check quantized, interpolated output at 60 Hz, including between baked keys.
  for (let frame=0; frame<=240; frame++) {
    const pose = nodes.map(n=>({t:n.translation||[0,0,0],q:n.rotation||[0,0,0,1],s:n.scale||[1,1,1]}));
    for (const t of ts) pose[t.node][{translation:'t',rotation:'q',scale:'s'}[t.path]] = sample(t,frame/60);
    function visit(i,parent) {
      const p = pose[i];
      const world = parent ? {t:add(parent.t,rotate(parent.q,p.t.map((v,j)=>v*parent.s[j]))),
        q:norm(qmul(parent.q,p.q)),s:p.s.map((v,j)=>v*parent.s[j])} : p;
      if (/^(Left|Right)(Foot|ToeBase)$/.test(nodes[i].name)) {
        if (!frame) pins[i] = world;
        maximum = Math.max(maximum,Math.hypot(...sub(world.t,pins[i].t)));
        assert(angle(world.q,pins[i].q)<0.001, 'Interpolated sole orientation drift');
      }
      for (const child of nodes[i].children || []) if (skeleton.has(child)) visit(child,world);
    }
    visit(hips,null);
  }
  assert(maximum<0.001, `Interpolated foot drift ${maximum*10} mm exceeds 0.01 mm`);
  return maximum*10;
}
function assertPreserved(before, after, changed) {
  const original = copy(before.json), result = copy(after.json);
  delete original.animations; delete result.animations;
  result.accessors = result.accessors.slice(0,original.accessors.length);
  result.bufferViews = result.bufferViews.slice(0,original.bufferViews.length);
  result.buffers = copy(original.buffers);
  assert.deepEqual(result, original, 'Non-animation glTF properties changed');
  assert(after.bin.subarray(0,before.bin.length).equals(before.bin), 'Original BIN data changed');
  for (const a of before.json.animations.filter(a=>!changed.includes(a.name))) {
    assert.deepEqual(after.json.animations.find(b=>b.name===a.name),a, `${a.name} changed`);
  }
}

let totalBefore = 0, totalAfter = 0;
// Build and validate every result before writing any model.
const results = [];
const armDirections = serviceArmDirections(await load('raw/restaurant-service/server-idle.glb'));
for (const id of [...customers.map(id=>'customers/'+id), 'crew/filipina-server']) {
  const relative = 'assets/models/'+id+'.glb', file = path.join(project, relative);
  const bytes = await fs.readFile(file), original = parse(bytes), d = parse(bytes);
  const server = id.startsWith('crew/');
  const changed = server ? ['idle','carry'] : ['idle','sit','glance'];
  const metadata = d.json.animations.find(a=>a.name==='idle').extras?.buildCastClips;
  if (metadata?.recipe === recipe) {
    for (const name of changed) assertLoop(tracks(d,d.json.animations.find(a=>a.name===name)),name,1);
    if (!server) verifyFootPins(d);
    // Also require glTF-Transform to parse the shipped result successfully.
    await io.readBinary(new Uint8Array(bytes));
    totalBefore += bytes.length; totalAfter += bytes.length;
    console.log(`${id}: already current, ${bytes.length} bytes`);
    continue;
  }
  if (metadata) {
    d.json.animations = d.json.animations.filter(a=>!changed.includes(a.name));
    d.json.animations.push(...metadata.originalAnimations);
    d.json.animations.sort((a,b)=>metadata.order.indexOf(a.name)-metadata.order.indexOf(b.name));
    d.json.accessors.length = metadata.accessors;
    d.json.bufferViews.length = metadata.bufferViews;
    d.json.buffers[0].byteLength = metadata.bufferLength;
    d.bin = d.bin.subarray(0,metadata.binLength);
  }
  const base = {json:copy(d.json), bin:d.bin};
  const build = { recipe, accessors:d.json.accessors.length, bufferViews:d.json.bufferViews.length,
    bufferLength:d.json.buffers[0].byteLength, binLength:d.bin.length,
    order:d.json.animations.map(a=>a.name), originalAnimations:copy(d.json.animations.filter(a=>changed.includes(a.name))) };
  const w = writer(d);
  let contact = '';
  function replace(name, ts) {
    assertLoop(ts,name,1);
    const a = w.animation(name,ts), index = d.json.animations.findIndex(a=>a.name===name);
    if (index < 0) d.json.animations.push(a); else d.json.animations[index] = a;
  }
  if (server) {
    for (const name of changed) {
      const a = d.json.animations.find(a=>a.name===name);
      replace(name,closeLoop(tracks(base,a),duration(base,a)));
    }
  } else {
    const frames = standingFrames(d,armDirections);
    const idle = d.json.animations.find(a=>a.name==='idle');
    const idleTracks = tracks(base,idle).map(t=>({...t,interpolation:'LINEAR',times:frames.map((_,i)=>i/30),
      rows:frames.map(frame=>t.path==='rotation' ? frame[t.node].q : t.path==='translation' ? frame[t.node].t : [1,1,1])}));
    replace('idle',idleTracks);
    const sit = d.json.animations.find(a=>a.name==='sit');
    replace('sit',seatedLoop(tracks(base,sit),duration(base,sit)));
    const name = path.basename(id);
    const sourcePath = name === 'souq-man' ? 'raw/souq-customers/souq-man-animation.glb'
      : `raw/${['beach-walker','city-commuter','creek-abaya','creek-kandura'].includes(name)?'area-cast':'evening-cast'}/${name}-animation.glb`;
    const source = await load(sourcePath), sourceIdle = source.json.animations.find(a=>a.name==='Idle');
    assert(sourceIdle, `${sourcePath}: missing uncut Idle`);
    assert(Math.abs(duration(source,sourceIdle)-4) < 0.001, 'Expected complete four-second look-around');
    const nodes = new Map(d.json.nodes.map((n,i)=>[n.name,i]));
    const oldHips = tracks(base,idle).find(t=>t.name==='Hips'&&t.path==='translation').rows[0];
    const glance = tracks(source,sourceIdle).map(t=> {
      assert(nodes.has(t.name), `Unmapped glance joint ${t.name}`);
      const out = {...t,node:nodes.get(t.name)};
      // Keep each shipped model's original ground placement, not raw root motion.
      if (t.name==='Hips'&&t.path==='translation') {
        const offset = sub(oldHips,t.rows[0]);
        out.rows = t.rows.map(row=>add(row,offset));
      }
      out.rows = out.rows.map(row=>t.path==='rotation'?norm(row):row.slice());
      // The sources close already; duplicate first values to remove float noise.
      assert(t.path!=='rotation'||angle(out.rows[0],out.rows.at(-1))<0.1, 'Unclosed glance source');
      out.rows[out.rows.length-1] = out.rows[0].slice();
      return out;
    });
    replace('glance',glance);
  }
  d.json.animations.find(a=>a.name==='idle').extras = { buildCastClips:build };
  const output = w.finish(), after = parse(output);
  assertPreserved(base,after,changed);
  // Same meshes/skins/materials/textures/untouched tracks as the input, even on rebuild.
  if (!metadata) assertPreserved(original,after,changed);
  assert(output.length < 1500000, `${id} exceeds the cast size budget`);
  const decoded = await io.readBinary(new Uint8Array(output));
  for (const name of changed) assert(decoded.getRoot().listAnimations().some(a=>a.getName()===name));
  for (const name of changed) assertLoop(tracks(after,after.json.animations.find(a=>a.name===name)),name,1);
  if (!server) contact = `; planted-foot error ${verifyFootPins(after).toFixed(6)} mm`;
  totalBefore += bytes.length; totalAfter += output.length;
  console.log(`${id}: ${bytes.length} -> ${output.length} bytes; ${changed.join(', ')}${contact}${check?' (would write)':''}`);
  results.push({file,output});
}
if (!check) for (const {file,output} of results) await fs.writeFile(file,output);
console.log(`${check?'CHECK':'BUILD'}: ${results.length} models ${check?'would change':'written'}; ${totalBefore} -> ${totalAfter} bytes; original art and other motion bytes preserved`);
