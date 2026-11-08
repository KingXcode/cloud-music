// 防止原生登录依赖在网页启动时偷偷预加载 GIS；网页授权只由显式桥接发起。
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = process.argv[2] || 'build/web';
const main = fs.readFileSync(path.join(root, 'main.dart.js'), 'utf8');
const bridge = fs.readFileSync(path.join(root, 'google_drive.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
assert(!main.includes('accounts.google.com/gsi/client'), 'Flutter 自动注册器不应包含 GIS 脚本加载器');
assert(main.includes('createGoogleDrivePlatform'), '缺少应用网页桥接绑定');
assert(bridge.includes('https://accounts.google.com/gsi/client'), '缺少用户主动触发的官方 GIS 桥接');
assert(index.includes('google_drive.js'), '发布页面未加载网盘桥接');
console.log('Google Drive Web 发布校验通过：独立桥接存在，无自动 GIS 预加载。');
