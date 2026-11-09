/* prepare_web_updates.cjs prepends update_core.js to this worker. */
'use strict';
const updateCore = self.CloudMusicUpdateCore;
const appBase = updateCore.baseURL(self.registration.scope, self.location.origin);
// Scope-qualified names avoid touching another app's service worker or caches.
const cachePrefix = 'cloud-music-updates-v1:' + appBase.href + ':';
const metaName = cachePrefix + 'metadata';
const tasks = new Map();
const installingClients = new Set();
let promotionQueue = Promise.resolve();
// Web Locks also serialize overlapping old/new worker instances. An in-memory
// queue alone would not protect the persisted pointer during worker replacement.
function withPromotionLock(action) {
  const queued = promotionQueue.then(() => {
    if (typeof self.navigator?.locks?.request !== 'function') {
      throw new Error('此浏览器不支持安全的跨标签页更新锁，请使用较新的浏览器。');
    }
    return self.navigator.locks.request(cachePrefix + 'promotion', { mode: 'exclusive' }, action);
  });
  promotionQueue = queued.catch(() => {});
  return queued;
}
function assertMonotonic(candidate, active) {
  if (!active) return;
  const installed = updateCore.validateManifest(active.manifest);
  if (updateCore.isOlder(candidate, installed)) {
    throw new Error('其他标签页已启用较新的版本，已阻止旧版本覆盖。请重载页面使用新版。');
  }
  if (candidate.id !== installed.id && updateCore.compareVersions(candidate.version, installed.version) === 0 &&
      Number(candidate.build) === Number(installed.build)) {
    throw new Error('同一版本和构建号对应不同内容，无法安全排序。请提高构建号后重新发布。');
  }
  if (candidate.id === installed.id &&
      (candidate.version !== installed.version || candidate.build !== installed.build ||
       JSON.stringify(candidate.resources) !== JSON.stringify(installed.resources))) {
    throw new Error('更新内容标识与已启用版本不一致，已停止启用。');
  }
}
const key = path => new URL('.cloud-music-update-state/' + path, appBase).href;
const json = data => new Response(JSON.stringify(data), { headers: { 'Content-Type': 'application/json' } });
async function readMeta(path) {
  const response = await (await caches.open(metaName)).match(key(path));
  return response ? response.json() : null;
}
async function writeMeta(path, value) { await (await caches.open(metaName)).put(key(path), json(value)); }
function validateRunningBuild(value, allowSynthetic = false) {
  if (!value || (!/^[a-f0-9]{64}$/.test(value.id) && !(allowSynthetic && value.id === null))) {
    throw new Error('当前构建信息无效。');
  }
  updateCore.compareVersions(value.version, value.version);
  if (typeof value.build !== 'string' || !/^\d+$/.test(value.build) ||
      !Number.isSafeInteger(Number(value.build))) throw new Error('当前构建信息无效。');
  return value;
}
function validateFloor(value) {
  if (!value) return null;
  validateRunningBuild(value, true);
  if (value.schema !== 1 || typeof value.ambiguous !== 'boolean') throw new Error('已记录版本信息无效，已停止启用更新。');
  return value;
}
function assertObservedFloor(candidate, value) {
  const floor = validateFloor(value);
  if (!floor) return;
  if (updateCore.isOlder(candidate, floor)) {
    throw new Error('已有标签页运行较新的版本，已阻止旧版本覆盖。请重载页面使用新版。');
  }
  if (updateCore.compareVersions(candidate.version, floor.version) === 0 &&
      Number(candidate.build) === Number(floor.build) &&
      (floor.ambiguous || (floor.id !== null && floor.id !== candidate.id))) {
    throw new Error('同一版本和构建号对应不同内容，无法安全排序。请提高构建号后重新发布。');
  }
}
// Same-origin application pages identify their executing build during hello.
// This tiny persistent high-water survives worker replacement and cache pruning,
// including first installs where no updater-managed active cache exists yet.
async function rememberObservedBuild(runningBuild) {
  const running = validateRunningBuild(runningBuild);
  const previous = validateFloor(await readMeta('observed'));
  let next = { schema: 1, id: running.id, version: running.version, build: running.build, ambiguous: false };
  if (previous) {
    const version = updateCore.compareVersions(running.version, previous.version) > 0 ? running.version : previous.version;
    const build = Number(running.build) > Number(previous.build) ? running.build : previous.build;
    const unchanged = version === previous.version && build === previous.build;
    const runningIsFloor = updateCore.compareVersions(running.version, version) === 0 && Number(running.build) === Number(build);
    if (unchanged) {
      next = { ...previous };
      if (runningIsFloor) {
        if (next.id !== null && next.id !== running.id) next.ambiguous = true;
        if (next.id === null) next.id = running.id;
      }
    } else {
      // Independent maxima can form a synthetic pair if a server deploy already
      // regressed one component. A future candidate must dominate both maxima.
      next = { schema: 1, id: runningIsFloor ? running.id : null, version, build, ambiguous: false };
    }
  }
  await writeMeta('observed', next);
}

async function pruneUpdateCachesLocked() {
  let protectedCacheNames = Array.from(tasks.values(), task => task.cacheName);
  try {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const live = new Set(windows.map(client => client.id));
    // A disappeared page cannot consume its download. Abort its stream rather
    // than let the local tasks map pin a closed-tab cache indefinitely.
    for (const [client, task] of tasks) if (!live.has(client)) task.abort.abort();
    protectedCacheNames = Array.from(tasks).filter(([client]) => live.has(client)).map(([, task]) => task.cacheName);
  } catch (_) { /* If client enumeration fails, retain files conservatively. */ }
  return self.CloudMusicUpdateRetention.prune({
    cachePrefix, appBase, caches, clients: self.clients, protectedCacheNames,
  });
}
function clientKey(client) { return 'client/' + encodeURIComponent(client); }
function downloadKey(client) { return 'download/' + encodeURIComponent(client); }
async function registerClient(client, runningBuild) {
  if (!runningBuild || !/^[a-f0-9]{64}$/.test(runningBuild.id)) return;
  validateRunningBuild(runningBuild);
  await withPromotionLock(async () => {
    await rememberObservedBuild(runningBuild);
    await writeMeta(clientKey(client), { id: runningBuild.id });
    await pruneUpdateCachesLocked();
  });
}
function readyKey(client) { return 'ready/' + encodeURIComponent(client); }
function checkCancelled(task) {
  if (task.abort.signal.aborted) throw new Error('更新下载已取消。');
}
function send(port, message) { try { port?.postMessage(message); } catch (_) { /* Closed page. */ } }
async function discardPrepared(client, descriptor) {
  if (!descriptor || !descriptor.cacheName.startsWith(cachePrefix + 'stage:')) return;
  const committed = await readMeta('build/' + descriptor.id);
  // Never remove an installed cache, even if a late cancellation arrives.
  if (committed?.cacheName !== descriptor.cacheName && !installingClients.has(client)) {
    await caches.delete(descriptor.cacheName);
    const current = await readMeta(readyKey(client));
    if (current?.token === descriptor.token) await (await caches.open(metaName)).delete(key(readyKey(client)));
  }
}
async function cancel(client, operationId) {
  const task = tasks.get(client);
  if (task?.operationId === operationId) task.abort.abort();
  await withPromotionLock(async () => {
    const ready = await readMeta(readyKey(client));
    if (ready?.operationId === operationId) await discardPrepared(client, ready);
  });
}
async function download(client, request, port) {
  if (typeof self.navigator?.locks?.request !== 'function') {
    throw new Error('此浏览器不支持安全的跨标签页更新锁，请使用较新的浏览器。');
  }
  // A replacing worker must not overwrite the persistent in-flight marker of
  // an older worker serving the same tab. Hold this lock through final cleanup.
  return self.navigator.locks.request(cachePrefix + 'download:' + encodeURIComponent(client),
    { mode: 'exclusive', ifAvailable: true }, async lock => {
      if (!lock) throw new Error('此标签页已有更新下载正在进行，请稍后重试。');
      return downloadLocked(client, request, port);
    });
}
async function downloadLocked(client, request, port) {
  if (tasks.has(client) || installingClients.has(client)) throw new Error('已有更新操作正在进行。');
  if (typeof request.operationId !== 'string' || request.operationId.length > 100) throw new Error('更新操作无效。');
  const manifest = updateCore.validateManifest(request.manifest);
  const token = self.crypto.randomUUID();
  const cacheName = cachePrefix + 'stage:' + token;
  const task = { operationId: request.operationId, abort: new AbortController(), cacheName };
  tasks.set(client, task);
  let received = 0;
  try {
    await withPromotionLock(async () => {
      await writeMeta(downloadKey(client), { cacheName, id: manifest.id, operationId: request.operationId });
      await pruneUpdateCachesLocked();
      await discardPrepared(client, await readMeta(readyKey(client)));
    });
    const cache = await caches.open(cacheName);
    const report = () => send(port, { type: 'progress', received, total: manifest.totalBytes });
    report();
    for (const resource of manifest.resources) {
      checkCancelled(task);
      const url = updateCore.resourceURL(appBase, manifest.id, resource.path);
      const response = await fetch(url, { signal: task.abort.signal, cache: 'no-store', credentials: 'same-origin', redirect: 'error' });
      if (!response.ok || response.type === 'opaque' || response.status === 206) {
        throw new Error(`下载失败（HTTP ${response.status}），请重试。`);
      }
      const chunks = [];
      let length = 0;
      const append = chunk => {
        checkCancelled(task);
        length += chunk.byteLength;
        if (length > resource.size) throw new Error('下载大小不符，请重新检查更新。');
        chunks.push(chunk); received += chunk.byteLength; report();
      };
      if (response.body) {
        const reader = response.body.getReader();
        try {
          for (;;) {
            checkCancelled(task);
            const result = await reader.read();
            if (result.done) break;
            append(result.value);
          }
        } catch (error) {
          await reader.cancel().catch(() => {});
          throw error;
        } finally { reader.releaseLock(); }
      } else {
        append(new Uint8Array(await response.arrayBuffer()));
      }
      checkCancelled(task);
      if (length !== resource.size) throw new Error('下载不完整，请重试。');
      const bytes = new Uint8Array(await new Blob(chunks).arrayBuffer());
      if (await updateCore.sha256(bytes) !== resource.sha256) throw new Error('更新文件校验失败，请重新下载。');
      checkCancelled(task);
      // A decoded stream must not retain gzip/Content-Encoding or old length headers.
      const headers = new Headers();
      headers.set('Content-Type', response.headers.get('Content-Type') || 'application/octet-stream');
      headers.set('Content-Length', String(length));
      headers.set('Cache-Control', 'public, max-age=31536000, immutable');
      await cache.put(url, new Response(bytes, { status: 200, headers }));
    }
    checkCancelled(task);
    const descriptor = { id: manifest.id, cacheName, token, operationId: request.operationId, manifest };
    // The ready marker is written LAST. Interrupted or quota-failed caches cannot install.
    await cache.put(key('complete'), json(descriptor));
    checkCancelled(task);
    await writeMeta(readyKey(client), descriptor);
    checkCancelled(task);
    return { token };
  } catch (error) {
    await caches.delete(cacheName);
    const ready = await readMeta(readyKey(client));
    if (ready?.token === token) await (await caches.open(metaName)).delete(key(readyKey(client)));
    if (task.abort.signal.aborted) throw new Error('更新下载已取消。');
    throw error;
  } finally {
    if (tasks.get(client) === task) tasks.delete(client);
    try {
      await withPromotionLock(async () => {
        const marker = await readMeta(downloadKey(client));
        if (marker?.cacheName === cacheName) await (await caches.open(metaName)).delete(key(downloadKey(client)));
      });
    } catch (_) { /* A failed cleanup is retried by the next registered operation. */ }
  }
}
async function install(client, request) {
  if (tasks.has(client) || installingClients.has(client)) throw new Error('更新仍在准备中。');
  installingClients.add(client);
  try {
    return await withPromotionLock(async () => {
      const descriptor = await readMeta(readyKey(client));
      if (!descriptor || descriptor.id !== request.id || descriptor.token !== request.token ||
          !descriptor.cacheName.startsWith(cachePrefix + 'stage:')) throw new Error('新版未下载完成，请重新下载。');
      const manifest = updateCore.validateManifest(descriptor.manifest);
      const cache = await caches.open(descriptor.cacheName);
      const marker = await cache.match(key('complete'));
      if (!marker || (await marker.json()).token !== descriptor.token) throw new Error('更新缓存不完整，请重新下载。');
      for (const resource of manifest.resources) {
        if (!await cache.match(updateCore.resourceURL(appBase, manifest.id, resource.path))) {
          throw new Error('更新缓存已被浏览器清理，请重新下载。');
        }
      }
      // Read the GLOBAL persisted active version inside the exclusive lock, after
      // all asynchronous validation and immediately before either metadata write.
      const active = await readMeta('active');
      assertMonotonic(manifest, active);
      assertObservedFloor(manifest, await readMeta('observed'));
      if (active?.id === manifest.id) {
        const installedCache = await caches.open(active.cacheName);
        let intact = true;
        for (const resource of manifest.resources) {
          if (!await installedCache.match(updateCore.resourceURL(appBase, manifest.id, resource.path))) {
            intact = false; break;
          }
        }
        if (intact) {
          await (await caches.open(metaName)).delete(key(readyKey(client)));
          if (descriptor.cacheName !== active.cacheName) await caches.delete(descriptor.cacheName);
          try { await pruneUpdateCachesLocked(); } catch (_) {}
          return { installed: true, alreadyActive: true };
        }
      }
      descriptor.installedAt = Date.now();
      await writeMeta('build/' + manifest.id, descriptor);
      // One atomic metadata put switches navigation only. Existing tabs keep
      // their immutable URLs; a stale tab can never decrease this global pointer.
      await writeMeta('active', descriptor);
      await (await caches.open(metaName)).delete(key(readyKey(client)));
      // Retention is best-effort after the atomic activation has succeeded.
      // A cache cleanup failure must not misreport a committed update as failed.
      try { await pruneUpdateCachesLocked(); } catch (_) {}
      return { installed: true };
    });
  } finally { installingClients.delete(client); }
}
self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('message', event => {
  const source = event.source;
  if (!source?.id || typeof source.url !== 'string') return;
  const url = new URL(source.url);
  if (url.origin !== appBase.origin || !url.pathname.startsWith(appBase.pathname)) return;
  const request = event.data || {}, port = event.ports?.[0];
  event.waitUntil((async () => {
    try {
      let value;
      if (request.action === 'hello') {
        await registerClient(source.id, request.runningBuild);
        value = { protocol: 1 };
      }
      else if (request.action === 'download') value = await download(source.id, request, port);
      else if (request.action === 'install') value = await install(source.id, request);
      else if (request.action === 'cancel') { await cancel(source.id, request.operationId); value = {}; }
      else throw new Error('未知更新操作。');
      send(port, { type: 'result', value });
    } catch (error) { send(port, { type: 'error', message: error.message || '更新失败，请重试。' }); }
  })());
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== appBase.origin || !url.pathname.startsWith(appBase.pathname)) return;
  const relative = url.pathname.slice(appBase.pathname.length);
  if (request.mode === 'navigate' && (relative === '' || relative === 'index.html')) {
    event.respondWith((async () => {
      // Navigation registration and response selection share the promotion lock:
      // pruning cannot remove a just-selected build before the new tab registers.
      const response = await withPromotionLock(async () => {
        const active = await readMeta('active');
        if (!active) return null;
        // A newer network-loaded page may register after an older install won
        // the lock. Never keep routing future navigations to that stale cache.
        assertObservedFloor(active.manifest, await readMeta('observed'));
        const cached = await (await caches.open(active.cacheName)).match(updateCore.resourceURL(appBase, active.id, 'index.html'));
        if (cached) await rememberObservedBuild(active.manifest);
        if (cached && event.resultingClientId) {
          await writeMeta(clientKey(event.resultingClientId), { id: active.id, pendingUntil: Date.now() + 30000 });
        }
        return cached;
      }).catch(() => null);
      return response || fetch(request);
    })());
    return;
  }
  if (!relative.startsWith(updateCore.BUILD_DIRECTORY)) return;
  const id = relative.slice(updateCore.BUILD_DIRECTORY.length).split('/')[0];
  if (!/^[a-f0-9]{64}$/.test(id)) return;
  event.respondWith((async () => {
    const committed = await readMeta('build/' + id);
    if (committed) {
      const cached = await (await caches.open(committed.cacheName)).match(request, { ignoreSearch: true });
      if (cached) return cached;
      // Never substitute a resource from another release, even after eviction.
    }
    return fetch(request);
  })());
});
