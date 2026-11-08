/* Google Drive 授权只保存在内存；媒体完整缓冲后通过临时 Blob URL 播放。 */
(() => {
  'use strict';
  const SCOPE = 'https://www.googleapis.com/auth/drive.readonly';
  class AuthError extends Error {}
  const MAX_BYTES = 100 * 1024 * 1024;
  let gisLoading;
  function loadGis() {
    if (globalThis.google?.accounts?.oauth2) return Promise.resolve();
    if (!gisLoading) {
      gisLoading = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = 'https://accounts.google.com/gsi/client';
        script.async = true;
        const fail = () => { script.remove(); gisLoading = null; reject(new Error('无法加载 Google 授权服务，请重试。')); };
        const timer = setTimeout(fail, 15000);
        script.onload = () => { clearTimeout(timer); resolve(); };
        script.onerror = () => { clearTimeout(timer); fail(); };
        document.head.appendChild(script);
      });
    }
    return gisLoading;
  }
  globalThis.createGoogleDrivePlatform = (clientId, listener) => {
    let token = null, expiresAt = 0, pendingAuth = null, disposed = false;
    let epoch = 0, controller = null, audio = null, blobUrl = null, state = {};
    let volume = 1;
    const emit = (patch) => { state = { ...state, ...patch }; if (!disposed) listener({ ...state }); };
    const currentAuth = () => token && Date.now() < expiresAt ? { accessToken: token, expiresAt } : null;
    function clearAudio() {
      epoch++;
      controller?.abort(); controller = null;
      if (audio) { const old = audio; audio = null; old.pause(); old.removeAttribute('src'); old.load(); }
      if (blobUrl) { URL.revokeObjectURL(blobUrl); blobUrl = null; }
    }
    const stop = () => {
      clearAudio();
      emit({ id: null, playing: false, loading: false, completed: false, resumable: false, position: 0, duration: 0, error: null });
    };
    async function authorize(interactive) {
      if (disposed) throw new AuthError('连接已关闭。');
      if (!clientId) throw new AuthError('尚未配置 GOOGLE_DRIVE_WEB_CLIENT_ID。');
      const existing = currentAuth();
      if (!interactive) return existing;
      if (pendingAuth) return pendingAuth.promise;
      let settle;
      const promise = new Promise((resolve, reject) => { settle = (error, result) => error ? reject(error) : resolve(result); });
      const pending = { promise, cancel: () => finish(new AuthError('Google 授权已取消。')) };
      pendingAuth = pending;
      let timer;
      function finish(error, result) {
        if (pendingAuth !== pending) return;
        clearTimeout(timer); pendingAuth = null; settle(error, result);
      }
      timer = setTimeout(() => finish(new AuthError('Google 授权超时，请重新连接。')), 120000);
      // 首次点击只加载组件，下一次点击同步弹窗，避免等待网络导致用户激活失效。
      if (!globalThis.google?.accounts?.oauth2) {
        loadGis().then(() => finish(new AuthError('授权组件已准备好，请再次点击连接。')))
          .catch(() => finish(new AuthError('无法打开 Google 授权服务，请重试。')));
        return promise;
      }
      // 不进行静默刷新；弹窗仅由本次用户点击同步触发。
      try {
        if (pendingAuth !== pending || disposed) return;
        const oauth = google.accounts.oauth2;
        const client = oauth.initTokenClient({
          client_id: clientId, scope: SCOPE, include_granted_scopes: false,
          callback: response => {
            if (pendingAuth !== pending || disposed) return;
            if (response.error || !response.access_token) { finish(new AuthError('Google 授权未完成或被拒绝。')); return; }
            if (!oauth.hasGrantedAllScopes(response, SCOPE)) { finish(new AuthError('需要 Google Drive 只读权限才能列出文件夹。')); return; }
            const lifetime = Number(response.expires_in);
            if (!Number.isFinite(lifetime) || lifetime <= 30) { finish(new AuthError('Google 授权已过期，请重试。')); return; }
            token = response.access_token;
            expiresAt = Date.now() + (lifetime - 30) * 1000;
            finish(null, currentAuth());
          },
          error_callback: () => finish(new AuthError('Google 授权窗口被关闭或被浏览器拦截，请点击连接重试。')),
        });
        client.requestAccessToken({ prompt: 'consent' });
      } catch (_) { finish(new AuthError('无法打开 Google 授权服务，请重试。')); }
      return promise;
    }
    async function disconnect() {
      pendingAuth?.cancel();
      const previous = token; token = null; expiresAt = 0;
      stop();
      if (previous) {
        if (!globalThis.google?.accounts?.oauth2) throw new Error('本地会话已清除，但未能撤销 Google 授权。');
        await new Promise((resolve, reject) => {
          const fail = () => reject(new Error('本地会话已清除，但未能确认 Google 授权已撤销。'));
          const timer = setTimeout(fail, 5000);
          try {
            google.accounts.oauth2.revoke(previous, response => {
              clearTimeout(timer);
              if (response?.successful === true && !response.error) resolve();
              else fail();
            });
          } catch (_) { clearTimeout(timer); fail(); }
        });
      }
    }
    async function play(request) {
      stop();
      if (disposed) return;
      const run = epoch;
      emit({ id: request.id, loading: true });
      controller = new AbortController();
      const activeController = controller;
      try {
        if (typeof request.fileId !== 'string' || !/^[A-Za-z0-9_-]{1,256}$/.test(request.fileId)) throw new Error('Google Drive 文件编号无效。');
        if (!currentAuth() || token !== request.accessToken) throw new Error('Google 授权已过期，请重新连接。');
        if (Number(request.size) > MAX_BYTES) throw new Error('网页版单曲限制为 100 MiB，请使用原生应用播放此文件。');
        // 忽略调用方 URL，只允许固定的 Drive API；拒绝重定向以免泄露凭据。
        const response = await fetch(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(request.fileId)}?alt=media&supportsAllDrives=true`, {
          headers: { Authorization: `Bearer ${token}` }, signal: activeController.signal,
          redirect: 'error', credentials: 'omit', cache: 'no-store',
        });
        if (!response.ok) {
          if (response.status === 401 && run === epoch) { token = null; expiresAt = 0; }
          throw new Error(response.status === 401 ? 'Google 授权已失效，请重新连接。' : '无法读取 Google Drive 音频，请检查权限和网络。');
        }
        if (Number(response.headers.get('content-length')) > MAX_BYTES) throw new Error('网页版单曲限制为 100 MiB。');
        if (!response.body?.getReader) throw new Error('此浏览器不支持有界音频下载。');
        const reader = response.body.getReader();
        const chunks = []; let bytes = 0;
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (run !== epoch || disposed) { await reader.cancel(); return; }
            if (done) break;
            bytes += value.byteLength;
            if (bytes > MAX_BYTES) { await reader.cancel(); throw new Error('网页版单曲限制为 100 MiB。'); }
            chunks.push(value);
          }
        } finally { reader.releaseLock(); }
        if (run !== epoch || disposed) return;
        blobUrl = URL.createObjectURL(new Blob(chunks, { type: request.mimeType || 'application/octet-stream' }));
        const element = new Audio(); audio = element; element.volume = volume;
        const valid = () => run === epoch && audio === element && !disposed;
        const update = () => {
          if (!valid()) return;
          emit({ position: Number.isFinite(element.currentTime) ? element.currentTime : 0,
            duration: Number.isFinite(element.duration) ? element.duration : 0, playing: !element.paused, loading: false });
        };
        for (const name of ['timeupdate', 'loadedmetadata', 'play', 'pause', 'durationchange']) element.addEventListener(name, update);
        element.addEventListener('ended', () => { if (valid()) emit({ completed: true, playing: false, loading: false }); });
        element.addEventListener('error', () => { if (valid()) { clearAudio(); emit({ error: '浏览器无法解码此音频格式。', playing: false, loading: false, resumable: false }); } });
        element.src = blobUrl;
        try { await element.play(); if (valid()) update(); }
        catch (error) {
          if (valid()) {
            if (error?.name === 'NotAllowedError') emit({ error: '浏览器暂停了自动播放，请点击播放继续。', playing: false, loading: false, resumable: true });
            else { clearAudio(); emit({ error: '浏览器无法播放此音频。', playing: false, loading: false, resumable: false }); }
          }
        }
      } catch (error) {
        if (run !== epoch || disposed) return;
        clearAudio();
        emit({ loading: false, playing: false, resumable: false, error: error instanceof Error && !['TypeError', 'AbortError'].includes(error.name) ? error.message : 'Google Drive 音频加载失败，请检查网络后重试。' });
      }
    }
    return {
      initialize: async () => {},
      authorize,
      // 仅跨桥传递应用内定义的错误，不能透传服务端消息或令牌。
      authorizeResult: async interactive => {
        try { return await authorize(interactive); }
        catch (error) { return { error: error instanceof AuthError ? error.message : 'Google 授权未完成，请重新连接。' }; }
      },
      cancelAuthorization: () => { pendingAuth?.cancel(); },
      disconnect,
      play,
      pause: async () => { audio?.pause(); },
      resume: async () => {
        const element = audio;
        if (!element) return;
        try { await element.play(); if (audio === element) emit({ error: null, playing: true, completed: false, resumable: false }); }
        catch (error) {
          if (audio === element) {
            if (error?.name === 'NotAllowedError') emit({ error: '浏览器未允许播放，请再次点击播放。', playing: false, resumable: true });
            else { clearAudio(); emit({ error: '浏览器无法播放此音频。', playing: false, loading: false, resumable: false }); }
          }
        }
      },
      seek: async seconds => { if (audio && Number.isFinite(seconds)) audio.currentTime = Math.max(0, seconds); },
      setVolume: async value => { volume = Math.max(0, Math.min(1, value)); if (audio) audio.volume = volume; },
      stop: async () => stop(),
      dispose: async () => { pendingAuth?.cancel(); stop(); token = null; expiresAt = 0; disposed = true; },
    };
  };
})();
