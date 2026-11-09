'use strict';

// Standalone regression harness: no browser, HTTP server, network, or helpers
// from app_update_test.cjs. Fresh VM contexts model replacement workers sharing
// origin storage and the browser's lock manager.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createHash, webcrypto } = require('node:crypto');

const root = path.resolve(__dirname, '../..');
const coreSource = fs.readFileSync(path.join(root, 'web/update_core.js'), 'utf8');
const workerSource = fs.readFileSync(path.join(root, 'web/flutter_service_worker.js'), 'utf8');
const retentionSource = fs.readFileSync(path.join(root, 'web/update_retention.js'), 'utf8');
const base = 'https://music.test/cloud-music/';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const metadataName = scope => 'cloud-music-updates-v1:' + scope + ':metadata';
const stateURL = (scope, name) => new URL('.cloud-music-update-state/' + name, scope).href;
const requestURL = request => typeof request === 'string' ? request : request.url;
const nextTurn = () => new Promise(resolve => setImmediate(resolve));

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function observe(promise) {
  const observation = { settled: false };
  observation.result = promise.then(value => ({ value }), error => ({ error }))
    .then(result => { observation.settled = true; return result; });
  return observation;
}
function makeRelease(label, build, version = '0.6.0') {
  const files = new Map([
    ['index.html', Buffer.from('<html>' + label + '</html>')],
    ['flutter_bootstrap.js', Buffer.from('bootstrap:' + label)],
    ['main.dart.js', Buffer.from('application:' + label)],
    ['version.json', Buffer.from(JSON.stringify({ version, build_number: String(build) }))],
  ]);
  const resources = Array.from(files, ([path, bytes]) => ({ path, size: bytes.length, sha256: sha(bytes) }));
  return { files, manifest: { schema: 1, id: sha(label + ':' + version + ':' + build),
    version, build: String(build), totalBytes: resources.reduce((total, entry) => total + entry.size, 0), resources } };
}

class MemoryCacheStorage {
  constructor() { this.stores = new Map(); this.operations = []; this.barriers = []; }
  holdNext(predicate) {
    const entered = deferred(), resume = deferred();
    const barrier = { predicate, entered: entered.promise, release: () => resume.resolve(),
      fail: error => resume.resolve(error), used: false };
    barrier.run = async operation => {
      barrier.used = true;
      entered.resolve(operation);
      const error = await resume.promise;
      if (error) throw error;
    };
    this.barriers.push(barrier);
    return barrier;
  }
  async checkpoint(operation) {
    this.operations.push(operation);
    const barrier = this.barriers.find(item => !item.used && item.predicate(operation));
    if (barrier) await barrier.run(operation);
  }
  async open(name) {
    if (!this.stores.has(name)) this.stores.set(name, new Map());
    const entries = this.stores.get(name), storage = this;
    return {
      async put(request, response) {
        const url = requestURL(request);
        const entry = { bytes: new Uint8Array(await response.arrayBuffer()), status: response.status,
          headers: Array.from(response.headers.entries()) };
        await storage.checkpoint({ kind: 'put', phase: 'before', name, url });
        entries.set(url, entry);
        await storage.checkpoint({ kind: 'put', phase: 'after', name, url });
      },
      async match(request, options = {}) {
        const url = requestURL(request);
        await storage.checkpoint({ kind: 'match', phase: 'before', name, url });
        const stored = options.ignoreSearch
          ? Array.from(entries).find(([candidate]) => candidate.split('?')[0] === url.split('?')[0])?.[1]
          : entries.get(url);
        // Capture the snapshot BEFORE pausing, as a completed Cache.match read
        // can become stale while another worker is trying to promote a build.
        const response = stored ? new Response(stored.bytes, { status: stored.status, headers: stored.headers }) : undefined;
        await storage.checkpoint({ kind: 'match', phase: 'after', name, url });
        return response;
      },
      async delete(request) {
        const url = requestURL(request);
        await storage.checkpoint({ kind: 'delete', phase: 'before', name, url });
        return entries.delete(url);
      },
      async keys() { return Array.from(entries.keys(), url => new Request(url)); },
    };
  }
  async keys() { return Array.from(this.stores.keys()); }
  async delete(name) {
    await this.checkpoint({ kind: 'cacheDelete', phase: 'before', name });
    const removed = this.stores.delete(name);
    await this.checkpoint({ kind: 'cacheDelete', phase: 'after', name });
    return removed;
  }
  readJSON(scope, key) {
    const bytes = this.stores.get(metadataName(scope))?.get(stateURL(scope, key))?.bytes;
    return bytes ? JSON.parse(Buffer.from(bytes).toString('utf8')) : null;
  }
  putsSince(offset = 0) { return this.operations.slice(offset).filter(op => op.kind === 'put' && op.phase === 'after'); }
}

class SharedLockManager {
  constructor() { this.tails = new Map(); this.requests = []; this.waiters = []; this.held = new Set(); this.pending = new Map(); }
  request(name, options, callback) {
    if (typeof options === 'function') { callback = options; options = {}; }
    const mode = options.mode || 'exclusive';
    assert.equal(mode, 'exclusive', 'promotion must request an exclusive Web Lock');
    this.requests.push({ name, mode, ifAvailable: options.ifAvailable === true });
    for (const waiter of this.waiters) if (this.requests.length >= waiter.count) waiter.ready.resolve();
    // Reservations include queued requests, not only callbacks already running.
    // An ifAvailable request receives null immediately rather than joining them.
    if (options.ifAvailable && this.pending.has(name)) {
      return Promise.resolve().then(() => callback(null));
    }
    this.pending.set(name, (this.pending.get(name) || 0) + 1);
    const predecessor = this.tails.get(name) || Promise.resolve();
    const result = predecessor.then(async () => {
      assert.ok(!this.held.has(name), 'fake browser must never grant overlapping exclusive locks');
      this.held.add(name);
      try { return await callback({ name, mode }); }
      finally {
        this.held.delete(name);
        const remaining = this.pending.get(name) - 1;
        if (remaining) this.pending.set(name, remaining);
        else this.pending.delete(name);
      }
    });
    // A failed holder must release the lock and allow the next request to run.
    this.tails.set(name, result.then(() => undefined, () => undefined));
    return result;
  }
  waitForRequests(count) {
    if (this.requests.length >= count) return Promise.resolve();
    const ready = deferred(); this.waiters.push({ count, ready }); return ready.promise;
  }
}

function createWorld() {
  const caches = new MemoryCacheStorage(), locks = new SharedLockManager(), releases = new Map(), liveClients = new Map();
  function worker(scope = base, lockSupport = 'available') {
    const handlers = new Map();
    const self = { crypto: webcrypto, registration: { scope }, location: { origin: new URL(scope).origin },
      clients: { async claim() {}, async matchAll() { return Array.from(liveClients.values()); } },
      async skipWaiting() {}, addEventListener(name, listener) { handlers.set(name, listener); } };
    if (lockSupport !== 'no navigator') self.navigator = lockSupport === 'available' ? { locks }
      : lockSupport === 'no locks' ? {} : { locks: {} };
    const fetch = async request => {
      const url = new URL(requestURL(request));
      const relative = url.pathname.slice(new URL(scope).pathname.length);
      const match = /^cloud-music-builds\/([a-f0-9]{64})\/(.+)$/.exec(relative);
      const bytes = match && releases.get(match[1])?.files.get(decodeURIComponent(match[2]));
      return bytes ? new Response(bytes) : new Response('Not found', { status: 404 });
    };
    const context = { self, crypto: webcrypto, URL, Response, Request, Headers, Blob,
      AbortController, Uint8Array, fetch, caches };
    context.globalThis = context;
    vm.runInNewContext(coreSource, context, { filename: 'update_core.js' });
    self.CloudMusicUpdateCore = context.CloudMusicUpdateCore;
    vm.runInNewContext(retentionSource, context, { filename: 'update_retention.js' });
    self.CloudMusicUpdateRetention = context.CloudMusicUpdateRetention;
    vm.runInNewContext(workerSource, context, { filename: 'flutter_service_worker.js' });
    async function message(client, data) {
      const messages = []; let lifetime;
      liveClients.set(client, { id: client, url: scope });
      handlers.get('message')({ source: { id: client, url: scope }, data,
        ports: [{ postMessage(value) { messages.push(value); } }], waitUntil(value) { lifetime = value; } });
      assert.ok(lifetime, 'worker accepted the same-origin client');
      await lifetime;
      const failure = messages.find(value => value.type === 'error');
      if (failure) throw new Error(failure.message);
      const result = messages.find(value => value.type === 'result');
      assert.ok(result, 'worker replied to its message port');
      return result.value;
    }
    return {
      async stage(client, release) {
        releases.set(release.manifest.id, release);
        const result = await message(client, { action: 'download', manifest: release.manifest,
          operationId: client + ':' + release.manifest.id });
        return { client, id: release.manifest.id, token: result.token };
      },
      install(prepared) { return message(prepared.client, { action: 'install', id: prepared.id, token: prepared.token }); },
      hello(client, runningBuild) { return message(client, { action: 'hello', runningBuild }); },
      async navigate() {
        let response;
        handlers.get('fetch')({ request: { url: scope, method: 'GET', mode: 'navigate' },
          respondWith(value) { response = value; } });
        return (await response).text();
      },
    };
  }
  return { caches, locks, worker, publish(release) { releases.set(release.manifest.id, release); }, active: (scope = base) => caches.readJSON(scope, 'active'),
    committed: (id, scope = base) => caches.readJSON(scope, 'build/' + id) };
}
async function fixture() {
  const world = createWorld(), worker = world.worker();
  const original = makeRelease('original-7', 7), older = makeRelease('candidate-8', 8), newer = makeRelease('candidate-9', 9);
  await worker.install(await worker.stage('original', original));
  const staged8 = await worker.stage('tab-8', older), staged9 = await worker.stage('tab-9', newer);
  return { ...world, worker, newWorker: world.worker, original, older, newer, staged8, staged9, originalActive: world.active() };
}
function activeBarrier(world, kind, phase) {
  return world.caches.holdNext(op => op.name === metadataName(base) && op.url === stateURL(base, 'active') && op.kind === kind && op.phase === phase);
}
function assertInstalled(outcome) {
  assert.equal(outcome.error, undefined, outcome.error?.message);
  assert.equal(outcome.value.installed, true);
}
function assertRejected(outcome) { assert.ok(outcome.error instanceof Error, 'promotion must reject rather than activate stale content'); }

// This is the original two-tab rollback: both downloads finish before either
// install, then the user accepts build 9 followed by stale build 8.
test('installing staged build 8 after build 9 cannot roll back the active release', { timeout: 5000 }, async () => {
  const f = await fixture();
  await f.worker.install(f.staged9);
  const installed = f.active(), offset = f.caches.operations.length;
  await assert.rejects(f.worker.install(f.staged8));
  assert.deepEqual(f.active(), installed);
  assert.equal(f.committed(f.older.manifest.id), null);
  assert.equal(f.caches.putsSince(offset).length, 0);
  assert.equal(await f.worker.navigate(), '<html>candidate-9</html>');
  assert.ok(f.caches.stores.has(f.originalActive.cacheName), 'running older tabs retain their installed cache');
});

for (const context of ['same worker', 'replacement worker']) {
  for (const pause of [{ kind: 'match', phase: 'after', label: 'active read' }, { kind: 'put', phase: 'before', label: 'active write' }]) {
    test(`${context}: newer-first concurrent installs are serialized across a paused ${pause.label}`, { timeout: 5000 }, async t => {
      const f = await fixture();
      // Each replacement is a genuinely fresh VM with no shared in-memory queue.
      const other = context === 'same worker' ? f.worker : f.newWorker();
      const held = activeBarrier(f, pause.kind, pause.phase); t.after(held.release);
      const beforeRequests = f.locks.requests.length;
      const newer = observe(f.worker.install(f.staged9));
      await held.entered;
      const operationOffset = f.caches.operations.length;
      const older = observe(other.install(f.staged8));
      if (context === 'replacement worker') await f.locks.waitForRequests(beforeRequests + 2);
      // All mocks use immediately resolved promises. One event-loop checkpoint
      // drains runnable operations; the explicit cache barrier remains closed.
      await nextTurn();
      assert.equal(older.settled, false, 'the second installer waits while the first owns promotion');
      assert.equal(f.active().id, f.original.manifest.id);
      assert.equal(f.caches.putsSince(operationOffset).length, 0, 'waiting installers cannot write build or active metadata');
      held.release();
      assertInstalled(await newer.result);
      assertRejected(await older.result);
      assert.equal(f.active().id, f.newer.manifest.id);
      assert.equal(f.committed(f.older.manifest.id), null);
      const requests = f.locks.requests.slice(beforeRequests);
      assert.equal(requests.length, 2);
      assert.equal(requests[0].name, requests[1].name, 'both contexts share the same scope lock');
    });
  }
}

for (const context of ['same worker', 'replacement worker']) {
  test(`${context}: older-first concurrent installs finish on the newer build`, { timeout: 5000 }, async t => {
    const f = await fixture(), other = context === 'same worker' ? f.worker : f.newWorker();
    const held = activeBarrier(f, 'put', 'before'); t.after(held.release);
    const beforeRequests = f.locks.requests.length;
    const older = observe(f.worker.install(f.staged8)); await held.entered;
    const newer = observe(other.install(f.staged9));
    if (context === 'replacement worker') await f.locks.waitForRequests(beforeRequests + 2);
    await nextTurn();
    assert.equal(newer.settled, false);
    held.release();
    assertInstalled(await older.result); assertInstalled(await newer.result);
    assert.equal(f.active().id, f.newer.manifest.id);
    assert.ok(f.caches.stores.has(f.committed(f.older.manifest.id).cacheName));
    assert.equal(await other.navigate(), '<html>candidate-9</html>');
  });
}

test('a failed active write releases the promotion queue and lock for an already waiting install', { timeout: 5000 }, async t => {
  const f = await fixture(), held = activeBarrier(f, 'put', 'before'); t.after(held.release);
  const failing = observe(f.worker.install(f.staged8)); await held.entered;
  const succeeding = observe(f.worker.install(f.staged9));
  await nextTurn();
  assert.equal(succeeding.settled, false);
  assert.equal(f.active().id, f.original.manifest.id);
  held.fail(new Error('QuotaExceededError: simulated active metadata failure'));
  assert.match((await failing.result).error.message, /QuotaExceededError/);
  assertInstalled(await succeeding.result);
  assert.equal(f.active().id, f.newer.manifest.id);
  assert.equal(f.locks.held.size, 0);
  await assert.rejects(f.worker.install(f.staged8));
  assert.equal(f.active().id, f.newer.manifest.id);
});

test('same version and build with a different content ID is rejected without metadata writes', { timeout: 5000 }, async () => {
  const f = await fixture(); await f.worker.install(f.staged9);
  const duplicate = await f.worker.stage('conflicting-tab', makeRelease('different-content-9', 9));
  const installed = f.active(), offset = f.caches.operations.length;
  await assert.rejects(f.worker.install(duplicate));
  assert.deepEqual(f.active(), installed);
  assert.equal(f.committed(duplicate.id), null);
  assert.equal(f.caches.putsSince(offset).length, 0);
});

test('same-ID installs from another tab are idempotent and retain the original active cache', { timeout: 5000 }, async () => {
  const f = await fixture();
  const duplicate = await f.worker.stage('duplicate-tab', f.newer);
  const prepared = f.caches.readJSON(base, 'ready/duplicate-tab');
  await f.worker.install(f.staged9);
  const installed = f.active(), committed = f.committed(f.newer.manifest.id), offset = f.caches.operations.length;
  assert.notEqual(prepared.cacheName, installed.cacheName, 'tabs really downloaded into distinct caches');
  assertInstalled({ value: await f.newWorker().install(duplicate) });
  assert.deepEqual(f.active(), installed);
  assert.deepEqual(f.committed(f.newer.manifest.id), committed);
  assert.ok(f.caches.stores.has(installed.cacheName));
  assert.equal(f.caches.putsSince(offset).length, 0, 'idempotence must not replace the active or immutable build pointer');
});

for (const candidate of [makeRelease('higher-version-lower-build', 8, '0.7.0'), makeRelease('lower-version-higher-build', 10, '0.5.9')]) {
  test(`version ${candidate.manifest.version} build ${candidate.manifest.build} cannot downgrade version 0.6.0 build 9`, { timeout: 5000 }, async () => {
    const f = await fixture(); await f.worker.install(f.staged9);
    const stale = await f.worker.stage('stale-tab', candidate), installed = f.active(), offset = f.caches.operations.length;
    await assert.rejects(f.newWorker().install(stale));
    assert.deepEqual(f.active(), installed);
    assert.equal(f.committed(stale.id), null);
    assert.equal(f.caches.putsSince(offset).length, 0);
  });
}

for (const support of ['no navigator', 'no locks', 'no request']) {
  test(`missing lock API (${support}) fails closed before writing any install metadata`, { timeout: 5000 }, async () => {
    const f = await fixture();
    const installed = f.active(), offset = f.caches.operations.length;
    await assert.rejects(f.newWorker(base, support).install(f.staged9));
    assert.deepEqual(f.active(), installed);
    assert.equal(f.committed(f.newer.manifest.id), null);
    assert.equal(f.caches.putsSince(offset).length, 0);
  });
}

test('promotion locks are origin/scope qualified and do not block another application scope', { timeout: 5000 }, async t => {
  const world = createWorld(), first = world.worker(), otherScope = 'https://music.test/another-app/';
  const second = world.worker(otherScope), release = makeRelease('separate-scope', 9);
  const a = await first.stage('tab-a', release), b = await second.stage('tab-b', release);
  const held = activeBarrier(world, 'put', 'before'); t.after(held.release);
  const requestOffset = world.locks.requests.length;
  const blocked = observe(first.install(a)); await held.entered;
  assertInstalled({ value: await second.install(b) });
  assert.equal(blocked.settled, false);
  assert.equal(world.active(), null);
  assert.equal(world.active(otherScope).id, release.manifest.id);
  const requests = world.locks.requests.slice(requestOffset);
  assert.equal(requests.length, 2);
  assert.notEqual(requests[0].name, requests[1].name);
  assert.ok(requests[0].name.includes(base));
  assert.ok(requests[1].name.includes(otherScope));
  held.release(); assertInstalled(await blocked.result);
});


test('replacement worker cannot overwrite a same-client download marker or delete its in-flight cache', { timeout: 5000 }, async t => {
  const world = createWorld(), originalWorker = world.worker(), replacement = world.worker();
  const firstRelease = makeRelease('first-client-download-8', 8), nextRelease = makeRelease('same-client-retry-9', 9);
  const client = 'shared-client';
  const held = world.caches.holdNext(op => op.kind === 'put' && op.phase === 'before' &&
    op.name.includes(':stage:') && op.url === new URL('cloud-music-builds/' + firstRelease.manifest.id + '/index.html', base).href);
  t.after(held.release);
  const first = observe(originalWorker.stage(client, firstRelease));
  await held.entered;
  const marker = world.caches.readJSON(base, 'download/' + client);
  assert.equal(marker.id, firstRelease.manifest.id);
  assert.ok(world.caches.stores.has(marker.cacheName));
  assert.equal(world.caches.readJSON(base, 'ready/' + client), null);
  const operationOffset = world.caches.operations.length;
  const requestOffset = world.locks.requests.length;
  await assert.rejects(replacement.stage(client, nextRelease));
  assert.equal(first.settled, false, 'the original transfer is still held by the deterministic barrier');
  assert.deepEqual(world.caches.readJSON(base, 'download/' + client), marker, 'rejected transfer must not replace the owner marker');
  assert.ok(world.caches.stores.has(marker.cacheName), 'retention must not prune the in-flight owner cache');
  assert.equal(world.caches.putsSince(operationOffset).length, 0, 'rejection happens before any download metadata or resource write');
  assert.ok(!world.caches.operations.slice(operationOffset).some(op => op.kind === 'cacheDelete'), 'rejected transfer cannot delete another download cache');
  const rejectedRequests = world.locks.requests.slice(requestOffset);
  assert.equal(rejectedRequests.length, 1);
  assert.equal(rejectedRequests[0].ifAvailable, true, 'same-client download contention must reject, not wait');
  assert.ok(rejectedRequests[0].name.includes(base), 'download locks are scope qualified');
  held.release();
  const completed = await first.result;
  assert.equal(completed.error, undefined, completed.error?.message);
  assert.equal(world.caches.readJSON(base, 'download/' + client), null, 'the owner cleans its marker before releasing the client lock');
  assert.equal(world.caches.readJSON(base, 'ready/' + client).cacheName, marker.cacheName);
  assertInstalled({ value: await replacement.install(completed.value) });
  const installed = world.active();
  const retry = await replacement.stage(client, nextRelease);
  assert.equal(world.active().id, firstRelease.manifest.id, 'successful retry still waits for installation confirmation');
  assert.ok(world.caches.stores.has(installed.cacheName));
  assertInstalled({ value: await replacement.install(retry) });
  assert.equal(world.active().id, nextRelease.manifest.id);
  assert.equal(world.locks.pending.size, 0);
});

test('replacement workers keep different-client downloads concurrent and protect both prepared caches', { timeout: 5000 }, async t => {
  const world = createWorld(), firstWorker = world.worker(), secondWorker = world.worker();
  const firstRelease = makeRelease('parallel-download-8', 8), secondRelease = makeRelease('parallel-download-9', 9);
  const held = world.caches.holdNext(op => op.kind === 'put' && op.phase === 'before' &&
    op.name.includes(':stage:') && op.url === new URL('cloud-music-builds/' + firstRelease.manifest.id + '/index.html', base).href);
  t.after(held.release);
  const first = observe(firstWorker.stage('parallel-client-8', firstRelease));
  await held.entered;
  const marker = world.caches.readJSON(base, 'download/parallel-client-8');
  const second = await secondWorker.stage('parallel-client-9', secondRelease);
  assert.equal(first.settled, false, 'another client can finish while the first transfer is paused');
  assert.deepEqual(world.caches.readJSON(base, 'download/parallel-client-8'), marker);
  assert.ok(world.caches.stores.has(marker.cacheName));
  const prepared9 = world.caches.readJSON(base, 'ready/parallel-client-9');
  assert.equal(prepared9.id, secondRelease.manifest.id);
  assert.ok(world.caches.stores.has(prepared9.cacheName));
  held.release();
  const completed = await first.result;
  assert.equal(completed.error, undefined, completed.error?.message);
  assert.equal(world.caches.readJSON(base, 'ready/parallel-client-8').cacheName, marker.cacheName);
  assertInstalled({ value: await secondWorker.install(second) });
  await assert.rejects(firstWorker.install(completed.value));
  assert.equal(world.active().id, secondRelease.manifest.id);
});


function runningMetadata(release) {
  const { id, version, build } = release.manifest;
  return { id, version, build };
}

test('network-served build 10 hello prevents first installation of staged build 8 after worker replacement', { timeout: 5000 }, async () => {
  const world = createWorld(), firstWorker = world.worker();
  const older = makeRelease('first-install-staged-8', 8), observed = makeRelease('network-served-10', 10);
  const prepared = await firstWorker.stage('first-install-tab-8', older);
  const preparedCache = world.caches.readJSON(base, 'ready/first-install-tab-8').cacheName;
  assert.equal(world.active(), null, 'repro must start with no prior service-worker promotion');
  world.publish(observed);
  assert.equal((await world.worker().hello('network-tab-10', runningMetadata(observed))).protocol, 1);
  assert.equal(world.active(), null, 'observing a running tab does not itself install or reload');
  const offset = world.caches.operations.length;
  await assert.rejects(world.worker().install(prepared));
  assert.equal(world.active(), null);
  assert.equal(world.committed(older.manifest.id), null);
  assert.equal(world.caches.putsSince(offset).length, 0, 'stale first install must fail before any promotion write');
  assert.ok(world.caches.stores.has(preparedCache), 'rejection must not damage the completed download');
});

test('a later lower running-build hello cannot lower the persisted observed floor across worker replacements', { timeout: 5000 }, async () => {
  const world = createWorld(), staged = makeRelease('floor-candidate-9', 9);
  const observed = makeRelease('floor-network-10', 10), lower = makeRelease('late-old-page-8', 8);
  const prepared = await world.worker().stage('staged-tab-9', staged);
  world.publish(observed); world.publish(lower);
  assert.equal((await world.worker().hello('newer-network-tab', runningMetadata(observed))).protocol, 1);
  assert.equal((await world.worker().hello('late-older-tab', runningMetadata(lower))).protocol, 1);
  assert.equal(world.active(), null);
  const offset = world.caches.operations.length;
  await assert.rejects(world.worker().install(prepared));
  assert.equal(world.active(), null);
  assert.equal(world.committed(staged.manifest.id), null);
  assert.equal(world.caches.putsSince(offset).length, 0);
});

for (const [label, patch] of [
  ['invalid content ID', { id: '../not-a-content-id' }],
  ['missing semantic version', { version: undefined }],
  ['malformed semantic version', { version: 'latest' }],
  ['negative build', { build: '-1' }],
  ['unsafe build integer', { build: '9007199254740992' }],
  ['numeric rather than string build', { build: 10 }],
]) {
  test(`malformed running metadata (${label}) cannot write or poison the first-install floor`, { timeout: 5000 }, async () => {
    const world = createWorld(), candidate = makeRelease('valid-first-install-8', 8);
    const claimed = makeRelease('malformed-network-10', 10);
    const prepared = await world.worker().stage('valid-first-tab', candidate);
    world.publish(claimed);
    const offset = world.caches.operations.length;
    // Invalid hello may be rejected or ignored for protocol compatibility, but
    // it must never persist a floor or client build inferred from invalid data.
    await world.worker().hello('invalid-network-tab', { ...runningMetadata(claimed), ...patch }).catch(() => {});
    assert.equal(world.caches.putsSince(offset).length, 0);
    assert.equal(world.active(), null);
    assertInstalled({ value: await world.worker().install(prepared) });
    assert.equal(world.active().id, candidate.manifest.id, 'invalid claims cannot poison future valid installs');
  });
}

test('equal version and build with different content cannot replace an observed running release before first install', { timeout: 5000 }, async () => {
  const world = createWorld(), candidate = makeRelease('ambiguous-first-install-10', 10);
  const observed = makeRelease('actual-running-content-10', 10);
  const prepared = await world.worker().stage('ambiguous-download-tab', candidate);
  world.publish(observed);
  assert.equal((await world.worker().hello('actual-running-tab', runningMetadata(observed))).protocol, 1);
  const offset = world.caches.operations.length;
  await assert.rejects(world.worker().install(prepared));
  assert.equal(world.active(), null);
  assert.equal(world.committed(candidate.manifest.id), null);
  assert.equal(world.caches.putsSince(offset).length, 0);
});

test('the exact observed running content can become the first installed release', { timeout: 5000 }, async () => {
  const world = createWorld(), release = makeRelease('matching-network-content-10', 10);
  const prepared = await world.worker().stage('matching-download-tab', release);
  assert.equal((await world.worker().hello('matching-running-tab', runningMetadata(release))).protocol, 1);
  assert.equal(world.active(), null);
  assertInstalled({ value: await world.worker().install(prepared) });
  assert.equal(world.active().id, release.manifest.id);
});

test('a late hello from running build 10 stops navigation from serving already active build 8', { timeout: 5000 }, async () => {
  const world = createWorld(), worker = world.worker();
  const installedRelease = makeRelease('late-hello-active-8', 8), observed = makeRelease('late-hello-network-10', 10);
  assertInstalled({ value: await worker.install(await worker.stage('installed-tab-8', installedRelease)) });
  const installed = world.active();
  assert.equal(await worker.navigate(), '<html>late-hello-active-8</html>', 'the old active cache was usable before the newer hello');
  world.publish(observed);
  assert.equal((await world.worker().hello('new-network-tab-10', runningMetadata(observed))).protocol, 1);
  const indexURL = new URL('cloud-music-builds/' + installedRelease.manifest.id + '/index.html', base).href;
  assert.ok(world.caches.stores.get(installed.cacheName)?.has(indexURL), 'the regression must not pass merely because retention removed the cache');
  assert.equal(await worker.navigate(), 'Not found', 'navigation must use the mocked network fallback rather than cached build 8');
  assert.equal(await world.worker().navigate(), 'Not found', 'a replacement worker must honor the persisted higher running build too');
});

test('a late equal-version/build hello with different content stops navigation from serving the conflicting active cache', { timeout: 5000 }, async () => {
  const world = createWorld(), worker = world.worker();
  const installedRelease = makeRelease('late-hello-content-a-10', 10), observed = makeRelease('late-hello-content-b-10', 10);
  assertInstalled({ value: await worker.install(await worker.stage('content-a-tab', installedRelease)) });
  const installed = world.active();
  assert.equal(await worker.navigate(), '<html>late-hello-content-a-10</html>');
  world.publish(observed);
  assert.equal((await world.worker().hello('content-b-network-tab', runningMetadata(observed))).protocol, 1);
  const indexURL = new URL('cloud-music-builds/' + installedRelease.manifest.id + '/index.html', base).href;
  assert.ok(world.caches.stores.get(installed.cacheName)?.has(indexURL), 'conflicting content remains cached, so the navigation guard itself is exercised');
  assert.equal(await worker.navigate(), 'Not found', 'equal numbers cannot authorize serving a different content ID');
  assert.equal(await world.worker().navigate(), 'Not found', 'the conflict remains blocked after worker replacement');
});
