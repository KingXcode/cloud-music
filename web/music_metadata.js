/* 仅在播放时读取原文件的小段标签；不上传音频，也不读取封面或整首歌曲。 */
(() => {
  'use strict';
  const MAX_READ = 256 * 1024, MAX_TOTAL = 1024 * 1024, MAX_STEPS = 512;
  const ascii = bytes => String.fromCharCode(...bytes);
  const u32 = (b, p = 0, little = false) => new DataView(b.buffer, b.byteOffset, b.byteLength).getUint32(p, little);
  const sync = (b, p = 0) => {
    if (b.slice(p, p + 4).some(v => v > 127)) throw new Error('Invalid synchsafe size');
    return b[p] * 2097152 + b[p + 1] * 16384 + b[p + 2] * 128 + b[p + 3];
  };
  const clean = value => value.replace(/\0/g, ' / ').replace(/[\u0001-\u001f\u007f]/g, '').replace(/(?:\s*\/\s*)+$/, '').trim().slice(0, 1024);
  const decode = (bytes, encoding = 'utf-8') => clean(new TextDecoder(encoding).decode(bytes));
  function textFrame(bytes) {
    const enc = bytes[0]; let data = bytes.subarray(1);
    if (enc === 1) {
      const big = data[0] === 0xfe && data[1] === 0xff;
      if ((data[0] === 0xff && data[1] === 0xfe) || big) data = data.subarray(2);
      return decode(data, big ? 'utf-16be' : 'utf-16le');
    }
    if (enc > 3) return '';
    return decode(data, ['windows-1252', '', 'utf-16be', 'utf-8'][enc]);
  }
  window.readCloudMusicMetadata = async (file, isCurrent = () => true) => {
    const tags = {};
    if (!file || typeof file.slice !== 'function' || !Number.isSafeInteger(file.size)) return tags;
    let total = 0, steps = 0;
    async function read(offset, length) {
      if (!isCurrent() || ++steps > MAX_STEPS || length < 0 || length > MAX_READ ||
          offset < 0 || offset + length > file.size || (total += length) > MAX_TOTAL) throw new Error('Tag read limit');
      const bytes = new Uint8Array(await file.slice(offset, offset + length).arrayBuffer());
      if (!isCurrent() || bytes.length !== length) throw new Error('Incomplete tag');
      return bytes;
    }
    function set(key, value) { if (key && value && !tags[key]) tags[key] = value; }
    function comments(bytes, start = 0) {
      let p = start;
      const size = () => { const n = u32(bytes, p, true); p += 4; return n; };
      const vendorLength = size(); p += vendorLength;
      const count = size();
      if (count > 4096) return;
      for (let i = 0; i < count; i++) {
        const n = size(); if (p + n > bytes.length) return;
        const value = decode(bytes.subarray(p, p + n)); p += n;
        const split = value.indexOf('=');
        const key = {TITLE: 'title', ARTIST: 'artist', ALBUM: 'album'}[value.slice(0, split).toUpperCase()];
        set(key, clean(value.slice(split + 1)));
      }
    }
    try {
      const head = await read(0, Math.min(12, file.size));
      if (ascii(head.subarray(0, 3)) === 'ID3' && [2, 3, 4].includes(head[3])) {
        const version = head[3], end = Math.min(file.size, 10 + sync(head, 6));
        // 压缩标签及整段去同步需要重建大缓冲区，安全降级到文件名。
        if (head[5] & 0x80 || (version === 2 && head[5] & 0x40)) return tags;
        let p = 10;
        if (version >= 3 && head[5] & 0x40) {
          const ext = await read(p, 4); p += version === 4 ? sync(ext) : 4 + u32(ext);
        }
        const headerSize = version === 2 ? 6 : 10;
        while (p + headerSize <= end) {
          const h = await read(p, headerSize), id = ascii(h.subarray(0, version === 2 ? 3 : 4));
          if (!/^[A-Z0-9]+$/.test(id)) break;
          const size = version === 2 ? h[3] * 65536 + h[4] * 256 + h[5] : version === 4 ? sync(h, 4) : u32(h, 4);
          p += headerSize;
          if (!size || p + size > end) break;
          const key = {TIT2: 'title', TT2: 'title', TPE1: 'artist', TP1: 'artist', TALB: 'album', TAL: 'album'}[id];
          const flags = version === 2 ? 0 : h[9];
          if (key && size <= MAX_READ && !(flags & (version === 4 ? 0x4f : 0xe0))) set(key, textFrame(await read(p, size)));
          p += size;
        }
      } else if (ascii(head.subarray(0, 4)) === 'fLaC') {
        let p = 4;
        while (p + 4 <= file.size) {
          const h = await read(p, 4), size = h[1] * 65536 + h[2] * 256 + h[3]; p += 4;
          if (p + size > file.size) break;
          if ((h[0] & 127) === 4 && size <= MAX_READ) comments(await read(p, size));
          p += size; if (h[0] & 128) break;
        }
      } else if (ascii(head.subarray(0, 4)) === 'OggS') {
        let p = 0, chunks = [], length = 0, serial;
        // 只检查起始逻辑流的头部包，支持跨页的 Vorbis/Opus 注释。
        for (let page = 0; page < 32 && p + 27 <= file.size; page++) {
          const h = await read(p, 27);
          if (ascii(h.subarray(0, 4)) !== 'OggS' || h[4] !== 0) break;
          const currentSerial = u32(h, 14, true);
          if (serial === undefined) serial = currentSerial;
          if (currentSerial !== serial) break;
          const laces = await read(p + 27, h[26]); p += 27 + h[26];
          for (const n of laces) {
            length += n; if (length > MAX_READ) return tags;
            chunks.push(await read(p, n)); p += n;
            if (n < 255) {
              const packet = new Uint8Array(length); let at = 0;
              for (const chunk of chunks) { packet.set(chunk, at); at += chunk.length; }
              if (ascii(packet.subarray(0, 8)) === 'OpusTags') { comments(packet, 8); return tags; }
              if (packet[0] === 3 && ascii(packet.subarray(1, 7)) === 'vorbis') { comments(packet, 7); return tags; }
              chunks = []; length = 0;
              if (!(packet[0] === 1 && ascii(packet.subarray(1, 7)) === 'vorbis') && ascii(packet.subarray(0, 8)) !== 'OpusHead') return tags;
            }
          }
        }
      } else if (ascii(head.subarray(4, 8)) === 'ftyp') {
        async function atoms(start, end, depth = 0, key = null) {
          if (depth > 6) return;
          for (let p = start; p + 8 <= end;) {
            const h = await read(p, 8), type = ascii(h.subarray(4, 8));
            let size = u32(h), header = 8;
            if (size === 1) {
              const extended = await read(p + 8, 8); size = u32(extended) * 4294967296 + u32(extended, 4); header = 16;
            } else if (!size) size = end - p;
            if (!Number.isSafeInteger(size) || size < header || p + size > end) return;
            const field = {'©nam': 'title', '©ART': 'artist', '©alb': 'album'}[type];
            if (type === 'data' && key && size - header >= 8 && size - header <= MAX_READ) {
              const data = await read(p + header, size - header), encoding = u32(data) & 0xffffff;
              if (encoding === 1 || encoding === 2) set(key, decode(data.subarray(8), encoding === 2 ? 'utf-16be' : 'utf-8'));
            } else if (field || ['moov', 'udta', 'meta', 'ilst'].includes(type)) {
              await atoms(p + header + (type === 'meta' ? 4 : 0), p + size, depth + 1, field);
            }
            p += size;
          }
        }
        await atoms(0, file.size);
      }
    } catch (_) { /* 损坏、不支持或超出读取预算的标签不影响原始 Blob 播放。 */ }
    return tags;
  };
})();
