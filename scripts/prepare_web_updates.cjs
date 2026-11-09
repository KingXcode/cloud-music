#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const output = path.resolve(process.argv[2] || 'build/web');
const root = path.resolve(__dirname, '..');
const buildsDirectory = 'cloud-music-builds';
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
function walk(directory, prefix = '') {
  return fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name)).flatMap(entry => {
    if (!prefix && [buildsDirectory, 'cloud-music-release.json', '.last_build_id'].includes(entry.name)) return [];
    if (entry.isSymbolicLink()) throw Error('Refusing a symbolic link in web output: ' + entry.name);
    const name = prefix + entry.name;
    return entry.isDirectory() ? walk(path.join(directory, entry.name), name + '/') : [name];
  });
}
const version = JSON.parse(fs.readFileSync(path.join(output, 'version.json'), 'utf8'));
if (!version.version || !version.build_number) throw Error('Flutter version.json is missing version/build_number.');
const originalIndex = fs.readFileSync(path.join(output, 'index.html'), 'utf8');
if (!originalIndex.includes('<!-- CLOUD_MUSIC_BUILD -->')) throw Error('Expected a fresh Flutter build with CLOUD_MUSIC_BUILD marker.');
const baseMatch = originalIndex.match(/<base href="([^"]+)"\s*\/?\s*>/i);
if (!baseMatch || !baseMatch[1].startsWith('/') || !baseMatch[1].endsWith('/') || /[?#<>"\\]/.test(baseMatch[1]) || baseMatch[1].startsWith('//')) {
  throw Error('Build with an absolute same-origin --base-href ending in /.');
}
const base = baseMatch[1];
const bootstrap = fs.readFileSync(path.join(output, 'flutter_bootstrap.js'), 'utf8');
// Flutter's embedded loader implementation mentions serviceWorkerSettings even
// when the application does not pass it. Inspect the final app startup call.
const startup = bootstrap.slice(bootstrap.lastIndexOf('_flutter.loader.load('));
if (!startup.startsWith('_flutter.loader.load(') || /serviceWorkerSettings\s*:/.test(startup) || !startup.includes('canvasKitBaseUrl:')) {
  throw Error('Expected custom bootstrap without Flutter service worker and with local CanvasKit.');
}
if (!fs.existsSync(path.join(output, 'canvaskit'))) throw Error('Build must contain local CanvasKit resources.');
const paths = walk(output).filter(name => name !== 'flutter_service_worker.js');
const digest = crypto.createHash('sha256');
for (const name of paths) digest.update(name + '\0').update(hash(fs.readFileSync(path.join(output, name))));
digest.update(fs.readFileSync(path.join(root, 'web/flutter_service_worker.js')));
digest.update(fs.readFileSync(path.join(root, 'web/update_retention.js')));
const id = digest.digest('hex');
const target = path.join(output, buildsDirectory, id);
const metadata = { id, version: version.version, build: version.build_number, base };
const encoded = JSON.stringify(metadata).replace(/</g, '\\u003c');
const index = originalIndex.replace(baseMatch[0], `<base href="${base}${buildsDirectory}/${id}/">`)
  .replace('<!-- CLOUD_MUSIC_BUILD -->', `<script>window.CLOUD_MUSIC_BUILD = ${encoded};</script>`);
const resources = [];
for (const name of paths) {
  const bytes = name === 'index.html' ? Buffer.from(index) : fs.readFileSync(path.join(output, name));
  const destination = path.join(target, name);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, bytes);
  resources.push({ path: name, size: bytes.length, sha256: hash(bytes) });
}
const manifest = { schema: 1, id, version: version.version, build: version.build_number,
  notes: '网页新版已准备好。下载期间可以继续播放，完成后由您确认重新载入。',
  totalBytes: resources.reduce((sum, resource) => sum + resource.size, 0), resources };
// Apply the same runtime validation in the publisher, before publishing its pointer.
const context = { globalThis: null }; context.globalThis = context;
require('node:vm').runInNewContext(fs.readFileSync(path.join(root, 'web/update_core.js'), 'utf8'), context);
context.CloudMusicUpdateCore.validateManifest(manifest);
fs.writeFileSync(path.join(output, 'flutter_service_worker.js'),
  fs.readFileSync(path.join(root, 'web/update_core.js'), 'utf8') + '\n' +
  fs.readFileSync(path.join(root, 'web/update_retention.js'), 'utf8') + '\n' +
  fs.readFileSync(path.join(root, 'web/flutter_service_worker.js'), 'utf8'));
fs.writeFileSync(path.join(output, 'index.html'), index);
fs.writeFileSync(path.join(output, 'cloud-music-release.json'), JSON.stringify(manifest));
console.log(`Prepared web update ${version.version}+${version.build_number}, ${resources.length} resources, ${manifest.totalBytes} bytes, ${id}`);
