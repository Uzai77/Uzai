// Schwere Netze vereinfachen (meshoptimizer), Texturen kleiner: für Deko, die nie groß im Bild steht.
//   node tools/glb_vereinfachen.mjs <ein.glb> <aus.glb> [anteil] [maxTex] [fehler]
// Braucht @gltf-transform/core, /extensions, /functions 4.1.1, meshoptimizer und sharp (npm).
// Schwere Netze vereinfachen (meshoptimizer), Texturen kleiner: für Deko, die nie groß im Bild steht.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';
const [ein, aus, ratioArg, maxTexArg, errArg] = process.argv.slice(2);
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(ein);
await doc.transform(weld(), simplify({ simplifier: MeshoptSimplifier, ratio: parseFloat(ratioArg || '0.4'), error: parseFloat(errArg || '0.002') }), dedup(), prune(),
	textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [parseInt(maxTexArg || '512', 10), parseInt(maxTexArg || '512', 10)], quality: 84 }), prune());
await io.write(aus, doc);
let v = 0;
for (const m of doc.getRoot().listMeshes()) for (const p of m.listPrimitives()) v += p.getAttribute('POSITION').getCount();
console.log(`${aus}: Eckpunkte ${v}`);
