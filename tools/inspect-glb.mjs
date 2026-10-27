import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { getBounds } from '@gltf-transform/core';
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
for (const f of process.argv.slice(2)) {
  const doc = await io.read(f);
  const root = doc.getRoot();
  const scene = root.listScenes()[0];
  const b = getBounds(scene);
  const size = b.max.map((v,i)=> +(v-b.min[i]).toFixed(2));
  const anims = root.listAnimations().map(a=>a.getName());
  const skins = root.listSkins().length;
  const tris = root.listMeshes().reduce((s,m)=>s+m.listPrimitives().reduce((t,p)=>t+(p.getIndices()?p.getIndices().getCount()/3:p.getAttribute('POSITION').getCount()/3),0),0);
  const tex = root.listTextures().length;
  const uris = root.listTextures().map(t=>t.getURI()||'(embedded '+t.getMimeType()+')'); console.log(uris, f.split('/').slice(-3).join('/'), 'size', size, 'min', b.min.map(v=>+v.toFixed(2)), 'tris', Math.round(tris), 'tex', tex, 'skins', skins, 'anims', anims);
}
