const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('web/google_drive.js', 'utf8');
function harness(options = {}) {
  const events = [], calls = [], revoked = [], audios = [], timers = new Map();
  let config, now = 1000, timerId = 0;
  class Audio {
    constructor() { this.listeners = {}; this.paused = true; this.currentTime = 0; this.duration = 30; audios.push(this); }
    addEventListener(name, fn) { this.listeners[name] = fn; }
    fire(name) { this.listeners[name]?.(); }
    async play() { if (options.blockPlay) { const error = Error('blocked'); error.name = 'NotAllowedError'; throw error; } this.paused = false; this.fire('play'); }
    pause() { this.paused = true; this.fire('pause'); }
    removeAttribute() {} load() {}
  }
  const context = {
    Audio, Blob, AbortController, Date: { now: () => now },
    setTimeout: fn => { timers.set(++timerId, fn); return timerId; }, clearTimeout: id => timers.delete(id),
    URL: { createObjectURL: () => 'blob:local', revokeObjectURL: u => revoked.push(u) },
    document: { createElement: () => ({}), head: { appendChild: script => calls.push(['script', script]) } },
    fetch: async (url, init) => { calls.push(['fetch', url, init]); return options.fetch ? options.fetch(url, init) : response(); },
    google: { accounts: { oauth2: {
      initTokenClient(c) { config = c; return { requestAccessToken: o => calls.push(['request', o]) }; },
      hasGrantedAllScopes: () => !options.deniedScope,
      revoke: (token, cb) => { calls.push(['revoke', token]); if (options.revokeTimeout) return; cb(options.revokeFailure ? { successful: false, error: 'SECRET' } : { successful: true }); },
    } } },
  };
  const savedGoogle = context.google;
  if (options.noGis) delete context.google;
  vm.runInNewContext(source, context);
  const api = context.createGoogleDrivePlatform(options.missing ? '' : 'client', e => events.push(e));
  return { installGis: () => { context.google = savedGoogle; }, api, events, calls, revoked, audios, timers, config: () => config, time: t => now = t,
    async connect() { const p = api.authorize(true); await Promise.resolve(); config.callback({ access_token: 'SECRET', expires_in: 3600 }); return p; },
  };
}
function response(chunks = [new Uint8Array([1, 2])], length = null) {
  return { ok: true, headers: { get: () => length }, body: { getReader: () => ({
    async read() { return chunks.length ? { value: chunks.shift(), done: false } : { done: true }; },
    async cancel() {}, releaseLock() {},
  }) } };
}
const track = id => ({ id: `gdrive:${id}`, fileId: id, accessToken: 'SECRET', size: 2, mimeType: 'audio/mpeg', url: 'https://evil.example/SECRET' });
test('missing configuration and initialize never load GIS', async () => {
  const h = harness({ missing: true, noGis: true }); await h.api.initialize();
  await assert.rejects(h.api.authorize(true), /GOOGLE_DRIVE_WEB_CLIENT_ID/); assert.deepEqual(h.calls, []);
});
test('noninteractive auth never opens prompt; GIS is lazy and singleton', async () => {
  const h = harness({ noGis: true }); assert.equal(await h.api.authorize(false), null);
  const p = h.api.authorize(true); const rejection = assert.rejects(p, /取消/);
  assert.equal(h.calls.length, 1); assert.equal(h.calls[0][1].src, 'https://accounts.google.com/gsi/client');
  await h.api.disconnect(); await rejection;
});
test('OAuth exact readonly scope, expiry and disconnect revocation', async () => {
  const h = harness(); const auth = await h.connect();
  assert.equal(h.config().scope, 'https://www.googleapis.com/auth/drive.readonly');
  assert.equal(h.config().include_granted_scopes, false);
  assert.equal((await h.api.authorize(false)).accessToken, 'SECRET');
  h.time(auth.expiresAt); assert.equal(await h.api.authorize(false), null);
  await h.connect(); await h.api.disconnect();
  assert.ok(h.calls.some(c => c[0] === 'revoke' && c[1] === 'SECRET'));
  assert.equal(await h.api.authorize(false), null);
});
test('popup closed, OAuth denial, missing scope and timeout reject safely', async () => {
  for (const mode of ['popup', 'denial', 'scope', 'timeout']) {
    const h = harness({ deniedScope: mode === 'scope' }); const p = h.api.authorize(true);
    const rejected = assert.rejects(p); await Promise.resolve();
    if (mode === 'popup') h.config().error_callback({ type: 'popup_closed' });
    if (mode === 'denial') h.config().callback({ error: 'access_denied' });
    if (mode === 'scope') h.config().callback({ access_token: 'SECRET', expires_in: 3600 });
    if (mode === 'timeout') [...h.timers.values()][0]();
    await rejected; assert.equal(await h.api.authorize(false), null);
  }
});
test('authenticated fixed URL, bounded Blob, audio events and cleanup', async () => {
  const h = harness(); await h.connect(); await h.api.play(track('abc'));
  const [, url, init] = h.calls.find(c => c[0] === 'fetch');
  assert.equal(url, 'https://www.googleapis.com/drive/v3/files/abc?alt=media&supportsAllDrives=true');
  assert.ok(!url.includes('SECRET')); assert.equal(init.headers.Authorization, 'Bearer SECRET');
  assert.equal(init.redirect, 'error'); assert.equal(init.credentials, 'omit');
  h.audios[0].currentTime = 4; h.audios[0].fire('timeupdate');
  assert.equal(h.events.at(-1).position, 4); h.audios[0].fire('ended'); assert.equal(h.events.at(-1).completed, true);
  await h.api.stop(); assert.equal(h.revoked.length, 1);
  h.audios[0].fire('ended'); assert.equal(h.events.at(-1).completed, false);
});
test('oversize known metadata/header and unknown-length stream enforce cap', async () => {
  for (const kind of ['metadata', 'header', 'stream']) {
    const h = harness({ fetch: async () => kind === 'header' ? response([], String(101 * 1024 * 1024)) : response([{ byteLength: 101 * 1024 * 1024 }]) });
    await h.connect(); const request = track('large'); if (kind === 'metadata') request.size = 101 * 1024 * 1024;
    await h.api.play(request); assert.match(h.events.at(-1).error, /100 MiB/); assert.equal(h.audios.length, 0);
  }
});
test('rapid switch cancels old fetch, ignores late completion and releases URLs', async () => {
  let finish;
  const h = harness({ fetch: (url) => url.includes('/first?') ? new Promise(r => finish = r) : Promise.resolve(response()) });
  await h.connect(); const first = h.api.play(track('first')); await h.api.play(track('second'));
  assert.equal(h.calls.find(c => c[0] === 'fetch')[2].signal.aborted, true);
  finish(response()); await first; assert.equal(h.audios.length, 1); assert.equal(h.events.at(-1).id, 'gdrive:second');
  await h.api.dispose(); assert.equal(h.revoked.length, 1);
});
test('network failure, expired auth, autoplay retry and decode errors', async () => {
  const failed = harness({ fetch: async () => { throw TypeError('secret transport error'); } });
  await failed.connect(); await failed.api.play(track('a')); assert.match(failed.events.at(-1).error, /加载失败/);
  const expired = harness(); const auth = await expired.connect(); expired.time(auth.expiresAt);
  await expired.api.play(track('a')); assert.match(expired.events.at(-1).error, /过期/);
  const options = { blockPlay: true }; const h = harness(options); await h.connect(); await h.api.play(track('a'));
  assert.match(h.events.at(-1).error, /自动播放/); options.blockPlay = false; await h.api.resume(); assert.equal(h.events.at(-1).playing, true);
  h.audios[0].fire('error'); assert.equal(h.revoked.length, 1); assert.match(h.events.at(-1).error, /解码/);
});
test('disconnect cancels pending OAuth and ignores late grant', async () => {
  const h = harness(); const p = h.api.authorize(true); const rejected = assert.rejects(p, /取消/);
  await Promise.resolve(); const callback = h.config().callback;
  await h.api.disconnect(); callback({ access_token: 'SECRET', expires_in: 3600 });
  await rejected; assert.equal(await h.api.authorize(false), null);
});
test('HTTP 401 clears session and disconnect during fetch prevents playback', async () => {
  const unauthorized = harness({ fetch: async () => ({ ok: false, status: 401 }) });
  await unauthorized.connect(); await unauthorized.api.play(track('a'));
  assert.equal(await unauthorized.api.authorize(false), null);
  let finish; const h = harness({ fetch: () => new Promise(resolve => finish = resolve) });
  await h.connect(); const pending = h.api.play(track('a')); await h.api.disconnect();
  finish(response()); await pending; assert.equal(h.audios.length, 0); assert.equal(h.events.at(-1).id, null);
});

test('first click only loads GIS; next click opens popup synchronously', async () => {
  const h = harness({ noGis: true });
  const first = h.api.authorize(true); const rejected = assert.rejects(first, /再次点击连接/);
  const script = h.calls.find(c => c[0] === 'script')[1];
  h.installGis(); script.onload(); await rejected;
  assert.equal(h.calls.filter(c => c[0] === 'request').length, 0);
  const second = h.api.authorize(true);
  assert.equal(h.calls.filter(c => c[0] === 'request').length, 1);
  h.config().callback({ access_token: 'SECRET', expires_in: 3600 });
  await second;
  assert.equal(h.calls.filter(c => c[0] === 'script').length, 1);
});

test('prefixed track ID stays in events while bare file ID is used for media', async () => {
  const h = harness(); await h.connect(); await h.api.play(track('file_123'));
  assert.equal(h.events.at(-1).id, 'gdrive:file_123');
  assert.equal(h.calls.find(c => c[0] === 'fetch')[1], 'https://www.googleapis.com/drive/v3/files/file_123?alt=media&supportsAllDrives=true');
  await h.api.play({ ...track('x'), fileId: 'bad/id' });
  assert.match(h.events.at(-1).error, /文件编号无效/);
});
test('authorization bridge returns safe first-click retry and denial errors', async () => {
  const h = harness({ noGis: true });
  const result = h.api.authorizeResult(true);
  h.installGis(); h.calls.find(c => c[0] === 'script')[1].onload();
  assert.match((await result).error, /再次点击连接/);
  const denied = h.api.authorizeResult(true);
  h.config().callback({ error: 'SECRET must never be exposed' });
  assert.equal((await denied).error, 'Google 授权未完成或被拒绝。');
});

test('cancelAuthorization ignores late grant but preserves an existing session and audio', async () => {
  const pending = harness();
  const result = pending.api.authorizeResult(true); const callback = pending.config().callback;
  pending.api.cancelAuthorization(); callback({ access_token: 'SECRET', expires_in: 3600 });
  assert.match((await result).error, /取消/);
  assert.equal(await pending.api.authorize(false), null);
  const connected = harness(); await connected.connect(); await connected.api.play(track('a'));
  connected.api.cancelAuthorization();
  assert.equal((await connected.api.authorize(false)).accessToken, 'SECRET');
  assert.equal(connected.events.at(-1).playing, true);
  assert.equal(connected.revoked.length, 0);
  assert.equal(connected.calls.filter(c => c[0] === 'revoke').length, 0);
});
test('revoke failure and timeout reject after local token and audio are cleared', async () => {
  for (const options of [{ revokeFailure: true }, { revokeTimeout: true }]) {
    const h = harness(options); await h.connect(); await h.api.play(track('a'));
    const result = h.api.disconnect(); const rejected = assert.rejects(result, /未能确认 Google 授权已撤销/);
    if (options.revokeTimeout) [...h.timers.values()][0]();
    await rejected;
    assert.equal(await h.api.authorize(false), null);
    assert.equal(h.events.at(-1).playing, false);
    assert.equal(h.revoked.length, 1);
  }
});

test('explicit reconnect always opens fresh consent even with cached token', async () => {
  const h = harness(); await h.connect();
  assert.equal(h.calls.filter(c => c[0] === 'request').length, 1);
  const fresh = h.api.authorize(true);
  assert.equal(h.calls.filter(c => c[0] === 'request').length, 2);
  assert.equal(h.calls.filter(c => c[0] === 'request')[1][1].prompt, 'consent');
  h.config().callback({ access_token: 'NEW_TOKEN', expires_in: 3600 });
  assert.equal((await fresh).accessToken, 'NEW_TOKEN');
});
test('autoplay recovery resumes buffered audio without fetching again', async () => {
  const options = { blockPlay: true }; const h = harness(options);
  await h.connect(); await h.api.play(track('a'));
  assert.equal(h.events.at(-1).resumable, true);
  const fetchCount = h.calls.filter(c => c[0] === 'fetch').length;
  options.blockPlay = false; await h.api.resume();
  assert.equal(h.events.at(-1).resumable, false);
  assert.equal(h.events.at(-1).playing, true);
  assert.equal(h.calls.filter(c => c[0] === 'fetch').length, fetchCount);
  await h.api.stop(); assert.equal(h.events.at(-1).resumable, false);
});

test('cancel explicit reconnect preserves prior usable token', async () => {
  const h = harness(); await h.connect();
  const p = h.api.authorize(true); const rejected = assert.rejects(p, /取消/);
  h.api.cancelAuthorization(); await rejected;
  assert.equal((await h.api.authorize(false)).accessToken, 'SECRET');
});
