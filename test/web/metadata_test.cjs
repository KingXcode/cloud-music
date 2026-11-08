// 运行：node --test test/web/*.cjs
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const context = {window: {}, TextDecoder};
vm.runInNewContext(fs.readFileSync('web/music_metadata.js', 'utf8'), context);
const read = context.window.readCloudMusicMetadata;
const be = n => {const b = Buffer.alloc(4); b.writeUInt32BE(n); return b;};
const le = n => {const b = Buffer.alloc(4); b.writeUInt32LE(n); return b;};
const sync = n => Buffer.from([n >> 21 & 127, n >> 14 & 127, n >> 7 & 127, n & 127]);
const frame = (id, text, version = 3) => {
  const value = Buffer.concat([Buffer.from([3]), Buffer.from(text)]);
  return Buffer.concat([Buffer.from(id), version === 4 ? sync(value.length) : be(value.length), Buffer.alloc(2), value]);
};
const id3 = (version = 3) => {
  const frames = Buffer.concat([frame('TIT2', '晴天', version), frame('TPE1', '周杰伦', version), frame('TALB', '叶惠美', version)]);
  return Buffer.concat([Buffer.from([73,68,51,version,0,0]), sync(frames.length), frames]);
};
const comments = () => {
  const values = ['TITLE=晴天', 'ARTIST=周杰伦', 'ALBUM=叶惠美'].map(v => {const b = Buffer.from(v); return Buffer.concat([le(b.length), b]);});
  return Buffer.concat([le(0), le(values.length), ...values]);
};
const expected = {title: '晴天', artist: '周杰伦', album: '叶惠美'};
for (const version of [3, 4]) test(`reads ID3v2.${version} Unicode text`, async () => {
  assert.deepEqual({...await read(new Blob([id3(version)]))}, expected);
});
test('reads FLAC Vorbis comments without artwork', async () => {
  const data = comments();
  const bytes = Buffer.concat([Buffer.from('fLaC'), Buffer.from([132, 0, data.length >> 8, data.length & 255]), data]);
  assert.deepEqual({...await read(new Blob([bytes]))}, expected);
});
test('reads Opus and Vorbis comment packets', async () => {
  for (const prefix of [Buffer.from('OpusTags'), Buffer.concat([Buffer.from([3]), Buffer.from('vorbis')])]) {
    const packet = Buffer.concat([prefix, comments()]);
    const header = Buffer.alloc(27); header.write('OggS'); header[26] = 1;
    assert.deepEqual({...await read(new Blob([header, Buffer.from([packet.length]), packet]))}, expected);
  }
});
test('reads M4A atoms and skips audio payload', async () => {
  const atom = (type, body) => Buffer.concat([be(8 + body.length), Buffer.from(type, 'latin1'), body]);
  const field = (type, value) => atom(type, atom('data', Buffer.concat([be(1), be(0), Buffer.from(value)])));
  const tags = Buffer.concat([field('©nam', '晴天'), field('©ART', '周杰伦'), field('©alb', '叶惠美')]);
  const file = new Blob([atom('ftyp', Buffer.from('M4A ')), atom('mdat', Buffer.alloc(2 * 1024 * 1024)), atom('moov', atom('udta', atom('meta', Buffer.concat([be(0), atom('ilst', tags)]))))]);
  let total = 0;
  const wrapped = {size: file.size, slice(a,b) {total += b-a; assert.ok(b-a <= 256*1024); return file.slice(a,b);}};
  assert.deepEqual({...await read(wrapped)}, expected); assert.ok(total < 1024);
});
test('missing, corrupt, oversized and interrupted tags return safely', async () => {
  for (const data of [Buffer.alloc(0), Buffer.from('abc'), Buffer.from('fLaC\x84\xff\xff\xff'), Buffer.from('ID3\x04\x00\x00\xff\xff\xff\xff')]) {
    assert.deepEqual({...await read(new Blob([data]))}, {});
  }
  assert.deepEqual({...await read(new Blob([id3()]), () => false)}, {});
  const value = new Blob([id3()]); let calls = 0;
  assert.deepEqual({...await read({size:value.size, slice(a,b) {calls++; return value.slice(a,b);}}, () => calls < 1)}, {});
});
test('large artwork is skipped rather than buffered', async () => {
  const imageLength = 3 * 1024 * 1024;
  const art = Buffer.concat([Buffer.from('APIC'), be(imageLength), Buffer.alloc(2)]);
  const title = frame('TIT2', '晴天');
  const file = new Blob([Buffer.from([73,68,51,3,0,0]), sync(art.length + imageLength + title.length), art, Buffer.alloc(imageLength), title]);
  let total = 0;
  const tags = await read({size:file.size, slice(a,b) {total += b-a; assert.ok(b-a <= 256*1024); return file.slice(a,b);}});
  assert.equal(tags.title, '晴天'); assert.ok(total < 200);
});

test('reads ID3v2.2 and UTF-16 titles', async () => {
  const body = Buffer.concat([Buffer.from([1, 0xff, 0xfe]), Buffer.from('晴天\0', 'utf16le')]);
  const frame = Buffer.concat([Buffer.from('TT2'), Buffer.from([0, 0, body.length]), body]);
  const file = new Blob([Buffer.from([73,68,51,2,0,0]), sync(frame.length), frame]);
  assert.equal((await read(file)).title, '晴天');
});
test('untrusted atom chains have a bounded read count', async () => {
  const file = new Blob([be(12), Buffer.from('ftypM4A '), ...Array.from({length:1000}, () => Buffer.concat([be(8), Buffer.from('free')]))]);
  let count = 0;
  assert.deepEqual({...await read({size:file.size, slice(a,b) {count++; return file.slice(a,b);}})}, {});
  assert.ok(count <= 512);
});
test('Vorbis comments may span multiple Ogg pages', async () => {
  const vendor = Buffer.alloc(300, 65);
  const values = comments().subarray(4);
  const packet = Buffer.concat([Buffer.from([3]), Buffer.from('vorbis'), le(vendor.length), vendor, values]);
  const header = (continuation, size) => {
    const h = Buffer.alloc(27); h.write('OggS'); h[5] = continuation; h[26] = 1;
    return Buffer.concat([h, Buffer.from([size])]);
  };
  const file = new Blob([header(0,255), packet.subarray(0,255), header(1,packet.length-255), packet.subarray(255)]);
  assert.deepEqual({...await read(file)}, expected);
});
