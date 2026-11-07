// 运行：node --test test/web/music_gateway_test.cjs
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('web/music_gateway.js', 'utf8');
const tick = () => new Promise(r => setTimeout(r, 20));
function harness({handle = null, cached = null, picker, browser = {}, directoryInput = true, clickError, blockedDatabase = false} = {}) {
  const events = [], urls = new Set(), revoked = [];
  let picked = 0, audio, input;
  const document = {body: {append() {}}, createElement() {
    const element = {listeners: {}, files: [], attributes: {}, style: {}, removed: false,
      setAttribute(name, value) {this.attributes[name] = value;},
      remove() {this.removed = true;},
      click() {input = this; if (clickError) throw clickError;},
      addEventListener(name, callback) {this.listeners[name] = callback;}};
    if (directoryInput) element.webkitdirectory = false;
    return element;
  }};
  class FakeAudio {
    constructor() { audio = this; this.listeners = {}; this.paused = true; this.currentTime = 0; this.duration = 42; }
    addEventListener(k, f) { this.listeners[k] = f; }
    removeEventListener(k) { delete this.listeners[k]; }
    load() {}
    pause() { this.paused = true; this.listeners.pause?.(); }
    play() { this.paused = false; this.listeners.playing?.(); return Promise.resolve(); }
    removeAttribute() { this.src = ''; }
  }
  const db = {close() {}, transaction() {
    const tx = {objectStore: () => ({get: () => req(handle), put: v => {handle = v; return req(v);}, delete: () => {handle = null; return req(null);}})};
    function req(value) {const r = {}; setTimeout(() => { r.result = value; r.onsuccess?.(); tx.oncomplete?.(); }, 0); return r;}
    return tx;
  }};
  const context = {document, console, setTimeout, clearTimeout, Audio: FakeAudio, URL: {
    createObjectURL() { const u = 'blob:' + Math.random(); urls.add(u); return u; },
    revokeObjectURL(u) {urls.delete(u); revoked.push(u);}
  }, localStorage: {getItem: () => cached && JSON.stringify(cached), setItem: (_, v) => {cached = JSON.parse(v);}},
  indexedDB: {open() { const r = {}; if (!blockedDatabase) setTimeout(() => {r.result = db; r.onsuccess();}, 0); return r;}}, window: {navigator: browser}};
  if (picker) context.window.showDirectoryPicker = async () => {picked++; return picker();};
  vm.runInNewContext(source, context);
  const gateway = context.window.createCloudMusicGateway(s => events.push(s));
  return {gateway, events, urls, revoked, get input() {return input;}, get audio() {return audio;}, get picked() {return picked;}, get cached() {return cached;}};
}
function directory(files, permission = 'granted') {
  return {kind: 'directory', name: 'Music', queries: 0, requests: 0,
    async getFileHandle(name) { if (files[name]?.kind === 'file') return files[name]; throw {name: 'NotFoundError'}; },
    async getDirectoryHandle(name) { if (files[name]?.kind === 'directory') return files[name]; throw {name: 'NotFoundError'}; },
    async queryPermission() {this.queries++; return permission;},
    async requestPermission() {this.requests++; return permission;},
    async *entries() { for (const [path, file] of Object.entries(files)) yield [path, file]; }};
}
const file = name => ({kind: 'file', async getFile() {return {name};}});
test('restores granted handle without picker/requestPermission and does not read audio during scan', async () => {
  let reads = 0;
  const root = directory({'One.mp3': {kind:'file', async getFile() {reads++; return {};}}});
  const h = harness({handle: root});
  await h.gateway.initialize(); await tick();
  assert.equal(root.queries, 1); assert.equal(root.requests, 0);
  assert.equal(reads, 0); assert.equal(h.events.at(-1).tracks.length, 1);
  assert.equal(h.events.at(-1).tracks[0].status, 'unknown');
  await h.gateway.command('play', {id:'One.mp3'});
  assert.equal(reads, 1); assert.equal(h.urls.size, 1);
  h.gateway.dispose(); assert.equal(h.urls.size, 0);
});
test('startup never prompts; denied permission retains metadata', async () => {
  const root = directory({}, 'prompt');
  const h = harness({handle: root, cached:{folderName:'Music', tracks:[{id:'x.mp3', title:'x', relativePath:'x.mp3'}]}});
  const first = await h.gateway.initialize(); assert.equal(first.tracks.length, 1);
  await tick(); assert.equal(root.requests, 0); assert.match(h.events.at(-1).message, /刷新/);
  await h.gateway.command('refresh'); assert.equal(root.requests, 1);
  assert.equal(h.events.at(-1).tracks.length, 1); h.gateway.dispose();
});
test('startup marks missing; explicit complete refresh removes missing references', async () => {
  const root = directory({'new.mp3':file('new.mp3')});
  const h = harness({handle:root, cached:{tracks:[{id:'old.mp3',relativePath:'old.mp3'}]}});
  await h.gateway.initialize(); await tick();
  assert.equal(h.events.at(-1).tracks.find(t=>t.id==='old.mp3').status,'missing');
  await h.gateway.command('refresh'); assert.equal(h.events.at(-1).tracks.length,1);
  h.gateway.dispose();
});
test('failed subtree preserves prior tracks on refresh', async () => {
  const root = directory({'sub':{kind:'directory', async *entries(){throw new Error('unmounted');}}});
  const h = harness({handle:root,cached:{tracks:[{id:'sub/old.mp3',relativePath:'sub/old.mp3'}]}});
  await h.gateway.initialize(); await tick(); await h.gateway.command('refresh');
  assert.equal(h.events.at(-1).tracks.length,1); assert.match(h.events.at(-1).message,/保留/);
  h.gateway.dispose();
});
test('cancelled picker preserves library', async () => {
  const h = harness({cached:{tracks:[{id:'old.mp3',relativePath:'old.mp3'}]},picker:()=>{throw {name:'AbortError'};}});
  await h.gateway.initialize(); await h.gateway.command('pickFolder');
  assert.equal(h.picked,1); assert.equal(h.cached.tracks.length,1); h.gateway.dispose();
});
test('cancelLoading invalidates pending reads and never creates a stale Blob URL', async () => {
  let resolve;
  const root = directory({'slow.mp3':{kind:'file', getFile:()=>new Promise(r=>resolve=r)}});
  const h = harness({handle:root}); await h.gateway.initialize(); await tick();
  const pending = h.gateway.command('play',{id:'slow.mp3'});
  await h.gateway.command('cancelLoading'); resolve({}); await pending;
  assert.equal(h.urls.size,0); assert.equal(h.events.at(-1).isLoading,false); h.gateway.dispose();
});
test('next revokes old URL; seek, shuffle, repeat and volume update snapshots', async () => {
  const h = harness({handle:directory({'a.mp3':file('a.mp3'),'b.mp3':file('b.mp3')})});
  await h.gateway.initialize(); await tick(); await h.gateway.command('play',{id:'a.mp3'});
  await h.gateway.command('next'); assert.equal(h.events.at(-1).currentTrackId,'b.mp3');
  assert.equal(h.urls.size,1); assert.equal(h.revoked.length,1);
  await h.gateway.command('seek',{positionMs:10000}); assert.equal(h.audio.currentTime,10);
  await h.gateway.command('setVolume',{volume:0.3}); assert.equal(h.audio.volume,0.3);
  await h.gateway.command('setShuffle',{enabled:true}); await h.gateway.command('setRepeat',{mode:'one'});
  assert.equal(h.events.at(-1).shuffle,true); assert.equal(h.events.at(-1).repeatMode,'one');
  h.gateway.dispose();
});
test('empty successful listing is not proof of deletion or a healthy mounted source', async () => {
  const h = harness({handle:directory({}),cached:{tracks:[{id:'old.mp3',relativePath:'old.mp3'}]}});
  await h.gateway.initialize(); await tick(); await h.gateway.command('refresh');
  assert.equal(h.events.at(-1).tracks.length,1);
  assert.equal(h.events.at(-1).tracks[0].status,'unknown'); h.gateway.dispose();
});
test('omitted entry still resolvable by direct lookup is preserved', async () => {
  const root = directory({'witness.mp3':file('witness.mp3')});
  root.getFileHandle = async name => file(name);
  const h = harness({handle:root,cached:{tracks:[{id:'old.mp3',relativePath:'old.mp3'}]}});
  await h.gateway.initialize(); await tick(); await h.gateway.command('refresh');
  assert.equal(h.events.at(-1).tracks.find(t=>t.id==='old.mp3').status,'unknown'); h.gateway.dispose();
});
test('apparently present siblings with unavailable provider cannot confirm deletion', async () => {
  const root = directory({'witness.mp3':file('witness.mp3')});
  root.getFileHandle = async () => {throw {name:'NotFoundError'};};
  const h = harness({handle:root,cached:{tracks:[{id:'old.mp3',relativePath:'old.mp3'}]}});
  await h.gateway.initialize(); await tick(); await h.gateway.command('refresh');
  assert.equal(h.events.at(-1).tracks.find(t=>t.id==='old.mp3').status,'unknown'); h.gateway.dispose();
});
test('playback NotFound alone never labels track missing', async () => {
  const h = harness({handle:directory({'cloud.mp3':{kind:'file',async getFile(){throw {name:'NotFoundError'};}}})});
  await h.gateway.initialize(); await tick(); await h.gateway.command('play',{id:'cloud.mp3'});
  assert.equal(h.events.at(-1).tracks[0].status,'unknown'); h.gateway.dispose();
});
test('refresh invokes requestPermission synchronously before any awaited boundary', async () => {
  const root = directory({}); const h = harness({handle:root});
  await h.gateway.initialize(); await tick();
  const pending = h.gateway.command('refresh');
  assert.equal(root.requests,1); await pending; h.gateway.dispose();
});
test('fallback cancel leaves metadata untouched and allows another picker', async () => {
  const h = harness({cached:{folderName:'Music',tracks:[{id:'old.mp3',relativePath:'old.mp3'}]}});
  await h.gateway.initialize();
  const pending = h.gateway.command('pickFolder'); const first = h.input;
  first.listeners.cancel(); await pending;
  assert.equal(h.cached.tracks.length,1);
  const second = h.gateway.command('pickFolder'); assert.notEqual(h.input,first);
  h.input.listeners.change(); await second;
  assert.equal(h.cached.tracks.length,1); h.gateway.dispose();
});
test('shuffle repeat-off visits each track once and then stops', async () => {
  const h = harness({handle:directory({'a.mp3':file('a.mp3'),'b.mp3':file('b.mp3'),'c.mp3':file('c.mp3')})});
  await h.gateway.initialize(); await tick();
  await h.gateway.command('setShuffle',{enabled:true}); await h.gateway.command('play',{id:'a.mp3'});
  const ids = ['a.mp3'];
  for (let i=0;i<2;i++) {h.audio.paused=true; h.audio.listeners.ended(); await tick(); ids.push(h.events.at(-1).currentTrackId);}
  assert.equal(new Set(ids).size,3);
  const revokes = h.revoked.length;
  h.audio.paused=true; h.audio.listeners.ended(); await tick();
  assert.equal(h.events.at(-1).isPlaying,false); assert.equal(h.revoked.length,revokes);
  h.gateway.dispose();
});
test('shuffle repeat-all starts a new cycle; previous uses history; repeat-one repeats only current', async () => {
  const h = harness({handle:directory({'a.mp3':file('a.mp3'),'b.mp3':file('b.mp3')})});
  await h.gateway.initialize(); await tick();
  await h.gateway.command('setShuffle',{enabled:true}); await h.gateway.command('setRepeat',{mode:'all'});
  await h.gateway.command('play',{id:'a.mp3'}); await h.gateway.command('next');
  assert.equal(h.events.at(-1).currentTrackId,'b.mp3');
  h.audio.paused=true; h.audio.listeners.ended(); await tick();
  assert.equal(h.events.at(-1).currentTrackId,'a.mp3');
  await h.gateway.command('previous'); assert.equal(h.events.at(-1).currentTrackId,'b.mp3');
  await h.gateway.command('setRepeat',{mode:'one'});
  h.audio.paused=true; h.audio.listeners.ended(); await tick();
  assert.equal(h.events.at(-1).currentTrackId,'b.mp3'); assert.equal(h.events.at(-1).isPlaying,true);
  h.gateway.dispose();
});
test('late cancelled preparation cannot replace or autoplay over a new track', async () => {
  let resolve;
  const h = harness({handle:directory({'slow.mp3':{kind:'file',getFile:()=>new Promise(r=>resolve=r)},'new.mp3':file('new.mp3')})});
  await h.gateway.initialize(); await tick();
  const pending = h.gateway.command('play',{id:'slow.mp3'});
  await h.gateway.command('cancelLoading'); await h.gateway.command('play',{id:'new.mp3'});
  const src = h.audio.src; const revokes = h.revoked.length;
  resolve({}); await pending;
  assert.equal(h.audio.src,src); assert.equal(h.revoked.length,revokes);
  assert.equal(h.urls.size,1); assert.equal(h.events.at(-1).currentTrackId,'new.mp3');
  h.gateway.dispose();
});
test('pickFolder invokes native picker synchronously before returning its promise', async () => {
  let resolve;
  const h = harness({picker:()=>new Promise(r=>resolve=r)});
  await h.gateway.initialize();
  const pending = h.gateway.command('pickFolder');
  assert.equal(h.picked,1); // 调用选择器前不执行定时器、微任务或 await。
  resolve(directory({})); await pending; h.gateway.dispose();
});
test('picker security restriction is distinct from permission denial and does not silently fall back', async () => {
  const h = harness({picker:()=>{throw {name:'SecurityError'};}});
  await h.gateway.initialize(); await h.gateway.command('pickFolder');
  assert.match(h.events.at(-1).message,/安全限制/);
  assert.match(h.events.at(-1).message,/HTTPS/);
  assert.equal(h.input,undefined); h.gateway.dispose();
  const denied = harness({picker:()=>{throw {name:'NotAllowedError'};}});
  await denied.gateway.initialize(); await denied.gateway.command('pickFolder');
  assert.match(denied.events.at(-1).message,/未允许/);
  assert.doesNotMatch(denied.events.at(-1).message,/安全限制/); denied.gateway.dispose();
});

const iphone = {userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X)', platform: 'iPhone', maxTouchPoints: 5};
const selectedFile = (name, path = '') => ({name, webkitRelativePath: path, type: 'audio/mpeg'});

test('iPhone uses multi-file selection and the command completes even when no picker event arrives', async () => {
  const h = harness({browser: iphone});
  assert.equal((await h.gateway.initialize()).selectionMode, 'files');
  const result = await Promise.race([h.gateway.command('pickFolder').then(() => 'ready'), tick().then(() => 'locked')]);
  assert.equal(result, 'ready');
  assert.equal(h.input.multiple, true);
  assert.equal(h.input.attributes.webkitdirectory, undefined);
  assert.match(h.input.accept, /audio\/\*/);
  const previous = h.input;
  await h.gateway.command('pickFolder');
  assert.notEqual(h.input, previous);
  assert.equal(previous.removed, true);
  previous.files = [selectedFile('stale.mp3')]; previous.listeners.change();
  assert.equal(h.events.length, 0);
  h.input.files = [selectedFile('current.mp3')]; h.input.listeners.change();
  assert.equal(h.events.at(-1).tracks[0].id, 'current.mp3');
  await h.gateway.command('play', {id: 'current.mp3'});
  assert.equal(h.events.at(-1).isPlaying, true);
  h.gateway.dispose();
});
test('iPad desktop identity and browsers without directory input support use files', async () => {
  for (const options of [
    {browser: {userAgent: 'Mozilla/5.0 (Macintosh)', platform: 'MacIntel', maxTouchPoints: 5}},
    {directoryInput: false},
    {browser: iphone, picker: () => {throw new Error('must not use a directory picker');}}
  ]) {
    const h = harness(options);
    assert.equal((await h.gateway.initialize()).selectionMode, 'files');
    await h.gateway.command('pickFolder');
    assert.equal(h.input.attributes.webkitdirectory, undefined);
    assert.equal(h.picked, 0); h.gateway.dispose();
  }
});
test('desktop directory fallback completes without events and preserves nested paths', async () => {
  const h = harness();
  assert.equal((await h.gateway.initialize()).selectionMode, 'folder');
  await h.gateway.command('pickFolder');
  assert.equal(h.input.attributes.webkitdirectory, '');
  h.input.files = [selectedFile('track.mp3', 'Music/Album/track.mp3')];
  h.input.listeners.change();
  assert.equal(h.events.at(-1).folderName, 'Music');
  assert.equal(h.events.at(-1).tracks[0].id, 'Album/track.mp3');
  await tick();
  assert.equal(h.events.at(-1).tracks[0].id, 'Album/track.mp3');
  assert.doesNotMatch(h.events.at(-1).message, /没有可恢复/);
  h.gateway.dispose();
});
test('cancel, empty selection and unsupported files preserve current playback and allow retry', async () => {
  const h = harness({browser: iphone});
  await h.gateway.initialize(); await h.gateway.command('pickFolder');
  h.input.files = [selectedFile('kept.mp3')]; h.input.listeners.change();
  await h.gateway.command('play', {id: 'kept.mp3'});
  const src = h.audio.src;
  for (const outcome of ['cancel', 'empty', 'unsupported']) {
    await h.gateway.command('pickFolder');
    h.input.files = outcome === 'unsupported' ? [{name: 'notes.txt', type: 'text/plain'}] : [];
    h.input.listeners[outcome === 'cancel' ? 'cancel' : 'change']();
    assert.equal(h.audio.src, src);
    assert.equal(h.events.at(-1).tracks[0].id, 'kept.mp3');
    assert.equal(h.events.at(-1).isPlaying, true);
  }
  assert.match(h.events.at(-1).message, /没有找到.*音频/);
  h.gateway.dispose();
});
test('selected files publish immediately even when IndexedDB never responds; duplicate names stay playable', async () => {
  const h = harness({browser: iphone, blockedDatabase: true});
  await h.gateway.initialize(); await h.gateway.command('pickFolder');
  h.input.files = [selectedFile('same.mp3'), selectedFile('same.mp3'), {name: 'notes.txt', type: 'text/plain'}];
  h.input.listeners.change();
  const snapshot = h.events.at(-1);
  assert.equal(snapshot.folderName, '已选音乐文件');
  assert.equal(snapshot.tracks.length, 2);
  assert.equal(new Set(snapshot.tracks.map(t => t.id)).size, 2);
  assert.equal(h.cached.tracks.length, 2);
  await h.gateway.command('play', {id: snapshot.tracks[1].id});
  assert.equal(h.events.at(-1).isPlaying, true); h.gateway.dispose();
});
test('iPhone reload explains file reselection and refresh opens another file picker', async () => {
  const h = harness({browser: iphone, cached: {folderName: '已选音乐文件', tracks: [{id: 'old.mp3', relativePath: 'old.mp3'}]}});
  const initial = await h.gateway.initialize();
  assert.equal(initial.tracks[0].status, 'unknown');
  assert.match(initial.message, /重新选择音乐文件/);
  await h.gateway.command('play', {id: 'old.mp3'});
  assert.match(h.events.at(-1).message, /重新选择音乐文件/);
  await h.gateway.command('refresh');
  assert.equal(h.input.multiple, true);
  assert.equal(h.input.attributes.webkitdirectory, undefined); h.gateway.dispose();
});
test('fallback click error is visible and disposal ignores a late selection', async () => {
  const h = harness({browser: iphone, clickError: {name: 'SecurityError'}});
  await h.gateway.initialize(); await h.gateway.command('pickFolder');
  assert.match(h.events.at(-1).message, /安全限制/);
  assert.equal(h.input.removed, true); h.gateway.dispose();
  const late = harness({browser: iphone});
  await late.gateway.initialize(); await late.gateway.command('pickFolder');
  late.gateway.dispose();
  late.input.files = [selectedFile('late.mp3')]; late.input.listeners.change();
  assert.equal(late.events.length, 0); assert.equal(late.urls.size, 0);
});
test('different same-named folders receive separate persistent source identities', async () => {
  const first = directory({'a.mp3':file('a.mp3')});
  const second = directory({'a.mp3':file('a.mp3')});
  const h = harness({handle: first, cached: {sourceIdentity:'original-root'}, picker: () => second});
  await h.gateway.initialize(); await tick();
  assert.equal(h.events.at(-1).sourceIdentity, 'original-root');
  await h.gateway.command('pickFolder');
  const identity = h.events.at(-1).sourceIdentity;
  assert.notEqual(identity, 'original-root');
  assert.equal(h.cached.sourceIdentity, identity);
  await h.gateway.command('pickFolder');
  assert.equal(h.events.at(-1).sourceIdentity, identity); // 必须是同一个句柄。
  h.gateway.dispose();
});
test('saved handle identity wins over mismatched metadata cache', async () => {
  const h = harness({handle: {handle: directory({'a.mp3':file('a.mp3')}), sourceIdentity:'actual-root'},
    cached: {sourceIdentity:'stale-root'}});
  await h.gateway.initialize(); await tick();
  assert.equal(h.events.at(-1).sourceIdentity, 'actual-root');
  h.gateway.dispose();
});
