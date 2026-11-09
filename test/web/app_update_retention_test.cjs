const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const source = fs.readFileSync('web/update_retention.js', 'utf8');
const base = 'https://music.test/cloud-music/';
const prefix = 'cloud-music-updates-v1:' + base + ':';
const id = character => character.repeat(64);
const json = value => new Response(JSON.stringify(value));
const key = value => new URL('.cloud-music-update-state/' + value, base).href;
class CacheStorage {
  constructor() { this.stores = new Map(); }
  async open(name) {
    if (!this.stores.has(name)) this.stores.set(name, new Map());
    const data = this.stores.get(name);
    const url = request => typeof request === 'string' ? request : request.url;
    return {
      async put(request, response) { data.set(url(request), response.clone()); },
      async match(request) { return data.get(url(request))?.clone(); },
      async keys() { return [...data.keys()].map(url => new Request(url)); },
      async delete(request) { return data.delete(url(request)); },
    };
  }
  async keys() { return [...this.stores.keys()]; }
  async delete(name) { return this.stores.delete(name); }
}
function harness(live = []) {
  const caches = new CacheStorage(), calls = [];
  let now = 100000;
  const context = { URL, Date: { now: () => now } }; context.globalThis = context;
  vm.runInNewContext(source, context);
  const clients = { async matchAll(options) { calls.push(options); return live; } };
  async function metadata(path, value) { await (await caches.open(prefix + 'metadata')).put(key(path), json(value)); }
  async function getMetadata(path) { const response = await (await caches.open(prefix + 'metadata')).match(key(path)); return response ? response.json() : null; }
  async function stage(name) {
    const cacheName = prefix + 'stage:' + name;
    await (await caches.open(cacheName)).put(key('complete'), json({ complete: true }));
    return cacheName;
  }
  async function installed(character, installedAt = 0, version = '1.0.0', build = '1') {
    const descriptor = { id: id(character), cacheName: await stage(character), installedAt, manifest: { version, build } };
    await metadata('build/' + descriptor.id, descriptor);
    return descriptor;
  }
  async function register(client, character) { await metadata('client/' + encodeURIComponent(client), { id: id(character) }); }
  async function prune(protectedCacheNames = []) { return context.CloudMusicUpdateRetention.prune({ cachePrefix: prefix, appBase: base, caches, clients, protectedCacheNames }); }
  return { caches, clients, calls, metadata, getMetadata, stage, installed, register, prune, time: value => { now = value; } };
}
test('retains active, every live running build, and only newest inactive previous build', async () => {
  const h = harness([{ id: 'old-tab', url: base }, { id: 'current-tab', url: base }]);
  const a = await h.installed('a', 10), b = await h.installed('b', 20), c = await h.installed('c', 30), d = await h.installed('d', 40);
  await h.metadata('active', d); await h.register('old-tab', 'a'); await h.register('current-tab', 'd');
  const result = await h.prune();
  assert.equal(result.keptBuilds, 3); assert.equal(result.deletedCaches, 1);
  assert.equal(await h.getMetadata('build/' + b.id), null);
  for (const keep of [a, c, d]) assert.ok((await h.caches.keys()).includes(keep.cacheName));
  assert.equal(result.conservative, false);
  assert.equal(h.calls[0].type, 'window'); assert.equal(h.calls[0].includeUncontrolled, true);
});
test('closed tabs release old installed builds and stale ready/download/client metadata', async () => {
  const h = harness([{ id: 'current', url: base }]);
  const a = await h.installed('a', 1), b = await h.installed('b', 2), c = await h.installed('c', 3);
  await h.metadata('active', c); await h.register('current', 'c'); await h.register('closed/tab', 'a');
  const ready = await h.stage('closed-ready'), download = await h.stage('closed-download');
  await h.metadata('ready/' + encodeURIComponent('closed/tab'), { id: b.id, cacheName: ready });
  await h.metadata('download/' + encodeURIComponent('closed/tab'), { cacheName: download });
  const result = await h.prune();
  assert.equal(result.deletedCaches, 3); assert.equal(result.deletedMetadata, 4);
  assert.equal(await h.getMetadata('client/closed%2Ftab'), null);
  assert.equal(await h.getMetadata('ready/closed%2Ftab'), null);
  assert.equal(await h.getMetadata('download/closed%2Ftab'), null);
  assert.ok(!(await h.caches.keys()).includes(a.cacheName));
});
test('preserves live ready and persistent download stages plus explicitly protected caches', async () => {
  const h = harness([{ id: 'live', url: base }]); await h.register('live', 'a');
  const active = await h.installed('a', 1); await h.metadata('active', active);
  const ready = await h.stage('ready'), download = await h.stage('downloading'), protectedCache = await h.stage('protected');
  const orphan = await h.stage('sealed-orphan');
  await h.metadata('ready/live', { id: id('b'), cacheName: ready });
  await h.metadata('download/live', { cacheName: download });
  await h.prune(new Set([protectedCache]));
  const names = await h.caches.keys();
  for (const keep of [ready, download, protectedCache, active.cacheName]) assert.ok(names.includes(keep));
  assert.ok(!names.includes(orphan));
});
test('unregistered live app tab conservatively keeps installed builds but not orphaned stages', async () => {
  const h = harness([{ id: 'legacy', url: base }]);
  const builds = await Promise.all(['a', 'b', 'c', 'd'].map((character, index) => h.installed(character, index + 1)));
  await h.metadata('active', builds[3]); const orphan = await h.stage('orphan');
  const result = await h.prune();
  assert.equal(result.conservative, true); assert.equal(result.keptBuilds, 4);
  for (const build of builds) assert.ok((await h.caches.keys()).includes(build.cacheName));
  assert.ok(!(await h.caches.keys()).includes(orphan));
  await h.register('legacy', 'd');
  assert.equal((await h.prune()).keptBuilds, 2);
});
test('other app clients and unrelated caches or metadata are never removed or protected implicitly', async () => {
  const h = harness([{ id: 'other', url: 'https://music.test/cloud-music-other/' }, { id: 'external', url: 'https://elsewhere.test/cloud-music/' }]);
  const a = await h.installed('a', 1), b = await h.installed('b', 2), c = await h.installed('c', 3); await h.metadata('active', c);
  const foreignName = 'cloud-music-updates-v1:https://music.test/another/:stage:keep';
  await h.caches.open(foreignName); await h.caches.open('flutter-app-cache');
  const metadata = await h.caches.open(prefix + 'metadata');
  await metadata.put('https://music.test/another/.cloud-music-update-state/ready/other', json({ cacheName: foreignName }));
  await h.metadata('ready/closed', { cacheName: foreignName });
  const result = await h.prune();
  assert.equal(result.conservative, false);
  assert.ok(!(await h.caches.keys()).includes(a.cacheName));
  assert.ok((await h.caches.keys()).includes(b.cacheName));
  assert.ok((await h.caches.keys()).includes(foreignName));
  assert.ok((await h.caches.keys()).includes('flutter-app-cache'));
  assert.ok(await metadata.match('https://music.test/another/.cloud-music-update-state/ready/other'));
});
test('ordering falls back to semantic version/build when old descriptors lack timestamps', async () => {
  const h = harness();
  const a = await h.installed('a', 0, '1.9.0', '100'), b = await h.installed('b', 0, '1.10.0', '2'), c = await h.installed('c', 0, '1.10.0', '10'), d = await h.installed('d', 0, '2.0.0', '1');
  await h.metadata('active', d); await h.prune();
  const names = await h.caches.keys();
  assert.ok(!names.includes(a.cacheName)); assert.ok(!names.includes(b.cacheName));
  assert.ok(names.includes(c.cacheName)); assert.ok(names.includes(d.cacheName));
});
test('timestamp order keeps the most recently installed previous build and repeated cleanup is idempotent', async () => {
  const h = harness();
  const a = await h.installed('a', 30, '1.0.0'), b = await h.installed('b', 20, '2.0.0'), c = await h.installed('c', 40, '3.0.0');
  await h.metadata('active', c); await h.prune();
  assert.ok((await h.caches.keys()).includes(a.cacheName)); assert.ok(!(await h.caches.keys()).includes(b.cacheName));
  const second = await h.prune(); assert.equal(second.deletedCaches, 0); assert.equal(second.deletedMetadata, 0);
});
test('client enumeration failure and corrupt live metadata defer unsafe eviction', async () => {
  const failed = harness(); await failed.installed('a'); const failedOrphan = await failed.stage('orphan');
  failed.clients.matchAll = async () => { throw Error('browser unavailable'); };
  const skipped = await failed.prune(); assert.equal(skipped.skipped, 'clients-unavailable'); assert.ok((await failed.caches.keys()).includes(failedOrphan));
  for (const badPath of ['active', 'build/' + id('a'), 'ready/live', 'download/live']) {
    const h = harness([{ id: 'live', url: base }]); await h.register('live', 'a');
    const active = await h.installed('a'); await h.metadata('active', active); const orphan = await h.stage('possibly-live');
    await (await h.caches.open(prefix + 'metadata')).put(key(badPath), new Response('{corrupt'));
    const result = await h.prune(); assert.equal(result.conservative, true); assert.ok((await h.caches.keys()).includes(orphan));
  }
});
test('publisher embeds retention before worker code and fingerprints changes to it', () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'cloud-update-retention-'));
  try {
    fs.mkdirSync(path.join(folder, 'canvaskit'));
    fs.writeFileSync(path.join(folder, 'canvaskit', 'canvaskit.wasm'), 'engine');
    fs.writeFileSync(path.join(folder, 'index.html'), '<base href="/cloud-music/">\n<!-- CLOUD_MUSIC_BUILD -->');
    fs.writeFileSync(path.join(folder, 'flutter_bootstrap.js'), "_flutter.loader.load({config:{canvasKitBaseUrl: 'canvaskit/'}});");
    fs.writeFileSync(path.join(folder, 'version.json'), JSON.stringify({ version: '0.6.0', build_number: '8' }));
    execFileSync(process.execPath, ['scripts/prepare_web_updates.cjs', folder]);
    const worker = fs.readFileSync(path.join(folder, 'flutter_service_worker.js'), 'utf8');
    assert.ok(worker.includes('root.CloudMusicUpdateRetention = { prune }'));
    assert.ok(worker.indexOf('root.CloudMusicUpdateRetention') < worker.indexOf('const updateCore ='));
    const publisher = fs.readFileSync('scripts/prepare_web_updates.cjs', 'utf8');
    assert.ok(publisher.includes("digest.update(fs.readFileSync(path.join(root, 'web/update_retention.js')))"));
  } finally { fs.rmSync(folder, { recursive: true, force: true }); }
});
test('reserved navigation client retains its selected build until bounded grace expires', async () => {
  const h = harness([{ id: 'current', url: base }]);
  const a = await h.installed('a', 1), b = await h.installed('b', 2), c = await h.installed('c', 3), d = await h.installed('d', 4);
  await h.metadata('active', d); await h.register('current', 'd');
  await h.metadata('client/reserved', { id: a.id, pendingUntil: 130000 });
  const result = await h.prune();
  assert.equal(result.keptBuilds, 3); assert.equal(result.conservative, false);
  assert.ok((await h.caches.keys()).includes(a.cacheName));
  assert.ok(!(await h.caches.keys()).includes(b.cacheName));
  assert.ok(await h.getMetadata('client/reserved'));
  h.time(130001);
  await h.prune();
  assert.equal(await h.getMetadata('client/reserved'), null);
  assert.ok(!(await h.caches.keys()).includes(a.cacheName));
  for (const keep of [c, d]) assert.ok((await h.caches.keys()).includes(keep.cacheName));
});
test('navigation grace cannot preserve an absent client indefinitely or exceed sixty seconds', async () => {
  for (const pendingUntil of [100000, 99999, 160001, Number.MAX_SAFE_INTEGER, '130000']) {
    const h = harness(), a = await h.installed('a', 1), b = await h.installed('b', 2), c = await h.installed('c', 3);
    await h.metadata('active', c); await h.metadata('client/reserved', { id: a.id, pendingUntil });
    await h.prune();
    assert.equal(await h.getMetadata('client/reserved'), null);
    assert.ok(!(await h.caches.keys()).includes(a.cacheName));
    assert.ok((await h.caches.keys()).includes(b.cacheName));
  }
  const h = harness(), a = await h.installed('a', 1), b = await h.installed('b', 2), c = await h.installed('c', 3);
  await h.metadata('active', c); await h.metadata('client/reserved', { id: a.id, pendingUntil: 160000 });
  await h.prune(); assert.ok((await h.caches.keys()).includes(a.cacheName));
  // Once the browser exposes the page and hello registers it, the live page
  // remains protected after the old navigation lease would have expired.
  h.clients.matchAll = async () => [{ id: 'reserved', url: base }];
  await h.register('reserved', 'a'); h.time(170000); await h.prune();
  assert.ok((await h.caches.keys()).includes(a.cacheName)); assert.ok((await h.caches.keys()).includes(b.cacheName));
});
