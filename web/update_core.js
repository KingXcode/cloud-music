// Shared validation. URLs are constructed locally, never accepted from a manifest.
(function (root) {
  'use strict';
  const MAX_BYTES = 512 * 1024 * 1024;
  const BUILD_DIRECTORY = 'cloud-music-builds/';
  function compareVersions(left, right) {
    const parts = value => {
      if (typeof value !== 'string' || !/^\d+\.\d+\.\d+$/.test(value)) throw new Error('更新版本号无效。');
      const result = value.split('.').map(Number);
      if (result.some(number => !Number.isSafeInteger(number))) throw new Error('更新版本号无效。');
      return result;
    };
    const a = parts(left), b = parts(right);
    for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i] ? 1 : -1;
    return 0;
  }
  function buildNumber(value) {
    if (typeof value !== 'string' || !/^\d+$/.test(value) || !Number.isSafeInteger(Number(value))) throw new Error('更新构建号无效。');
    return Number(value);
  }
  function isOlder(candidate, installed) {
    const difference = compareVersions(candidate.version, installed.version);
    return difference < 0 || buildNumber(candidate.build) < buildNumber(installed.build);
  }
  function validateManifest(value) {
    if (!value || value.schema !== 1 || !/^[a-f0-9]{64}$/.test(value.id) ||
        typeof value.version !== 'string' || !value.version || value.version.length > 100 ||
        typeof value.build !== 'string' || !value.build || value.build.length > 100 ||
        !Array.isArray(value.resources) || !value.resources.length || value.resources.length > 10000) {
      throw new Error('更新清单格式无效，请稍后重试。');
    }
    compareVersions(value.version, value.version);
    buildNumber(value.build);
    let total = 0;
    const paths = new Set();
    const resources = value.resources.map(entry => {
      if (!entry || typeof entry.path !== 'string' || entry.path.length > 1024 ||
          /[\\%?#\u0000-\u001f]/.test(entry.path) ||
          entry.path.split('/').some(part => !part || part === '.' || part === '..') ||
          paths.has(entry.path) || !Number.isSafeInteger(entry.size) || entry.size < 0 ||
          !/^[a-f0-9]{64}$/.test(entry.sha256)) {
        throw new Error('更新资源清单无效。');
      }
      paths.add(entry.path);
      total += entry.size;
      if (total > MAX_BYTES) throw new Error('更新资源过大。');
      return { path: entry.path, size: entry.size, sha256: entry.sha256 };
    });
    if (!paths.has('index.html') || !paths.has('flutter_bootstrap.js') ||
        !Number.isSafeInteger(value.totalBytes) || value.totalBytes !== total || total === 0) {
      throw new Error('更新清单大小或启动文件无效。');
    }
    return { schema: 1, id: value.id, version: value.version, build: value.build,
      notes: typeof value.notes === 'string' ? value.notes.slice(0, 10000) : '', totalBytes: total, resources };
  }
  function baseURL(value, origin) {
    const url = new URL(value, origin);
    if (url.origin !== origin || !url.pathname.endsWith('/') || url.search || url.hash ||
        !['https:', 'http:'].includes(url.protocol)) throw new Error('更新地址必须位于本应用。');
    return url;
  }
  function resourceURL(base, id, path) {
    return new URL(BUILD_DIRECTORY + id + '/' + path.split('/').map(encodeURIComponent).join('/'), base).href;
  }
  async function sha256(bytes) {
    return Array.from(new Uint8Array(await root.crypto.subtle.digest('SHA-256', bytes)),
      byte => byte.toString(16).padStart(2, '0')).join('');
  }
  root.CloudMusicUpdateCore = { MAX_BYTES, BUILD_DIRECTORY, validateManifest, baseURL, resourceURL, sha256, compareVersions, isOlder };
})(globalThis);
