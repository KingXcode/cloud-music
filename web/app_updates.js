(function (root) {
  'use strict';
  const core = root.CloudMusicUpdateCore;
  let workerPromise, operation = null, ready = null, lastManifest = null, generation = 0, checkOperation = null;
  function configuration() {
    const value = root.CLOUD_MUSIC_BUILD;
    if (!value || !/^[a-f0-9]{64}$/.test(value.id)) {
      throw new Error('开发预览不提供网页更新，请使用已部署的发布版本。');
    }
    return { ...value, base: core.baseURL(value.base, root.location.origin) };
  }
  function request(worker, action, payload = {}, progress, timeout = 20000) {
    return new Promise((resolve, reject) => {
      const channel = new MessageChannel();
      let timer;
      const finish = (error, value) => {
        clearTimeout(timer); channel.port1.close();
        error ? reject(error) : resolve(value);
      };
      const reset = () => {
        clearTimeout(timer);
        timer = setTimeout(() => finish(new Error('更新服务响应超时，请重试。')), timeout);
      };
      channel.port1.onmessage = event => {
        const message = event.data;
        if (!message) return;
        if (message.type === 'progress') { reset(); progress?.(message.received, message.total); }
        else if (message.type === 'result') finish(null, message.value);
        else if (message.type === 'error') finish(new Error(message.message || '网页更新失败。'));
      };
      reset();
      try { worker.postMessage({ action, ...payload }, [channel.port2]); }
      catch (error) { finish(error); }
    });
  }
  async function connectWorker() {
    const config = configuration();
    if (!root.isSecureContext || !root.navigator.serviceWorker || !root.caches || !root.crypto?.subtle) {
      throw new Error('此浏览器不支持安全的离线更新，请在 HTTPS 浏览器中打开。');
    }
    const manager = root.navigator.serviceWorker;
    const script = new URL('flutter_service_worker.js', config.base);
    const existing = await manager.getRegistration(config.base.href);
    if (existing && existing.scope === config.base.href) {
      for (const worker of [existing.active, existing.waiting, existing.installing]) {
        if (worker && new URL(worker.scriptURL).pathname !== script.pathname) {
          throw new Error('此网址已有其他离线应用，不能覆盖它的更新服务。');
        }
      }
    }
    const registration = await manager.register(script.href, { scope: config.base.href, updateViaCache: 'none' });
    // The legacy Flutter worker can still be active while this worker installs.
    // A protocol handshake prevents sending an update to that legacy worker.
    const deadline = Date.now() + 20000;
    while (Date.now() < deadline) {
      const worker = registration.active;
      if (worker) {
        try {
          const response = await request(worker, 'hello', { runningBuild: { id: config.id, version: config.version, build: config.build } }, null, 1000);
          if (response.protocol === 1) return worker;
        } catch (_) { /* Wait for the replacement worker, never force a reload. */ }
      }
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error('更新服务尚未准备好，请稍后重试。');
  }
  async function ensureWorker() {
    workerPromise ??= connectWorker().catch(error => { workerPromise = null; throw error; });
    const worker = await workerPromise;
    if (worker.state === 'redundant') {
      workerPromise = null;
      return ensureWorker();
    }
    return worker;
  }
  function aborted() { return new Error('更新下载已取消。'); }
  root.cloudMusicUpdates = {
    getInstalledVersion() {
      const value = root.CLOUD_MUSIC_BUILD;
      // Register every running build so cache retention can protect live tabs.
      if (value && /^[a-f0-9]{64}$/.test(value.id)) ensureWorker().catch(() => {});
      return { version: value?.version || '开发版本', build: value?.build || '0', platform: 'web', architecture: 'browser' };
    },
    async check() {
      const config = configuration();
      const url = new URL('cloud-music-release.json', config.base);
      url.searchParams.set('check', String(Date.now()));
      checkOperation?.abort();
      const controller = new AbortController();
      checkOperation = controller;
      let timer;
      const resetTimer = () => {
        clearTimeout(timer);
        timer = setTimeout(() => controller.abort(), 20000);
      };
      let manifest;
      resetTimer();
      try {
        const response = await fetch(url.href, { signal: controller.signal, cache: 'no-store', credentials: 'same-origin', redirect: 'error' });
        if (!response.ok) throw new Error(`检查更新失败（HTTP ${response.status}）。`);
        const reader = response.body?.getReader();
        if (!reader) throw new Error('更新清单为空。');
        const chunks = []; let length = 0;
        try {
          for (;;) {
            const result = await reader.read();
            if (result.done) break;
            resetTimer(); length += result.value.byteLength;
            if (length > 4 * 1024 * 1024) throw new Error('更新清单过大。');
            chunks.push(result.value);
          }
        } catch (error) { await reader.cancel().catch(() => {}); throw error; }
        finally { reader.releaseLock(); }
        if (controller.signal.aborted) throw new Error('检查更新已取消或超时，请重试。');
        manifest = core.validateManifest(JSON.parse(await new Blob(chunks).text()));
        if (controller.signal.aborted) throw new Error('检查更新已取消或超时，请重试。');
        if (core.isOlder(manifest, config)) throw new Error('服务器提供的版本较旧，已阻止降级。');
      } catch (error) {
        if (controller.signal.aborted) throw new Error('检查更新已取消或超时，请重试。');
        throw error;
      } finally {
        clearTimeout(timer);
        if (checkOperation === controller) checkOperation = null;
      }
      lastManifest = manifest;
      if (manifest.id === config.id) return null;
      // Different content with identical numbers is not safely orderable across
      // tabs. Every content/configuration redeploy must increment its build number.
      if (core.compareVersions(manifest.version, config.version) === 0 && Number(manifest.build) === Number(config.build)) {
        throw new Error('同一版本和构建号对应不同内容，请提高构建号后重新发布。');
      }
      return { version: manifest.version, build: manifest.build, notes: manifest.notes,
        releasePage: config.base.href, id: manifest.id, size: manifest.totalBytes,
        url: new URL('cloud-music-release.json', config.base).href };
    },
    async download(id, onProgress) {
      if (operation && !operation.cancelled) throw new Error('已有更新正在下载。');
      const attempt = ++generation;
      if (operation) {
        await operation.finished;
        if (attempt !== generation) throw aborted();
        if (operation) throw new Error('已有更新正在下载。');
      }
      if (!lastManifest || lastManifest.id !== id) throw new Error('请重新检查更新。');
      const current = { id: root.crypto.randomUUID(), cancelled: false, worker: null };
      current.finished = new Promise(resolve => { current.finish = resolve; });
      operation = current;
      ready = null;
      try {
        current.worker = await ensureWorker();
        if (current.cancelled) throw aborted();
        const result = await request(current.worker, 'download', { operationId: current.id, manifest: lastManifest },
          (received, total) => { if (!current.cancelled) onProgress(received, total); }, 120000);
        if (current.cancelled) throw aborted();
        ready = { id, token: result.token, worker: current.worker };
      } catch (error) {
        // A lost response is not permission to promote a partially downloaded cache.
        current.worker?.postMessage({ action: 'cancel', operationId: current.id });
        throw error;
      } finally { if (operation === current) operation = null; current.finish(); }
    },
    async install(id) {
      if (!ready || ready.id !== id || operation) throw new Error('请先完整下载新版。');
      const current = ready;
      await request(await ensureWorker(), 'install', { id, token: current.token });
      ready = null;
      const url = configuration().base.href;
      // Only this explicit method navigates. Check/download/worker activation do not.
      setTimeout(() => root.location.replace(url), 100);
      return '新版已准备好，正在重新载入。';
    },
    cancel() {
      ++generation;
      checkOperation?.abort();
      if (!operation) return;
      operation.cancelled = true;
      operation.worker?.postMessage({ action: 'cancel', operationId: operation.id });
    },
  };
})(globalThis);
