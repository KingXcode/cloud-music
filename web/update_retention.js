/* Call prune only while holding this app's global promotion/navigation lock. */
(function (root) {
  'use strict';
  const BUILD_ID = /^[a-f0-9]{64}$/;
  function newer(left, right) {
    const leftTime = Number.isSafeInteger(left.installedAt) && left.installedAt > 0 ? left.installedAt : 0;
    const rightTime = Number.isSafeInteger(right.installedAt) && right.installedAt > 0 ? right.installedAt : 0;
    if (leftTime !== rightTime) return rightTime - leftTime;
    const number = value => Number.isSafeInteger(Number(value)) && Number(value) >= 0 ? Number(value) : 0;
    const parts = value => /^\d+\.\d+\.\d+$/.test(value || '') ? value.split('.').map(number) : [0, 0, 0];
    const a = parts(left.manifest?.version || left.version), b = parts(right.manifest?.version || right.version);
    for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return b[i] - a[i];
    const aBuild = number(left.manifest?.build ?? left.build);
    const bBuild = number(right.manifest?.build ?? right.build);
    return bBuild - aBuild || right.id.localeCompare(left.id);
  }
  async function prune({ cachePrefix, appBase, caches, clients, protectedCacheNames = [] }) {
    const base = new URL(appBase);
    if (!base.pathname.endsWith('/') || base.search || base.hash || typeof cachePrefix !== 'string' ||
        !cachePrefix.startsWith('cloud-music-updates-') || !cachePrefix.endsWith(base.href + ':')) {
      throw new Error('Invalid update retention scope.');
    }
    const stats = { deletedCaches: 0, deletedMetadata: 0, keptBuilds: 0, conservative: false };
    let windows;
    try { windows = await clients.matchAll({ type: 'window', includeUncontrolled: true }); }
    catch (_) { return { ...stats, conservative: true, skipped: 'clients-unavailable' }; }
    const liveIds = new Set();
    for (const client of windows) {
      try {
        const url = new URL(client.url);
        if (typeof client.id === 'string' && url.origin === base.origin && url.pathname.startsWith(base.pathname)) liveIds.add(client.id);
      } catch (_) { /* A non-URL client is outside this application's scope. */ }
    }
    const meta = await caches.open(cachePrefix + 'metadata');
    const stateBase = new URL('.cloud-music-update-state/', base).href;
    const entries = [];
    for (const request of await meta.keys()) {
      const url = typeof request === 'string' ? request : request.url;
      if (!url.startsWith(stateBase) || new URL(url).search || new URL(url).hash) continue;
      const path = url.slice(stateBase.length);
      let value = null, corrupt = false;
      try { value = await (await meta.match(request)).json(); }
      catch (_) { corrupt = true; }
      entries.push({ request, path, value, corrupt });
    }
    const ownsCache = name => typeof name === 'string' && name.startsWith(cachePrefix + 'stage:');
    const validDescriptor = value => value && BUILD_ID.test(value.id) && ownsCache(value.cacheName);
    const keepNames = new Set(Array.from(protectedCacheNames).filter(ownsCache));
    const keepIds = new Set();
    const byPath = new Map(entries.map(entry => [entry.path, entry]));
    const retainedClientIds = new Set(liveIds);
    const now = Date.now();
    for (const entry of entries) {
      const match = /^client\/([^/]+)$/.exec(entry.path);
      const until = entry.value?.pendingUntil;
      if (!match || !BUILD_ID.test(entry.value?.id) || !Number.isSafeInteger(until) ||
          until <= now || until > now + 60000) continue;
      // A navigation's reserved client may not appear in matchAll until its
      // document starts. Its bounded lease protects that selected build meanwhile.
      try { retainedClientIds.add(decodeURIComponent(match[1])); } catch (_) { continue; }
      keepIds.add(entry.value.id);
    }
    const active = byPath.get('active');
    let preserveAllStages = false;
    if (active) {
      if (validDescriptor(active.value)) { keepIds.add(active.value.id); keepNames.add(active.value.cacheName); }
      else preserveAllStages = true;
    }
    const installed = [];
    for (const entry of entries) {
      if (!entry.path.startsWith('build/')) continue;
      const id = entry.path.slice('build/'.length);
      if (!BUILD_ID.test(id) || !validDescriptor(entry.value) || entry.value.id !== id) {
        preserveAllStages = true;
        continue;
      }
      installed.push(entry);
      if (keepNames.has(entry.value.cacheName)) keepIds.add(id);
    }
    // A legacy/unregistered live page might still use any installed build.
    // Keep those builds conservatively until every live page identifies itself.
    let unknownLiveClient = false;
    for (const clientId of liveIds) {
      const registration = byPath.get('client/' + encodeURIComponent(clientId));
      if (!registration || registration.corrupt || !BUILD_ID.test(registration.value?.id)) unknownLiveClient = true;
      else keepIds.add(registration.value.id);
    }
    if (unknownLiveClient || preserveAllStages) {
      for (const entry of installed) keepIds.add(entry.value.id);
    } else {
      const inactive = installed.filter(entry => !keepIds.has(entry.value.id));
      inactive.sort((a, b) => newer(a.value, b.value));
      if (inactive.length) keepIds.add(inactive[0].value.id);
    }
    const removeEntries = [];
    for (const entry of installed) {
      if (keepIds.has(entry.value.id)) keepNames.add(entry.value.cacheName);
      else removeEntries.push(entry);
    }
    for (const entry of entries) {
      const match = /^(client|ready|download)\/([^/]+)$/.exec(entry.path);
      if (!match) continue;
      let clientId;
      try { clientId = decodeURIComponent(match[2]); } catch (_) { removeEntries.push(entry); continue; }
      if (!retainedClientIds.has(clientId)) { removeEntries.push(entry); continue; }
      if (match[1] !== 'client') {
        if (ownsCache(entry.value?.cacheName)) keepNames.add(entry.value.cacheName);
        else preserveAllStages = true;
      }
    }
    // Malformed live state cannot identify which installed/staging cache is in
    // use. Defer all cache eviction rather than risking a running player's data.
    if (preserveAllStages) {
      stats.conservative = true;
      const buildEntries = new Set(installed);
      for (let i = removeEntries.length - 1; i >= 0; i--) {
        if (buildEntries.has(removeEntries[i])) removeEntries.splice(i, 1);
      }
      stats.keptBuilds = installed.length;
    } else {
      stats.conservative = unknownLiveClient;
      stats.keptBuilds = installed.filter(entry => keepIds.has(entry.value.id)).length;
    }
    for (const entry of removeEntries) if (await meta.delete(entry.request)) stats.deletedMetadata++;
    if (!preserveAllStages) {
      // This also reclaims sealed orphans and downloads belonging to closed tabs.
      // References and persistent in-flight markers are stable under the lock.
      for (const name of await caches.keys()) {
        if (ownsCache(name) && !keepNames.has(name) && await caches.delete(name)) stats.deletedCaches++;
      }
    }
    return stats;
  }
  root.CloudMusicUpdateRetention = { prune };
})(globalThis);
