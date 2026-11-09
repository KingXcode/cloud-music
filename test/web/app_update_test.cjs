const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const { webcrypto, createHash } = require('node:crypto');
const { execFileSync } = require('node:child_process');
const coreSource = fs.readFileSync('web/update_core.js', 'utf8');
const retentionSource = fs.readFileSync('web/update_retention.js', 'utf8');
const workerSource = fs.readFileSync('web/flutter_service_worker.js', 'utf8');
const pageSource = fs.readFileSync('web/app_updates.js', 'utf8');
const base = 'https://music.test/cloud-music/';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
function release(label = 'new') {
  const files = { 'index.html': Buffer.from('<html>' + label + '</html>'), 'flutter_bootstrap.js': Buffer.from(label + '-bootstrap'), 'main.dart.js': Buffer.from(label + '-compiled-app') };
  const resources = Object.entries(files).map(([path, bytes]) => ({ path, size: bytes.length, sha256: sha(bytes) }));
  return { files, manifest: { schema: 1, id: sha(label), version: '0.6.0', build: '8', totalBytes: resources.reduce((n, r) => n + r.size, 0), resources } };
}
class FakeCacheStorage {
  constructor() { this.stores = new Map(); this.failPut = null; }
  async open(name) {
    if (!this.stores.has(name)) this.stores.set(name, new Map());
    const entries = this.stores.get(name), storage = this;
    const key = request => typeof request === 'string' ? request : request.url;
    return {
      async put(request, response) {
        if (storage.failPut?.(name, key(request))) throw Error('QuotaExceededError');
        entries.set(key(request), response.clone());
      },
      async match(request, options = {}) {
        let url = key(request);
        if (options.ignoreSearch) url = url.split('?')[0];
        return entries.get(url)?.clone();
      },
      async delete(request) { return entries.delete(key(request)); },
      async keys() { return [...entries.keys()].map(url => new Request(url)); },
    };
  }
  async delete(name) { return this.stores.delete(name); }
  async keys() { return [...this.stores.keys()]; }
}
function workerHarness(options = {}) {
  const handlers = {}, calls = [], cacheStorage = options.caches || new FakeCacheStorage();
  const candidate = options.release || release();
  const self = {
    navigator: { locks: { async request(name, options, callback) { return callback({ name, mode: options.mode }); } } },
    crypto: webcrypto, registration: { scope: base }, location: { origin: new URL(base).origin },
    clients: { async claim() {}, async matchAll() { return options.clients || [{ id: 'tab-1', url: base }]; } }, async skipWaiting() {},
    addEventListener(name, fn) { handlers[name] = fn; },
  };
  const fetch = async (url, init) => {
    calls.push({ url: typeof url === 'string' ? url : url.url, init });
    if (options.fetch) return options.fetch(url, init, candidate);
    const name = new URL(typeof url === 'string' ? url : url.url).pathname.split('/').pop();
    const bytes = candidate.files[name];
    if (!bytes) return new Response('Not found', { status: 404 });
    // Deliberately no Content-Length: progress must use actual chunks + manifest.
    return new Response(new ReadableStream({ start(controller) {
      const split = Math.max(1, Math.floor(bytes.length / 2));
      controller.enqueue(bytes.subarray(0, split)); controller.enqueue(bytes.subarray(split)); controller.close();
    } }), { headers: { 'Content-Type': name.endsWith('html') ? 'text/html' : 'application/javascript' } });
  };
  const context = { self, crypto: webcrypto, URL, Response, Request, Headers, Blob, AbortController, Uint8Array, fetch, caches: cacheStorage };
  context.globalThis = context;
  vm.runInNewContext(coreSource, context);
  self.CloudMusicUpdateCore = context.CloudMusicUpdateCore;
  vm.runInNewContext(retentionSource, context);
  self.CloudMusicUpdateRetention = context.CloudMusicUpdateRetention;
  vm.runInNewContext(workerSource, context);
  async function message(action, data = {}, client = 'tab-1', onProgress) {
    const messages = []; let operation;
    handlers.message({ source: { id: client, url: base }, data: { action, ...data }, ports: [{ postMessage(message) { messages.push(message); if (message.type === 'progress') onProgress?.(message); } }], waitUntil(value) { operation = value; } });
    await operation;
    const error = messages.find(message => message.type === 'error');
    if (error) throw Error(error.message);
    return { value: messages.find(message => message.type === 'result')?.value, progress: messages.filter(message => message.type === 'progress') };
  }
  async function navigate(url = base, mode = 'navigate') {
    let result;
    handlers.fetch({ request: { url, method: 'GET', mode }, respondWith(value) { result = value; } });
    return result ? await result : null;
  }
  async function download(manifest = candidate.manifest, operationId = 'operation', onProgress) {
    return message('download', { manifest, operationId }, 'tab-1', onProgress);
  }
  async function install(token, id = candidate.manifest.id) { return message('install', { id, token }); }
  return { calls, caches: cacheStorage, candidate, message, download, install, navigate };
}
const stageCaches = async h => (await h.caches.keys()).filter(name => name.includes(':stage:'));
test('full download streams real bytes without Content-Length and activates only after confirmation', async () => {
  const h = workerHarness();
  const { value, progress } = await h.download();
  assert.equal(progress[0].received, 0);
  assert.equal(progress.at(-1).received, h.candidate.manifest.totalBytes);
  assert.ok(progress.length > h.candidate.manifest.resources.length);
  assert.ok(progress.every((entry, i) => entry.total === h.candidate.manifest.totalBytes && (i === 0 || entry.received > progress[i - 1].received)));
  assert.equal((await h.navigate()).status, 404, 'download must not promote');
  await h.install(value.token);
  assert.equal(await (await h.navigate()).text(), '<html>new</html>');
  assert.ok(h.calls.filter(call => call.init).every(call => call.init.redirect === 'error' && call.init.cache === 'no-store'));
});
test('hash mismatch, HTTP error and truncation never leave an installable cache', async () => {
  for (const failure of ['hash', 'http', 'truncated']) {
    const h = workerHarness({ fetch: async (url, init, candidate) => {
      const name = new URL(url).pathname.split('/').pop(), bytes = candidate.files[name];
      if (failure === 'http') return new Response('no', { status: 503 });
      return new Response(failure === 'hash' ? Buffer.alloc(bytes.length, 88) : bytes.subarray(0, bytes.length - 1));
    } });
    await assert.rejects(h.download(), failure === 'hash' ? /校验失败/ : failure === 'http' ? /HTTP 503/ : /不完整/);
    assert.equal((await stageCaches(h)).length, 0);
    await assert.rejects(h.install('anything'), /未下载完成/);
  }
});
test('missing resource size, duplicate/path traversal or arbitrary external paths are rejected before fetching', async () => {
  for (const change of [m => delete m.resources[0].size, m => { m.resources[0].path = '../index.html'; }, m => { m.resources[0].path = 'https://evil.test/file'; }, m => { m.resources[0].path = '%2e%2e/index.html'; }, m => { m.resources.push(m.resources[0]); }]) {
    const h = workerHarness(), manifest = structuredClone(h.candidate.manifest); change(manifest);
    await assert.rejects(h.download(manifest), /无效/); assert.equal(h.calls.length, 0);
  }
});
test('cancel midstream clears staging and retry starts at zero, without touching unrelated caches', async () => {
  const candidate = release(); let slow = true, started;
  const hasStarted = new Promise(resolve => { started = resolve; });
  const h = workerHarness({ release: candidate, fetch: async (url, init) => {
    const bytes = candidate.files[new URL(url).pathname.split('/').pop()];
    if (!slow) return new Response(bytes);
    return new Response(new ReadableStream({ start(controller) {
      controller.enqueue(bytes.subarray(0, 1)); started();
      init.signal.addEventListener('abort', () => controller.error(Error('aborted')), { once: true });
    } }));
  } });
  await h.caches.open('unrelated-music-cache');
  const pending = h.download(); const rejection = assert.rejects(pending, /取消/);
  await hasStarted;
  await assert.rejects(h.download(undefined, 'double-click'), /正在进行/);
  await h.message('cancel', { operationId: 'operation' }); await rejection;
  assert.equal((await stageCaches(h)).length, 0);
  assert.ok((await h.caches.keys()).includes('unrelated-music-cache'));
  slow = false; const result = await h.download(undefined, 'retry');
  assert.equal(result.progress[0].received, 0); await h.install(result.value.token);
});
test('worker restart retains complete download, interrupted cache cannot promote, repeated install is safe', async () => {
  const h = workerHarness(), result = await h.download();
  const restarted = workerHarness({ caches: h.caches });
  await restarted.install(result.value.token);
  await assert.rejects(restarted.install(result.value.token), /未下载完成/);
  assert.equal(await (await restarted.navigate()).text(), '<html>new</html>');
  const broken = workerHarness(); const downloaded = await broken.download();
  const cacheName = (await stageCaches(broken))[0];
  const cache = await broken.caches.open(cacheName);
  await cache.delete(base + 'cloud-music-builds/' + broken.candidate.manifest.id + '/main.dart.js');
  await assert.rejects(broken.install(downloaded.value.token), /清理/);
  const quota = workerHarness(); quota.caches.failPut = (name, url) => name.includes(':stage:') && url.endsWith('/complete');
  await assert.rejects(quota.download(), /Quota/); assert.equal((await stageCaches(quota)).length, 0);
});
test('new cache promotion preserves an older running tab and a failed subsequent update preserves active version', async () => {
  const first = workerHarness({ release: release('old') });
  const oldDownload = await first.download(); await first.install(oldDownload.value.token);
  const newer = release('new'); newer.manifest.build = '9';
  const next = workerHarness({ release: newer, caches: first.caches });
  const nextDownload = await next.download();
  assert.equal(await (await next.navigate()).text(), '<html>old</html>');
  await next.install(nextDownload.value.token);
  assert.equal(await (await next.navigate()).text(), '<html>new</html>');
  const oldUrl = base + 'cloud-music-builds/' + first.candidate.manifest.id + '/main.dart.js';
  assert.equal(await (await next.navigate(oldUrl, 'cors')).text(), 'old-compiled-app');
  await next.message('cancel', { operationId: 'operation' });
  assert.equal(await (await next.navigate()).text(), '<html>new</html>');
  const failed = workerHarness({ caches: next.caches, fetch: async () => new Response('Unavailable', { status: 500 }) });
  await assert.rejects(failed.download(), /HTTP 500/);
  assert.equal(await (await failed.navigate()).text(), '<html>new</html>');
});
test('another tab cannot activate a prepared download', async () => {
  const h = workerHarness(), result = await h.download();
  await assert.rejects(h.message('install', { id: h.candidate.manifest.id, token: result.value.token }, 'tab-2'), /未下载完成/);
});
test('publisher creates hash-verified immutable resources, running metadata and a custom worker', () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'cloud-music-update-test-'));
  try {
    fs.mkdirSync(path.join(folder, 'canvaskit'));
    fs.writeFileSync(path.join(folder, 'canvaskit', 'canvaskit.wasm'), 'engine');
    for (const file of ['index.html', 'update_core.js', 'app_updates.js']) fs.copyFileSync(path.join('web', file), path.join(folder, file));
    fs.writeFileSync(path.join(folder, 'index.html'), fs.readFileSync(path.join(folder, 'index.html'), 'utf8').replace('$FLUTTER_BASE_HREF', '/cloud-music/'));
    fs.writeFileSync(path.join(folder, 'flutter_bootstrap.js'), "function frameworkLoader({serviceWorkerSettings: unused}) {}\n_flutter.loader.load({config:{canvasKitBaseUrl: 'canvaskit/'}});");
    fs.writeFileSync(path.join(folder, 'main.dart.js'), 'compiled app');
    fs.writeFileSync(path.join(folder, '.last_build_id'), 'Flutter local build marker');
    fs.writeFileSync(path.join(folder, 'version.json'), JSON.stringify({ version: '0.6.0', build_number: '8' }));
    execFileSync(process.execPath, ['scripts/prepare_web_updates.cjs', folder]);
    const manifest = JSON.parse(fs.readFileSync(path.join(folder, 'cloud-music-release.json')));
    assert.equal(manifest.version, '0.6.0'); assert.equal(manifest.build, '8');
    assert.ok(!manifest.resources.some(resource => resource.path === '.last_build_id'));
    for (const resource of manifest.resources) {
      const bytes = fs.readFileSync(path.join(folder, 'cloud-music-builds', manifest.id, resource.path));
      assert.equal(bytes.length, resource.size); assert.equal(sha(bytes), resource.sha256);
    }
    const index = fs.readFileSync(path.join(folder, 'index.html'), 'utf8');
    assert.ok(index.includes('window.CLOUD_MUSIC_BUILD = '));
    assert.ok(index.includes('/cloud-music/cloud-music-builds/' + manifest.id + '/'));
    assert.ok(fs.readFileSync(path.join(folder, 'flutter_service_worker.js'), 'utf8').includes('CloudMusicUpdateCore'));
    assert.throws(() => execFileSync(process.execPath, ['scripts/prepare_web_updates.cjs', folder], { stdio: 'pipe' }), /Command failed/);
  } finally { fs.rmSync(folder, { recursive: true, force: true }); }
});
function pageHarness(options = {}) {
  const candidate = release(), calls = [];
  const config = { id: sha('installed'), version: '0.5.1', build: '7', base: '/cloud-music/' };
  const context = { URL, Blob: options.Blob || Blob, AbortController, crypto: webcrypto, isSecureContext: true, caches: {}, navigator: { serviceWorker: options.manager || {} },
    CLOUD_MUSIC_BUILD: config, location: { origin: 'https://music.test', replace(url) { calls.push(['reload', url]); } },
    async fetch(url, init) { calls.push(['fetch', url, init]); if (options.fetch) return options.fetch(url, init); return options.response || new Response(JSON.stringify(candidate.manifest)); },
    setTimeout: options.setTimeout || setTimeout, clearTimeout: options.clearTimeout || clearTimeout, MessageChannel, Date,
  };
  context.globalThis = context;
  vm.runInNewContext(coreSource + '\n' + pageSource, context);
  return { api: context.cloudMusicUpdates, calls, candidate, config };
}
test('version check uses running metadata, same-origin no-store manifest and never reloads', async () => {
  const h = pageHarness();
  assert.equal(h.api.getInstalledVersion().version, '0.5.1');
  const result = await h.api.check();
  assert.equal(result.id, h.candidate.manifest.id);
  assert.ok(h.calls[0][1].startsWith(base + 'cloud-music-release.json?'));
  assert.equal(h.calls[0][2].redirect, 'error');
  assert.equal(h.calls[0][2].cache, 'no-store');
  assert.equal(h.calls.filter(call => call[0] === 'reload').length, 0);
  h.config.id = h.candidate.manifest.id; assert.equal(await h.api.check(), null);
  await assert.rejects(pageHarness({ response: new Response('failed', { status: 503 }) }).api.check(), /HTTP 503/);
});
test('an unrelated service worker is never replaced or unregistered', async () => {
  let registered = false;
  const h = pageHarness({ manager: {
    async getRegistration() { return { scope: base, active: { scriptURL: base + 'other-worker.js' } }; },
    async register() { registered = true; },
  } });
  const result = await h.api.check();
  await assert.rejects(h.api.download(result.id, () => {}), /其他离线应用/);
  assert.equal(registered, false);
});
test('page cancel followed immediately by retry waits for old cleanup and ignores stale progress', async () => {
  const downloads = [], progress = [], stages = new Set();
  const worker = { scriptURL: base + 'flutter_service_worker.js', postMessage(message, ports) {
    const port = ports?.[0];
    if (message.action === 'hello') port.postMessage({ type: 'result', value: { protocol: 1 } });
    if (message.action === 'download') {
      downloads.push({ message, port }); stages.add(message.operationId);
      port.postMessage({ type: 'progress', received: 1, total: 10 });
    }
    if (message.action === 'cancel') {
      const previous = downloads.find(entry => entry.message.operationId === message.operationId);
      if (previous && stages.has(message.operationId)) setTimeout(() => {
        stages.delete(message.operationId);
        previous.port.postMessage({ type: 'progress', received: 9, total: 10 });
        previous.port.postMessage({ type: 'error', message: '更新下载已取消。' });
      }, 5);
    }
  } };
  const h = pageHarness({ manager: { async getRegistration() { return null; }, async register() { return { active: worker }; } } });
  const candidate = await h.api.check();
  const first = h.api.download(candidate.id, received => progress.push(['first', received]));
  const rejected = assert.rejects(first, /取消/);
  while (!downloads.length) await new Promise(resolve => setTimeout(resolve, 1));
  h.api.cancel();
  const second = h.api.download(candidate.id, received => progress.push(['second', received]));
  await rejected;
  while (downloads.length < 2) await new Promise(resolve => setTimeout(resolve, 1));
  assert.equal(stages.size, 1, 'retry starts only after previous download cleaned up');
  downloads[1].port.postMessage({ type: 'result', value: { token: 'ready' } });
  await second;
  assert.ok(!progress.some(([label, received]) => label === 'first' && received === 9));
  assert.equal(h.calls.filter(call => call[0] === 'reload').length, 0);
});
test('cancel during service-worker registration never starts the cancelled download', async () => {
  let completeRegistration, downloadCount = 0;
  const worker = { scriptURL: base + 'flutter_service_worker.js', postMessage(message, ports) {
    if (message.action === 'hello') ports[0].postMessage({ type: 'result', value: { protocol: 1 } });
    if (message.action === 'download') { downloadCount++; ports[0].postMessage({ type: 'result', value: { token: 'ready' } }); }
  } };
  const h = pageHarness({ manager: { async getRegistration() { return null; }, register() { return new Promise(resolve => { completeRegistration = resolve; }); } } });
  const candidate = await h.api.check();
  const first = h.api.download(candidate.id, () => {}); const rejected = assert.rejects(first, /取消/);
  while (!completeRegistration) await new Promise(resolve => setTimeout(resolve, 1));
  h.api.cancel(); const retry = h.api.download(candidate.id, () => {});
  completeRegistration({ active: worker });
  await rejected; await retry; assert.equal(downloadCount, 1);
});
test('check blocks older versions/builds, malformed versions and unordered equal-number content redeploys', async () => {
  for (const patch of [{ version: '0.4.9', build: '100' }, { version: '0.5.1', build: '6' }, { version: 'latest', build: '8' }, { version: '0.6.0', build: '-1' }]) {
    const candidate = release(); Object.assign(candidate.manifest, patch);
    const h = pageHarness({ response: new Response(JSON.stringify(candidate.manifest)) });
    await assert.rejects(h.api.check(), /降级|无效/);
  }
  const candidate = release(); Object.assign(candidate.manifest, { version: '0.5.1', build: '7' });
  const h = pageHarness({ response: new Response(JSON.stringify(candidate.manifest)) });
  await assert.rejects(h.api.check(), /同一版本和构建号/);
});
test('oversized manifest stops the reader, and explicit cancellation aborts a pending check', async () => {
  let cancelled = false;
  const response = new Response(new ReadableStream({
    pull(controller) { controller.enqueue(new Uint8Array(1024 * 1024)); },
    cancel() { cancelled = true; },
  }));
  await assert.rejects(pageHarness({ response }).api.check(), /过大/);
  assert.equal(cancelled, true);
  let signal;
  const h = pageHarness({ fetch: (url, init) => new Promise((resolve, reject) => {
    signal = init.signal;
    signal.addEventListener('abort', () => reject(Error('aborted')), { once: true });
  }) });
  const pending = h.api.check(), rejection = assert.rejects(pending, /取消或超时/);
  h.api.cancel(); await rejection; assert.equal(signal.aborted, true);
});
test('next download removes interrupted unreferenced staging, preserving unrelated and installed caches', async () => {
  const h = workerHarness();
  await h.caches.open('cloud-music-updates-v1:' + base + ':stage:crashed-worker');
  await h.caches.open('some-other-app:stage:unrelated');
  await h.download();
  const names = await h.caches.keys();
  assert.ok(!names.some(name => name.endsWith(':crashed-worker')));
  assert.ok(names.includes('some-other-app:stage:unrelated'));
});
test('stalled manifest fetch times out through AbortController', async () => {
  let triggerTimeout, signal;
  const h = pageHarness({
    setTimeout(callback, delay) { assert.equal(delay, 20000); triggerTimeout = callback; return 1; }, clearTimeout() {},
    fetch: (url, init) => new Promise((resolve, reject) => { signal = init.signal; signal.addEventListener('abort', () => reject(Error('aborted'))); }),
  });
  const pending = h.api.check(), rejected = assert.rejects(pending, /超时/);
  triggerTimeout(); await rejected; assert.equal(signal.aborted, true);
});

test('worker registration and promotion bound installed caches while preserving a live old tab', async () => {
  const clients = [{ id: 'tab-1', url: base }];
  const caches = new FakeCacheStorage();
  let latest;
  const running = release('initial-page'); running.manifest.build = '7';
  for (let build = 8; build <= 13; build++) {
    const candidate = release('build-' + build); candidate.manifest.build = String(build);
    latest = workerHarness({ release: candidate, caches, clients });
    if (build === 8) await latest.message('hello', { runningBuild: running.manifest });
    const staged = await latest.download(); await latest.install(staged.value.token);
    if (build === 8) {
      clients.push({ id: 'old-tab', url: base });
      await latest.message('hello', { runningBuild: candidate.manifest }, 'old-tab');
    }
    assert.ok((await stageCaches(latest)).length <= 3, 'active + live old build + one inactive');
  }
  const oldId = release('build-8').manifest.id;
  assert.equal(await (await latest.navigate(base + 'cloud-music-builds/' + oldId + '/main.dart.js', 'cors')).text(), 'build-8-compiled-app');
  clients.pop();
  await latest.message('hello', { runningBuild: latest.candidate.manifest });
  assert.equal((await stageCaches(latest)).length, 2, 'closed old tab no longer pins its cache');
  const metadata = await caches.open('cloud-music-updates-v1:' + base + ':metadata');
  assert.equal(await metadata.match(base + '.cloud-music-update-state/build/' + oldId), undefined);
});

test('cancellation while decoding a manifest cannot commit stale candidate state', async () => {
  let completeDecode, started;
  const decoding = new Promise(resolve => { started = resolve; });
  class SlowBlob {
    constructor(chunks) { this.value = new Blob(chunks); }
    async text() {
      const text = await this.value.text(); started();
      return new Promise(resolve => { completeDecode = () => resolve(text); });
    }
  }
  const h = pageHarness({ Blob: SlowBlob });
  const pending = h.api.check(); const rejected = assert.rejects(pending, /取消或超时/);
  await decoding; h.api.cancel(); completeDecode(); await rejected;
  await assert.rejects(h.api.download(h.candidate.manifest.id, () => {}), /重新检查更新/);
});

test('closed-tab in-flight downloads are aborted and cannot pin their cache forever', async () => {
  const clients = [{ id: 'tab-1', url: base }], candidate = release();
  let started; const firstChunk = new Promise(resolve => { started = resolve; });
  const h = workerHarness({ clients, release: candidate, fetch: async (url, init) => {
    const bytes = candidate.files[new URL(url).pathname.split('/').pop()];
    return new Response(new ReadableStream({ start(controller) {
      controller.enqueue(bytes.subarray(0, 1)); started();
      init.signal.addEventListener('abort', () => controller.error(Error('aborted')), { once: true });
    } }));
  } });
  const pending = h.download(); const rejected = assert.rejects(pending, /取消/);
  await firstChunk;
  clients.splice(0, 1, { id: 'tab-2', url: base });
  await h.message('hello', { runningBuild: candidate.manifest }, 'tab-2');
  await rejected;
  assert.equal((await stageCaches(h)).length, 0);
  const metadata = await h.caches.open('cloud-music-updates-v1:' + base + ':metadata');
  assert.equal(await metadata.match(base + '.cloud-music-update-state/download/tab-1'), undefined);
});
