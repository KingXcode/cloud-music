/* Browser-only original-file playback. Never uploads or persists audio bytes. */
(() => {
  'use strict';
  const META = 'cloud-music-browser-v1';
  const extensions = /\.(mp3|m4a|aac|wav|wave|flac|ogg|oga|opus|aif|aiff|alac|mp4|webm)$/i;
  const missing = e => e?.name === 'NotFoundError';
  const aborted = e => e?.name === 'AbortError';
  const messageFor = e => missing(e) ? '找不到原始文件，请连接原来的磁盘后刷新。' :
    e?.name === 'SecurityError' ? '浏览器安全限制阻止了文件夹访问。请在独立的 HTTPS 页面中直接点击选择；嵌入式或受限浏览器可能不支持此操作。' :
    e?.name === 'NotAllowedError' ? '浏览器未允许读取文件夹。请点击刷新重新授权，或重新选择文件夹。' :
    '无法读取原始文件。请确认磁盘已连接、云端文件已下载，再点击刷新。';

  async function database() {
    return new Promise((resolve, reject) => {
      const r = indexedDB.open('cloud-music-handles', 1);
      r.onupgradeneeded = () => r.result.createObjectStore('handles');
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
      r.onblocked = () => reject(new Error('Database blocked'));
    });
  }
  async function savedHandle(value, write = false) {
    const db = await database();
    try {
      return await new Promise((resolve, reject) => {
        const tx = db.transaction('handles', write ? 'readwrite' : 'readonly');
        const store = tx.objectStore('handles');
        const request = write ? (value ? store.put(value, 'root') : store.delete('root')) : store.get('root');
        let result;
        request.onsuccess = () => { result = request.result; };
        tx.oncomplete = () => resolve(result);
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
    } finally { db.close(); }
  }

  window.createCloudMusicGateway = listener => {
    const audio = new Audio();
    const browser = window.navigator || {};
    // iPadOS may identify as macOS. Even where directory inputs are supported,
    // individual files are the more reliable path through iOS file providers.
    const appleMobile = /iPhone|iPad|iPod/.test(browser.userAgent || '') ||
      (browser.platform === 'MacIntel' && browser.maxTouchPoints > 1);
    const filesOnly = appleMobile || (typeof window.showDirectoryPicker !== 'function' &&
      !('webkitdirectory' in document.createElement('input')));
    audio.preload = 'metadata';
    const state = {folderName: null, sourceKind: 'web', selectionMode: filesOnly ? 'files' : 'folder', tracks: [], currentTrackId: null,
      isPlaying: false, isLoading: false, isScanning: false, shuffle: false,
      positionMs: 0, durationMs: 0, repeatMode: 'off', volume: 1, message: null};
    let root = null, entries = new Map(), disposed = false, initialized = false;
    let playGeneration = 0, scanGeneration = 0, url = null, picking = false, permissionBusy = false;
    let pickerCleanup = null;
    const history = [], shuffleVisited = new Set();
    const snapshot = () => ({...state, tracks: state.tracks.map(t => ({...t}))});
    function save() {
      try {
        localStorage.setItem(META, JSON.stringify({folderName: state.folderName,
          tracks: state.tracks, shuffle: state.shuffle, repeatMode: state.repeatMode, volume: state.volume}));
      } catch (_) { /* Private mode/quota: current-session playback still works. */ }
    }
    function emit(persist = false) {
      if (disposed) return;
      if (persist) save();
      listener(snapshot());
    }
    function clearAudio() {
      ++playGeneration;
      audio.pause();
      audio.removeAttribute('src');
      audio.load();
      if (url) URL.revokeObjectURL(url);
      url = null;
      state.isPlaying = false;
      state.isLoading = false;
      state.positionMs = 0;
      state.durationMs = 0;
    }
    function status(id, statusValue) {
      state.tracks = state.tracks.map(t => t.id === id ? {...t, status: statusValue} : t);
    }
    const finiteMs = v => Number.isFinite(v) && v > 0 ? Math.round(v * 1000) : 0;
    const listeners = [];
    function on(type, callback) { audio.addEventListener(type, callback); listeners.push([type, callback]); }
    on('timeupdate', () => { state.positionMs = finiteMs(audio.currentTime); emit(); });
    on('durationchange', () => {
      if (!url) return;
      state.durationMs = finiteMs(audio.duration);
      state.tracks = state.tracks.map(t => t.id === state.currentTrackId ? {...t, durationMs: state.durationMs} : t);
      emit();
    });
    on('playing', () => { if (!url) return; state.isPlaying = true; state.isLoading = false; emit(); });
    on('pause', () => { state.isPlaying = false; emit(); });
    on('waiting', () => { if (url && !audio.paused) { state.isLoading = true; emit(); } });
    on('canplay', () => { state.isLoading = false; emit(); });
    on('error', () => {
      if (!url || !audio.error) return;
      state.isPlaying = false; state.isLoading = false;
      const unsupported = audio.error.code === 3 || audio.error.code === 4;
      status(state.currentTrackId, unsupported ? 'unsupported' : 'unknown');
      state.message = unsupported ? '浏览器无法解码这首音频。可尝试其他歌曲或浏览器。' : '播放中断，请确认原始文件可用后重试。';
      emit(true);
    });
    on('ended', () => {
      state.isPlaying = false; state.isLoading = false;
      if (state.repeatMode === 'one') void play(state.currentTrackId, false, true);
      else void advance(1, true);
    });

    async function scan(handle, explicit, replacing = false) {
      const generation = ++scanGeneration;
      // A confirmed new selection invalidates any pending old-file read now.
      if (replacing) clearAudio();
      state.isScanning = true; state.message = null; emit();
      const found = new Map(), failed = [], directoryChildren = new Map();
      let rootError = null;
      async function walk(directory, prefix) {
        try {
          for await (const [name, child] of directory.entries()) {
            if (disposed || generation !== scanGeneration) return;
            const path = prefix + name;
            if (!directoryChildren.has(prefix)) directoryChildren.set(prefix, []);
            directoryChildren.get(prefix).push({name, kind: child.kind});
            if (child.kind === 'directory') await walk(child, path + '/');
            else if (extensions.test(name)) found.set(path, {handle: child});
          }
        } catch (e) { if (!prefix) rootError = e; failed.push(prefix); }
      }
      await walk(handle, '');
      if (disposed || generation !== scanGeneration) return;
      if (rootError) { state.isScanning = false; state.message = messageFor(rootError); emit(); return; }
      // Absence from a listing is not proof: cloud/removable providers may
      // temporarily return empty or incomplete listings without throwing.
      async function confirmedMissing(path) {
        if (failed.length) return false;
        const parts = path.split('/');
        const name = parts.pop();
        const prefix = parts.length ? parts.join('/') + '/' : '';
        const siblings = (directoryChildren.get(prefix) || []).filter(child => child.name !== name);
        if (!siblings.length) return false; // No positive evidence the parent is mounted.
        try {
          let parent = handle;
          for (const part of parts) parent = await parent.getDirectoryHandle(part);
          try { await parent.getFileHandle(name); return false; }
          catch (e) { if (!missing(e)) return false; }
          // Re-open a listed sibling, without opening its audio bytes.
          let healthy = false;
          for (const sibling of siblings) {
            try {
              if (sibling.kind === 'directory') await parent.getDirectoryHandle(sibling.name);
              else await parent.getFileHandle(sibling.name);
              healthy = true; break;
            } catch (_) {}
          }
          if (!healthy || await handle.queryPermission({mode: 'read'}) !== 'granted') return false;
          // Check absence again after the positive health/permission checks.
          try { await parent.getFileHandle(name); return false; }
          catch (e) { return missing(e); }
        } catch (_) { return false; }
      }
      let unconfirmed = false;
      const old = new Map((replacing ? [] : state.tracks).map(t => [t.id, t]));
      const tracks = [];
      for (const [path] of found) {
        const prior = old.get(path);
        tracks.push({...prior, id: path, title: prior?.title || path.split('/').pop().replace(/\.[^.]+$/, ''),
          artist: prior?.artist || '', album: prior?.album || '', relativePath: path,
          // A directory listing cannot prove cloud bytes are available offline.
          status: prior?.status === 'unsupported' ? 'unsupported' : 'unknown', durationMs: prior?.durationMs || 0});
      }
      for (const [id, track] of old) {
        if (found.has(id)) continue;
        const confirmed = await confirmedMissing(id);
        if (disposed || generation !== scanGeneration) return;
        if (!confirmed) unconfirmed = true;
        if (!explicit || !confirmed) {
          tracks.push({...track, status: confirmed ? 'missing' : 'unknown'});
          if (entries.has(id)) found.set(id, entries.get(id));
        }
      }
      if (replacing) {
        clearAudio(); history.length = 0; state.currentTrackId = null;
        root = handle; state.folderName = handle.name;
        try { await savedHandle(handle, true); }
        catch (_) { state.message = '浏览器无法保存文件夹授权，下次打开可能需要重新选择。'; }
        if (disposed || generation !== scanGeneration) return;
      }
      state.isScanning = false;
      entries = found;
      state.tracks = tracks.sort((a, b) => a.relativePath.localeCompare(b.relativePath, 'zh-CN', {numeric: true}));
      if (state.currentTrackId && !state.tracks.some(t => t.id === state.currentTrackId)) {
        clearAudio(); state.currentTrackId = null;
      }
      if (failed.length) state.message = '部分子文件夹无法读取，已保留其中的原有歌曲。请检查权限或磁盘后刷新。';
      else if (unconfirmed) state.message = '部分原有歌曲暂时无法确认是否仍在原处，已保留。请检查磁盘、云端下载和权限后刷新。';
      else if (!tracks.length) state.message = '这个文件夹中没有找到支持识别的音频文件。';
      emit(true);
    }

    function acceptFiles(files) {
      const next = new Map(), tracks = [];
      for (const file of files) {
        if (!extensions.test(file.name) && !file.type?.startsWith('audio/')) continue;
        const path = file.webkitRelativePath?.split('/').slice(1).join('/') || file.name;
        // A multi-file selection can contain equal names from different sources.
        let id = path, duplicate = 1;
        while (next.has(id)) id = `${path} [${++duplicate}]`;
        next.set(id, {file});
        tracks.push({id, title: file.name.replace(/\.[^.]+$/, ''), artist: '', album: '',
          relativePath: path, status: 'unknown', durationMs: 0});
      }
      if (!tracks.length) {
        state.message = '没有找到可识别的音频文件。请选择 MP3、M4A 等音乐文件；已保留原资料库。';
        emit(); return;
      }
      ++scanGeneration; clearAudio(); root = null; history.length = 0; shuffleVisited.clear();
      entries = next;
      state.folderName = filesOnly ? '已选音乐文件' :
        (files[0].webkitRelativePath?.split('/')[0] || '已选音乐文件');
      state.currentTrackId = null;
      state.tracks = tracks.sort((a, b) => a.relativePath.localeCompare(b.relativePath, 'zh-CN', {numeric: true}));
      state.message = filesOnly
        ? '已选择音乐文件。重新打开网页后需再次选择，音频不会上传。iCloud 文件可能先由系统下载。'
        : '当前浏览器使用文件夹选择模式，重新打开或刷新时需要再次选择原文件夹。音频不会上传。';
      // Persisting a cleared handle must not hold the UI hostage to IndexedDB.
      void savedHandle(null, true).catch(() => {});
      emit(true);
    }
    function fallbackPick() {
      // Some iOS/provider combinations send neither change nor cancel. Do not
      // await these events: the command ends after opening the native sheet.
      // A later user gesture can always discard an abandoned input and retry.
      pickerCleanup?.();
      ++scanGeneration;
      const input = document.createElement('input');
      input.type = 'file'; input.multiple = true; input.tabIndex = -1;
      if (filesOnly) input.accept = 'audio/*,.mp3,.m4a,.aac,.wav,.wave,.flac,.ogg,.oga,.opus,.aif,.aiff,.alac,.mp4,.webm';
      else input.setAttribute('webkitdirectory', '');
      input.setAttribute('aria-hidden', 'true');
      Object.assign(input.style, {position: 'fixed', left: '-10000px', width: '1px', height: '1px', opacity: '0'});
      document.body.append(input);
      let settled = false;
      const cleanup = () => finish(null);
      const finish = files => {
        if (settled) return;
        settled = true; input.remove();
        if (pickerCleanup === cleanup) pickerCleanup = null;
        if (disposed || !files?.length) return;
        try { acceptFiles(files); }
        catch (e) { state.message = messageFor(e); emit(); }
      };
      pickerCleanup = cleanup;
      input.addEventListener('cancel', () => finish(null), {once: true});
      input.addEventListener('change', () => finish(Array.from(input.files || [])), {once: true});
      try { input.click(); }
      catch (e) { cleanup(); throw e; }
    }
    async function pick() {
      if (picking || state.isScanning || permissionBusy) return;
      picking = true;
      try {
        if (!filesOnly && typeof window.showDirectoryPicker === 'function') {
          const handle = await window.showDirectoryPicker({mode: 'read', id: 'cloud-music-library'});
          await scan(handle, true, true);
        } else {
          fallbackPick();
        }
      } catch (e) { if (!aborted(e)) { state.message = messageFor(e); emit(); } }
      finally { picking = false; }
    }

    async function refresh() {
      if (state.isScanning || picking || permissionBusy) return;
      if (!root) return pick();
      permissionBusy = true;
      try {
        // Invoked directly from the click handler, before any async boundary.
        // requestPermission is never called during initialize or background scan.
        const permission = await root.requestPermission({mode: 'read'});
        if (permission !== 'granted') {
          state.message = '未获得文件夹读取权限。请点击刷新再次授权，或重新选择文件夹。'; emit(); return;
        }
        await scan(root, true);
      } catch (e) { state.message = messageFor(e); emit(); }
      finally { permissionBusy = false; }
    }

    async function play(id, remember = true, continueCycle = false) {
      if (!id || disposed) return;
      const entry = entries.get(id);
      if (!entry) {
        state.message = filesOnly ? '请重新选择音乐文件以恢复播放。' : '请点击刷新授权原文件夹；此浏览器若不支持记住文件夹，请重新选择。'; emit(); return;
      }
      if (!continueCycle) shuffleVisited.clear();
      shuffleVisited.add(id);
      const oldId = state.currentTrackId;
      clearAudio(); const generation = playGeneration;
      state.currentTrackId = id; state.isLoading = true; state.message = null; emit();
      if (remember && oldId && oldId !== id) history.push(oldId);
      try {
        const file = entry.file || await entry.handle.getFile();
        if (disposed || generation !== playGeneration) return;
        url = URL.createObjectURL(file); audio.src = url; audio.volume = state.volume;
        status(id, 'ready');
        await audio.play();
        if (disposed || generation !== playGeneration) return;
        state.isLoading = false; state.isPlaying = !audio.paused; emit(true);
      } catch (e) {
        if (disposed || generation !== playGeneration) return;
        state.isLoading = false; state.isPlaying = false;
        if (e?.name === 'NotAllowedError' && url) state.message = '浏览器阻止了自动播放，请再次点击播放。';
        else {
          const unsupported = e?.name === 'NotSupportedError';
          status(id, unsupported ? 'unsupported' : 'unknown');
          state.message = unsupported ? '浏览器不支持这首音频的编码，可尝试其他歌曲。' : messageFor(e);
        }
        emit(true);
      }
    }
    async function advance(direction, ended = false) {
      const ids = state.tracks.filter(t => t.status !== 'missing' && t.status !== 'unsupported').map(t => t.id);
      if (!ids.length) { emit(); return; }
      if (direction < 0 && audio.currentTime > 3 && url) { audio.currentTime = 0; emit(); return; }
      if (direction < 0 && state.shuffle && history.length) return play(history.pop(), false, true);
      let next;
      if (state.shuffle && ids.length > 1) {
        let choices = ids.filter(id => !shuffleVisited.has(id));
        if (!choices.length) {
          if (state.repeatMode !== 'all') { emit(); return; }
          shuffleVisited.clear();
          choices = ids.filter(id => id !== state.currentTrackId);
        }
        next = choices[Math.floor(Math.random() * choices.length)];
      } else {
        const index = ids.indexOf(state.currentTrackId);
        const target = index + direction;
        if (ended && target >= ids.length && state.repeatMode === 'off') { emit(); return; }
        next = ids[(target + ids.length) % ids.length];
      }
      await play(next, true, true);
    }

    return {
      async initialize() {
        if (initialized) return snapshot();
        initialized = true;
        try {
          const cached = JSON.parse(localStorage.getItem(META) || 'null');
          if (cached) {
            state.folderName = typeof cached.folderName === 'string' ? cached.folderName : null;
            state.tracks = Array.isArray(cached.tracks) ? cached.tracks.filter(t => typeof t.id === 'string' && typeof t.relativePath === 'string').map(t => ({...t, status: 'unknown'})) : [];
            state.shuffle = cached.shuffle === true;
            state.repeatMode = ['off', 'all', 'one'].includes(cached.repeatMode) ? cached.repeatMode : 'off';
            state.volume = Number.isFinite(cached.volume) ? Math.max(0, Math.min(1, cached.volume)) : 1;
            audio.volume = state.volume;
          }
        } catch (_) {}
        if (filesOnly) {
          if (state.folderName) state.message = '请重新选择音乐文件以恢复播放；网页不会保存音频或持续读取 iCloud 文件夹。';
          return snapshot();
        }
        // Capture the revision before scheduling: a fresh file selection must win
        // even when it happens before this startup task gets its first turn.
        const generation = scanGeneration;
        // Return cached metadata immediately. Restore/validate handles in background.
        setTimeout(async () => {
          try {
            const handle = await savedHandle();
            if (disposed || generation !== scanGeneration || picking) return;
            if (handle && typeof handle.queryPermission === 'function') {
              root = handle;
              const permission = await handle.queryPermission({mode: 'read'});
              if (disposed || generation !== scanGeneration || picking) return;
              if (permission === 'granted') await scan(handle, false);
              else { state.message = '已记住原文件夹，请点击刷新授予读取权限。'; emit(); }
            } else if (state.folderName) {
              state.message = '请重新选择原文件夹以恢复播放；当前浏览器没有可恢复的文件夹授权。'; emit();
            }
          } catch (_) {
            if (!disposed && generation === scanGeneration && state.folderName) {
              state.message = '浏览器无法恢复文件夹授权，请重新选择原文件夹。'; emit();
            }
          }
        }, 0);
        return snapshot();
      },
      async command(method, args = {}) {
        if (disposed) return;
        switch (method) {
          case 'initialize': return this.initialize();
          case 'pickFolder': return pick();
          case 'refresh': return refresh();
          case 'play': return play(args.id);
          case 'togglePlayback':
            if (!audio.paused) { audio.pause(); state.isLoading = false; emit(); return; }
            if (url) {
              try { await audio.play(); } catch (_) { state.message = '播放未能开始，请再点击播放或检查文件是否可用。'; emit(); }
              return;
            }
            return play(state.currentTrackId || state.tracks[0]?.id);
          case 'pause': ++playGeneration; audio.pause(); state.isLoading = false; emit(); return;
          case 'cancelLoading': clearAudio(); emit(); return;
          case 'next': return advance(1);
          case 'previous': return advance(-1);
          case 'seek':
            if (url && Number.isFinite(args.positionMs) && Number.isFinite(audio.duration)) {
              audio.currentTime = Math.max(0, Math.min(audio.duration, args.positionMs / 1000));
              state.positionMs = finiteMs(audio.currentTime); emit();
            }
            return;
          case 'setShuffle':
            state.shuffle = args.enabled === true; history.length = 0; shuffleVisited.clear();
            if (state.currentTrackId) shuffleVisited.add(state.currentTrackId);
            emit(true); return;
          case 'setRepeat': if (['off', 'all', 'one'].includes(args.mode)) state.repeatMode = args.mode; emit(true); return;
          case 'setVolume': if (Number.isFinite(args.volume)) state.volume = Math.max(0, Math.min(1, args.volume)); audio.volume = state.volume; emit(true); return;
          default: throw new Error(`Unknown music command: ${method}`);
        }
      },
      dispose() {
        if (disposed) return;
        disposed = true; ++scanGeneration; pickerCleanup?.();
        for (const [name, callback] of listeners) audio.removeEventListener(name, callback);
        clearAudio(); entries.clear(); root = null;
      }
    };
  };
})();
