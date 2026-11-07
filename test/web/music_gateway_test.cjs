// Run: node --test test/web/music_gateway_test.cjs
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('web/music_gateway.js', 'utf8');
const tick = () => new Promise(r => setTimeout(r, 20));
function harness({handle = null, cached = null, picker} = {}) {
  const events = [], urls = new Set(), revoked = [];
  let picked = 0, audio, input;
  const document = {body: {append() {}}, createElement() {
    input = {listeners: {}, files: [], setAttribute() {}, style: {}, remove() {}, click() {},
      addEventListener(name, callback) {this.listeners[name] = callback;}}; return input;
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
  indexedDB: {open() { const r = {}; setTimeout(() => {r.result = db; r.onsuccess();}, 0); return r;}}, window: {}};
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
  assert.equal(h.picked,1); // No timer/microtask/await occurs before picker invocation.
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
