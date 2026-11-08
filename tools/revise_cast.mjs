// Restore texture detail from the authored sources. Preserve every rig and motion.
// node tools/revise_cast.mjs --apply (raw sources stay outside the shipped project)
import { NodeIO } from '@gltf-transform/core';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const sharp = require('sharp');
const io = new NodeIO();
const project = new URL('../', import.meta.url).pathname;
const profiles = [
  ['crew/filipina-server', 'restaurant-service/server-rigged', 768],
  ['customers/souq-man', 'souq-customers/souq-man-rigged', 768],
  ...['creek-kandura','creek-abaya','beach-walker','city-commuter'].map(id=>['customers/'+id,'area-cast/'+id+'-rigged',768]),
  ...['jbr-modest-swimmer','jbr-local-swimmer','village-evening','downtown-fashion','downtown-tailored'].map(id=>['customers/'+id,'evening-cast/'+id+'-rigged',768]),
];
function geometryAndMotion(doc) {
  const hash = createHash('sha256');
  // Images are deliberately excluded: geometry, skinning, UVs and motions must survive.
  for(const accessor of doc.getRoot().listAccessors()) hash.update(new Uint8Array(accessor.getArray().buffer,accessor.getArray().byteOffset,accessor.getArray().byteLength));
  return hash.digest('hex');
}
let before = 0, after = 0;
for(const [id,source,edge] of profiles) {
  const file = path.join(project,'assets/models',id+'.glb');
  const document = await io.read(file);
  const root = document.getRoot();
  if(process.argv.includes('--apply')) {
    const original = await io.read(path.join(project,'raw',source+'.glb'));
    assert.equal(root.listTextures().length,1,id+' has a single material atlas');
    const texture = original.getRoot().listTextures()[0];
    const image = await sharp(texture.getImage()).resize(edge,edge,{kernel:'lanczos3'}).jpeg({quality:84,mozjpeg:true}).toBuffer();
    const contract = geometryAndMotion(document);
    root.listTextures()[0].setImage(image).setMimeType('image/jpeg');
    for(const material of root.listMaterials()) {
      material.setMetallicFactor(0).setRoughnessFactor(0.88);
      material.getBaseColorTextureInfo().setMagFilter(9729).setMinFilter(9987);
    }
    assert.equal(geometryAndMotion(document),contract,id+' rig and animation unchanged');
    before += (await fs.stat(file)).size;
    const bytes = await io.writeBinary(document);
    assert(bytes.byteLength <= 1500000,id+' exceeds 1.5 MB');
    await fs.writeFile(file,bytes);
    // These three atlases are explicitly tracked; keep Godot's extracted copy in sync.
    if(id.startsWith('crew/')) await fs.writeFile(file.replace('.glb','_Material_0_baseColor.jpg'),image);
  }
  const bytes = (await fs.stat(file)).size;
  after += bytes;
  assert(bytes<=1500000,id+' exceeds budget');
  const triangles = root.listMeshes().reduce((sum,mesh)=>sum+mesh.listPrimitives().reduce((n,p)=>n+p.getIndices().getCount()/3,0),0);
  assert(triangles<10000,id+' exceeds geometry budget');
  assert.equal(root.listSkins().length,1,id+' has one rig');
  assert.deepEqual(root.listTextures()[0].getSize(),[edge,edge],id+' uses the cast atlas profile');
  assert(root.listAnimations().some(a=>a.getName()==='idle') && root.listAnimations().some(a=>a.getName()==='walk'),id+' has idle and walk');
  console.log(`${id}: ${(bytes/1000000).toFixed(3)} MB, ${triangles} triangles, ${edge}px`);
}
console.log(`Cast budget PASS: ${profiles.length} models, ${(after/1000000).toFixed(2)} MB total${before ? ` (was ${(before/1000000).toFixed(2)} MB)` : ''}`);
