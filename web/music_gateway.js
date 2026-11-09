/* 浏览器端直接播放原始文件，不上传或持久化音频字节。 */
(() => {
  'use strict';
  const META = 'cloud-music-browser-v1';
  const newSourceIdentity = () => globalThis.crypto?.randomUUID?.() ||
    `source-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
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
  async function savedHandle(value, write = false, current = () => true) {
    const db = await database();
    try {
      if (!current()) return;
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
    // Safari 18.4 起 iOS/iPadOS 支持目录输入。旧版 WebKit 可能暴露
    // 属性却无法打开目录，因此只排除明确识别的旧系统，保留文件多选退路。
    const appleMobile = /iPhone|iPad|iPod/.test(browser.userAgent || '') ||
      (browser.platform === 'MacIntel' && browser.maxTouchPoints > 1);
    const appleVersion = (browser.userAgent || '').match(/(?:CPU(?: iPhone)? OS|iPhone OS) (\d+)[_.](\d+)/) ||
      (appleMobile && (browser.userAgent || '').match(/Version\/(\d+)\.(\d+)/));
    const legacyApplePicker = appleMobile && appleVersion &&
      (+appleVersion[1] < 18 || (+appleVersion[1] === 18 && +appleVersion[2] < 4));
    const filesOnly = typeof window.showDirectoryPicker !== 'function' &&
      (legacyApplePicker || !('webkitdirectory' in document.createElement('input')));
    audio.preload = 'metadata';
    const state = {folderName: null, sourceKind: 'web', sourceIdentity: newSourceIdentity(), selectionMode: filesOnly ? 'files' : 'folder', canPickFiles: true, importRevision: 0, tracks: [], currentTrackId: null,
      isPlaying: false, isLoading: false, isScanning: false, shuffle: false,
      positionMs: 0, durationMs: 0, repeatMode: 'off', volume: 1, message: null};
    let root = null, entries = new Map(), disposed = false, initialized = false;
    let playGeneration = 0, scanGeneration = 0, url = null, picking = false, permissionBusy = false;
    let pickerCleanup = null, cancelPreparation = null, cancelPickerOperation = null;
    let selectedFiles = !!filesOnly;
    const history = [], shuffleVisited = new Set();
    const snapshot = () => ({...state, tracks: state.tracks.map(t => ({...t}))});
    function save() {
      try {
        localStorage.setItem(META, JSON.stringify({folderName: state.folderName, sourceIdentity: state.sourceIdentity,
          tracks: state.tracks, selectedFiles, shuffle: state.shuffle, repeatMode: state.repeatMode, volume: state.volume}));
      } catch (_) { /* 隐私模式或配额限制不影响当前会话中的播放。 */ }
    }
    function emit(persist = false) {
      if (disposed) return;
      if (persist) save();
      listener(snapshot());
    }
    function clearAudio() {
      ++playGeneration;
      cancelPreparation?.();
      if (state.currentTrackId && state.isLoading) status(state.currentTrackId, entries.has(state.currentTrackId) ? 'unloaded' : 'accessRequired');
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
    on('playing', () => { if (!url) return; state.isPlaying = true; state.isLoading = false; status(state.currentTrackId, 'ready'); emit(); });
    on('pause', () => { state.isPlaying = false; emit(); });
    on('waiting', () => { if (url && !audio.paused) { state.isLoading = true; emit(); } });
    on('canplay', () => { if (!url) return; state.isLoading = false; status(state.currentTrackId, 'ready'); emit(); });
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
      const previous = {root, entries, tracks: state.tracks, folderName: state.folderName,
        sourceIdentity: state.sourceIdentity, selectedFiles};
      // 新选择已确认，即使来源比较或枚举很慢，也不允许旧歌曲的待处理读取自动播放。
      if (replacing && state.isLoading) clearAudio();
      let committed = !replacing;
      let sameSource = handle === root;
      if (replacing && !sameSource && root && typeof handle.isSameEntry === 'function') {
        try { sameSource = await handle.isSameEntry(root); } catch (_) {}
      }
      if (disposed || generation !== scanGeneration) return;
      const old = new Map((replacing ? [] : previous.tracks).map(t => [t.id, t]));
      state.isScanning = true; state.message = null; emit();
      const found = new Map(), failed = [], directoryChildren = new Map();
      let rootError = null, lastPublished = 0;
      function publish() {
        if (disposed || generation !== scanGeneration) return;
        if (!committed) {
          clearAudio(); history.length = 0; shuffleVisited.clear(); state.currentTrackId = null;
          root = handle; selectedFiles = false; state.folderName = handle.name;
          if (!sameSource) state.sourceIdentity = newSourceIdentity();
          entries = new Map(); state.tracks = []; committed = true;
        }
        const currentTracks = new Map(state.tracks.map(t => [t.id, t]));
        for (const [path, entry] of found) {
          entries.set(path, entry);
          const prior = currentTracks.get(path) || old.get(path);
          currentTracks.set(path, {...prior, id: path,
            title: prior?.title || path.split('/').pop().replace(/\.[^.]+$/, ''),
            artist: prior?.artist || '', album: prior?.album || '', relativePath: path,
            status: prior?.status && prior.status !== 'accessRequired' && prior.status !== 'missing'
              ? prior.status : 'unloaded', durationMs: prior?.durationMs || 0});
        }
        state.tracks = [...currentTracks.values()].sort((a, b) => a.relativePath.localeCompare(b.relativePath, 'zh-CN', {numeric: true}));
        lastPublished = found.size;
        emit();
      }
      async function walk(directory, prefix) {
        try {
          for await (const [name, child] of directory.entries()) {
            if (disposed || generation !== scanGeneration) return;
            const path = prefix + name;
            if (!directoryChildren.has(prefix)) directoryChildren.set(prefix, []);
            directoryChildren.get(prefix).push({name, kind: child.kind});
            if (child.kind === 'directory') await walk(child, path + '/');
            else if (extensions.test(name)) {
              found.set(path, {handle: child});
              // 首首立即显示，之后分批发布；不调用 getFile 或读取音频标签。
              if (found.size === 1 || found.size - lastPublished >= 32) publish();
            }
          }
        } catch (e) { if (!prefix) rootError = e; failed.push(prefix); }
        if (!rootError && found.size !== lastPublished) publish();
      }
      await walk(handle, '');
      if (disposed || generation !== scanGeneration) return;
      if (rootError) {
        if (replacing && committed) {
          clearAudio(); history.length = 0; shuffleVisited.clear(); state.currentTrackId = null;
          root = previous.root; entries = previous.entries;
          state.tracks = previous.tracks.map(t => ({...t, status: previous.entries.has(t.id) ? 'unloaded' : 'accessRequired'}));
          state.folderName = previous.folderName; state.sourceIdentity = previous.sourceIdentity; selectedFiles = previous.selectedFiles;
        }
        state.isScanning = false; state.message = messageFor(rootError); emit(true); return;
      }
      publish();
      // 目录列表中未出现文件不能作为缺失证明：云端或可移动存储提供器
      // 可能暂时返回空或不完整的列表，却不抛出异常。
      async function confirmedMissing(path) {
        if (failed.length) return false;
        const parts = path.split('/');
        const name = parts.pop();
        const prefix = parts.length ? parts.join('/') + '/' : '';
        const siblings = (directoryChildren.get(prefix) || []).filter(child => child.name !== name);
        if (!siblings.length) return false; // 没有确切证据表明父目录已挂载。
        try {
          let parent = handle;
          for (const part of parts) parent = await parent.getDirectoryHandle(part);
          try { await parent.getFileHandle(name); return false; }
          catch (e) { if (!missing(e)) return false; }
          // 重新打开已列出的同级文件，但不读取其音频字节。
          let healthy = false;
          for (const sibling of siblings) {
            try {
              if (sibling.kind === 'directory') await parent.getDirectoryHandle(sibling.name);
              else await parent.getFileHandle(sibling.name);
              healthy = true; break;
            } catch (_) {}
          }
          if (!healthy || await handle.queryPermission({mode: 'read'}) !== 'granted') return false;
          // 健康状态和权限检查通过后，再次确认文件是否缺失。
          try { await parent.getFileHandle(name); return false; }
          catch (e) { return missing(e); }
        } catch (_) { return false; }
      }
      let unconfirmed = false;
      const tracks = [];
      const latestTracks = new Map(state.tracks.map(t => [t.id, t]));
      for (const [path] of found) {
        const prior = latestTracks.get(path) || old.get(path);
        tracks.push({...prior, id: path, title: prior?.title || path.split('/').pop().replace(/\.[^.]+$/, ''),
          artist: prior?.artist || '', album: prior?.album || '', relativePath: path,
          // 目录列表不能证明云端文件内容已可离线读取。
          status: prior?.status || 'unloaded', durationMs: prior?.durationMs || 0});
      }
      const discovered = new Set(found.keys());
      for (const [id, track] of old) {
        if (found.has(id)) continue;
        const confirmed = await confirmedMissing(id);
        if (disposed || generation !== scanGeneration) return;
        if (!confirmed) unconfirmed = true;
        if (!explicit || !confirmed) {
          tracks.push({...track, status: confirmed ? 'missing' : (entries.has(id) ? 'unloaded' : 'accessRequired')});
          if (entries.has(id)) found.set(id, entries.get(id));
        }
      }
      state.isScanning = false;
      entries = found;
      // 缺失确认期间可能已经播放或解析了歌曲，保留这些较新的状态。
      const live = new Map(state.tracks.map(t => [t.id, t]));
      for (let i = 0; i < tracks.length; i++) {
        if (discovered.has(tracks[i].id) && live.has(tracks[i].id)) tracks[i] = live.get(tracks[i].id);
      }
      state.tracks = tracks.sort((a, b) => a.relativePath.localeCompare(b.relativePath, 'zh-CN', {numeric: true}));
      if (state.currentTrackId && !state.tracks.some(t => t.id === state.currentTrackId)) {
        clearAudio(); state.currentTrackId = null;
      }
      if (failed.length) state.message = '部分子文件夹无法读取，已保留其中的原有歌曲。请检查权限或磁盘后刷新。';
      else if (unconfirmed) state.message = '部分原有歌曲暂时无法确认是否仍在原处，已保留。请检查磁盘、云端下载和权限后刷新。';
      else if (!tracks.length) state.message = '这个文件夹中没有找到支持识别的音频文件。';
      if (replacing && discovered.size) state.importRevision++;
      emit(true);
      if (replacing) {
        const identity = state.sourceIdentity;
        void savedHandle({handle, sourceIdentity: identity}, true,
          () => !disposed && state.sourceIdentity === identity && root === handle).catch(() => {
          if (disposed || generation !== scanGeneration || state.sourceIdentity !== identity) return;
          state.message = '浏览器无法保存文件夹授权，下次打开可能需要重新选择。'; emit();
        });
      }
    }

    function acceptFiles(files, asFiles) {
      const next = new Map(), tracks = [];
      for (const file of files) {
        if (!extensions.test(file.name) && !file.type?.startsWith('audio/')) continue;
        const path = file.webkitRelativePath?.split('/').slice(1).join('/') || file.name;
        // 文件多选结果可能包含来自不同来源的同名文件。
        let id = path, duplicate = 1;
        while (next.has(id)) id = `${path} [${++duplicate}]`;
        next.set(id, {file});
        tracks.push({id, title: file.name.replace(/\.[^.]+$/, ''), artist: '', album: '',
          relativePath: path, status: 'unloaded', durationMs: 0});
      }
      if (!tracks.length) {
        state.message = '没有找到可识别的音频文件。请选择 MP3、M4A 等音乐文件；已保留原资料库。';
        emit(); return;
      }
      ++scanGeneration; clearAudio(); root = null; history.length = 0; shuffleVisited.clear();
      entries = next;
      // 文件输入无法确认两次选择是否指向同一根目录。
      state.sourceIdentity = newSourceIdentity();
      selectedFiles = asFiles;
      state.folderName = asFiles ? '已选音乐文件' :
        (files[0].webkitRelativePath?.split('/')[0] || '已选音乐文件');
      state.currentTrackId = null;
      state.tracks = tracks.sort((a, b) => a.relativePath.localeCompare(b.relativePath, 'zh-CN', {numeric: true}));
      state.message = asFiles
        ? '已选择音乐文件。重新打开网页后需再次选择，音频不会上传。浏览器无法查询 iCloud 下载状态，系统可能在选择时先下载文件，无法保证等到播放才下载。'
        : '当前浏览器使用文件夹选择模式，重新打开或刷新时需要再次选择原文件夹。浏览器无法查询 iCloud 下载状态，系统可能在选择时先下载文件，无法保证等到播放才下载。音频不会上传。';
      state.importRevision++;
      // 持久化已清空的句柄时，不得因等待 IndexedDB 而卡住界面。
      const generation = scanGeneration;
      void savedHandle(null, true, () => !disposed && generation === scanGeneration && !root).catch(() => {});
      emit(true);
    }
    function fallbackPick(asFiles) {
      // 某些 iOS 与文件提供器组合既不发送 change，也不发送 cancel 事件。
      // 不等待这些事件，命令在打开原生面板后即结束。
      // 后续用户手势始终可以丢弃已放弃的输入并重试。
      pickerCleanup?.();
      ++scanGeneration;
      const input = document.createElement('input');
      input.type = 'file'; input.multiple = true; input.tabIndex = -1;
      if (asFiles) input.accept = 'audio/*,.mp3,.m4a,.aac,.wav,.wave,.flac,.ogg,.oga,.opus,.aif,.aiff,.alac,.mp4,.webm';
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
        try { acceptFiles(files, asFiles); }
        catch (e) { state.message = messageFor(e); emit(); }
      };
      pickerCleanup = cleanup;
      input.addEventListener('cancel', () => finish(null), {once: true});
      input.addEventListener('change', () => finish(Array.from(input.files || [])), {once: true});
      try { input.click(); }
      catch (e) { cleanup(); throw e; }
    }
    async function pick(asFiles = !!filesOnly) {
      if (picking || state.isScanning || permissionBusy) return;
      picking = true;
      let cancel;
      const cancelled = new Promise(resolve => { cancel = resolve; });
      cancelPickerOperation = cancel;
      const operation = async () => {
        if (!asFiles && typeof window.showDirectoryPicker === 'function') {
          pickerCleanup?.();
          const generation = ++scanGeneration;
          const handle = await window.showDirectoryPicker({mode: 'read', id: 'cloud-music-library'});
          if (disposed || generation !== scanGeneration) return;
          await scan(handle, true, true);
        } else {
          fallbackPick(asFiles);
        }
      };
      try {
        // Start the picker synchronously; cancellation also releases the command
        // if a provider never finishes its directory iterator or native picker.
        await Promise.race([operation(), cancelled]);
      } catch (e) { if (!aborted(e)) { state.message = messageFor(e); emit(); } }
      finally {
        if (cancelPickerOperation === cancel) { cancelPickerOperation = null; picking = false; }
      }
    }

    async function refresh() {
      if (state.isScanning || picking || permissionBusy) return;
      if (!root) return pick(selectedFiles);
      permissionBusy = true;
      try {
        // 在任何异步边界之前，直接从点击处理函数中调用。
        // initialize 或后台扫描期间绝不调用 requestPermission。
        const permission = await root.requestPermission({mode: 'read'});
        if (permission !== 'granted') {
          state.message = '未获得文件夹读取权限。请点击刷新再次授权，或重新选择文件夹。'; emit(); return;
        }
        await scan(root, true);
      } catch (e) { state.message = messageFor(e); emit(); }
      finally { permissionBusy = false; }
    }

    // 浏览器不能中止提供器的 getFile，但必须能结束本次等待并丢弃迟到结果。
    function prepare(work) {
      return new Promise((resolve, reject) => {
        let settled = false;
        const finish = (callback, value) => {
          if (settled) return;
          settled = true; clearTimeout(timer);
          if (cancelPreparation === cancel) cancelPreparation = null;
          callback(value);
        };
        const cancel = () => finish(reject, {name: 'AbortError'});
        const timer = setTimeout(() => finish(reject, {name: 'TimeoutError'}), 120000);
        cancelPreparation = cancel;
        try { Promise.resolve(work()).then(value => finish(resolve, value), error => finish(reject, error)); }
        catch (error) { finish(reject, error); }
      });
    }

    async function play(id, remember = true, continueCycle = false) {
      if (!id || disposed) return;
      const entry = entries.get(id);
      if (!entry) {
        state.message = selectedFiles ? '请重新选择音乐文件以恢复播放。' : '请点击刷新授权原文件夹；此浏览器若不支持记住文件夹，请重新选择。'; emit(); return;
      }
      if (!continueCycle) shuffleVisited.clear();
      shuffleVisited.add(id);
      const oldId = state.currentTrackId;
      clearAudio(); const generation = playGeneration;
      state.currentTrackId = id; status(id, 'loading'); state.isLoading = true; state.message = null; emit();
      if (remember && oldId && oldId !== id) history.push(oldId);
      try {
        const file = await prepare(() => entry.file || entry.handle.getFile());
        if (disposed || generation !== playGeneration) return;
        url = URL.createObjectURL(file); audio.src = url; audio.volume = state.volume;
        // 标签解析独立于播放，且旧歌曲、旧资料库的异步结果不可回写。
        const sourceIdentity = state.sourceIdentity;
        const current = () => !disposed && generation === playGeneration &&
          sourceIdentity === state.sourceIdentity && entries.get(id) === entry;
        if (typeof window.readCloudMusicMetadata === 'function') {
          void Promise.resolve().then(() => window.readCloudMusicMetadata(file, current)).then(tags => {
            if (!current() || !tags) return;
            const metadata = {};
            for (const key of ['title', 'artist', 'album']) {
              if (typeof tags[key] === 'string' && tags[key].trim()) metadata[key] = tags[key].trim().slice(0, 1024);
            }
            if (!Object.keys(metadata).length) return;
            state.tracks = state.tracks.map(t => t.id === id ? {...t, ...metadata} : t);
            emit(true);
          }).catch(() => {});
        }
        await prepare(() => audio.play());
        if (disposed || generation !== playGeneration) return;
        state.isLoading = false; state.isPlaying = !audio.paused; emit(true);
      } catch (e) {
        if (disposed || generation !== playGeneration) return;
        if (e?.name === 'TimeoutError') {
          clearAudio(); status(id, 'unloaded');
          state.message = '读取或准备播放超时，请检查网络和文件权限后重试。浏览器无法保证停止系统的 iCloud 下载。';
          emit(true); return;
        }
        state.isLoading = false; state.isPlaying = false;
        if (e?.name === 'NotAllowedError' && url) {
          if (state.tracks.find(t => t.id === id)?.status === 'loading') status(id, 'unloaded');
          state.message = '浏览器阻止了自动播放，请再次点击播放。';
        }
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
            if (typeof cached.sourceIdentity === 'string' && cached.sourceIdentity.length < 200) state.sourceIdentity = cached.sourceIdentity;
            state.tracks = Array.isArray(cached.tracks) ? cached.tracks.filter(t => typeof t.id === 'string' && typeof t.relativePath === 'string').map(t => ({...t, status: 'accessRequired'})) : [];
            selectedFiles = filesOnly || cached.selectedFiles === true;
            state.shuffle = cached.shuffle === true;
            state.repeatMode = ['off', 'all', 'one'].includes(cached.repeatMode) ? cached.repeatMode : 'off';
            state.volume = Number.isFinite(cached.volume) ? Math.max(0, Math.min(1, cached.volume)) : 1;
            audio.volume = state.volume;
          }
        } catch (_) {}
        if (selectedFiles) {
          if (state.folderName) state.message = '请重新选择音乐文件以恢复播放；网页不会保存音频或持续读取 iCloud 文件夹。';
          return snapshot();
        }
        // 调度前记录修订号：即使新文件选择发生在启动任务首次执行前，
        // 也必须优先采用该选择。
        const generation = scanGeneration;
        // 立即返回缓存元数据，在后台恢复并校验句柄。
        setTimeout(async () => {
          try {
            const saved = await savedHandle();
            const handle = saved?.handle || saved;
            if (disposed || generation !== scanGeneration || picking) return;
            if (handle && typeof handle.queryPermission === 'function') {
              root = handle;
              if (typeof saved?.sourceIdentity === 'string' && state.sourceIdentity !== saved.sourceIdentity) {
                state.sourceIdentity = saved.sourceIdentity; state.tracks = [];
              }
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
          case 'pickFiles': return pick(true);
          case 'refresh': return refresh();
          case 'play': return play(args.id);
          case 'togglePlayback':
            if (state.isLoading) { clearAudio(); emit(); return; }
            if (!audio.paused) { audio.pause(); state.isLoading = false; emit(); return; }
            if (url) {
              const generation = playGeneration;
              state.isLoading = true; emit();
              try {
                await prepare(() => audio.play());
                if (disposed || generation !== playGeneration) return;
                state.isLoading = false; state.isPlaying = !audio.paused; emit();
              } catch (error) {
                if (disposed || generation !== playGeneration) return;
                if (error?.name === 'TimeoutError') clearAudio();
                state.isLoading = false;
                state.message = '播放未能开始，请再点击播放或检查文件是否可用。'; emit();
              }
              return;
            }
            return play(state.currentTrackId || state.tracks[0]?.id);
          case 'pause': if (state.isLoading) clearAudio(); else { ++playGeneration; audio.pause(); } state.isLoading = false; emit(); return;
          case 'cancelImport':
            ++scanGeneration; state.isScanning = false; pickerCleanup?.(); cancelPickerOperation?.();
            state.message = '已取消本次导入；系统可能继续管理已开始的文件下载。'; emit(); return;
          case 'cancelLoading': clearAudio(); state.message = '已取消本次播放等待；浏览器无法保证取消系统正在进行的 iCloud 下载。'; emit(); return;
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
        disposed = true; ++scanGeneration; pickerCleanup?.(); cancelPickerOperation?.();
        for (const [name, callback] of listeners) audio.removeEventListener(name, callback);
        clearAudio(); entries.clear(); root = null;
      }
    };
  };
})();
