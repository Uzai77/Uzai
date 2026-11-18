// Fremde glTF-Modelle (Khronos glTF-Sample-Assets, CC0 bzw. CC-BY 4.0) für Uzai umpacken:
// Beschriftungen (Herstelleretiketten), Lichter und Animationen entfernen, Texturen auf höchstens
// 1024 Punkte verkleinern und als WebP speichern, Doppeltes zusammenlegen. Form und Material bleiben.
//   node tools/glb_umpacken.mjs <ein.glb> <aus.glb> [maxTex] [entfernen:namen,durch,komma] [skalierung]
// Braucht @gltf-transform/core, /extensions, /functions 4.1.1 und sharp (npm), siehe assets/zimmer/LIZENZ.txt.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, textureCompress, resample, flatten } from '@gltf-transform/functions';
import sharp from 'sharp';

const [ein, aus, maxTexArg, entfernenArg, skalArg] = process.argv.slice(2);
const maxTex = parseInt(maxTexArg || '1024', 10);
const entfernen = (entfernenArg || 'label,firefly,light').split(',').filter((s) => s.length > 0);
const skal = parseFloat(skalArg || '1');

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(ein);
const root = doc.getRoot();

// Knoten mit Etiketten, Glühwürmchen usw. entfernen (samt Netzen).
for (const node of root.listNodes()) {
	const n = (node.getName() || '').toLowerCase();
	if (entfernen.some((e) => n.includes(e))) {
		node.dispose();
	}
}
for (const mesh of root.listMeshes()) {
	const n = (mesh.getName() || '').toLowerCase();
	if (entfernen.some((e) => n.includes(e))) {
		mesh.dispose();
	}
}
// Punktlichter und Animationen: Uzai setzt eigene.
for (const light of root.listExtensionsUsed().flatMap((e) => (e.extensionName === 'KHR_lights_punctual' ? e.listProperties() : []))) {
	light.dispose();
}
for (const anim of root.listAnimations()) {
	anim.dispose();
}
if (skal !== 1) {
	for (const scene of root.listScenes()) {
		for (const child of scene.listChildren()) {
			const s = child.getScale();
			child.setScale([s[0] * skal, s[1] * skal, s[2] * skal]);
		}
	}
}
await doc.transform(
	dedup(),
	prune(),
	textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [maxTex, maxTex], quality: 86 }),
	prune(),
);
await io.write(aus, doc);
const t = root.listTextures().map((x) => `${x.getName() || '?'}:${x.getMimeType()}`);
console.log(`${aus}: Netze ${root.listMeshes().length}, Materialien ${root.listMaterials().length}, Texturen ${t.length}, Erweiterungen ${root.listExtensionsUsed().map((e) => e.extensionName).join(' ')}`);
