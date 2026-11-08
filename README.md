# 云听 · Cloud Music

基于 Flutter 的音乐播放器，直接播放原始音频文件，支持 iPhone、iPad、macOS、Android（包括可安装普通 APK 的车机）和浏览器。

[打开网页版](https://kingxcode.github.io/cloud-music/) · [源码仓库](https://github.com/KingXcode/cloud-music) · [构建状态](https://github.com/KingXcode/cloud-music/actions)

## 功能介绍

- 在 Apple 设备上选择 iCloud Drive 文件夹，或通过 Android 系统选择器选择本地、USB 目录。
- 保存访问权限和元数据索引，通过原始 URL/URI 播放，不将歌曲复制到应用沙盒。
- 恢复文件夹书签和 Android 存储访问框架（SAF）的持久权限。浏览器在支持且获准时记住目录句柄，其他浏览器会在需要时提示重新选择。
- 浅色音乐资料库支持歌曲、专辑、歌手分类、搜索、可用状态标记和手动刷新；手机底部导航在宽屏切换为侧栏。
- 可按歌曲搜索、下载歌词：需明确同意访问 LRCLIB，支持版本选择、LRC 同步高亮与跳转、离线缓存及本地 LRC/TXT 导入。详见[歌词使用、隐私与版权限制](docs/LYRICS.md)。
- 浮动迷你播放器与沉浸式完整播放器，支持柔和背景、封面占位图、元数据、进度跳转、待播清单、上一首/下一首、播放/暂停、随机播放、循环播放和音量调节。
- 大字号同步歌词，当前句居中高亮；手动滚动后可返回跟随，点击歌词行即可跳转。搜索、导入与粘贴收纳到歌词选项面板，宽屏可同时显示封面、控制与歌词。
- 适配窄屏、横屏和宽屏布局，提供更大的触控区域。本应用**不是 Android Auto 应用**。请勿在驾驶时操作。
- 启动时校验已知歌曲；刷新时发现新歌曲，只移除已确认缺失的索引条目。iCloud 离线、文件提供器报错、权限撤销或 USB 断开都不会清空音乐库，应用始终不会删除源文件。

## 使用限制与说明

应用不会上传音频。浏览器通过临时 Blob URL 播放音频。Apple iCloud/文件提供器可能将原始文件下载到系统管理的设备存储中，因此播放仍会占用设备空间。应用保存元数据、访问凭据，以及用户选择下载或导入的歌词。在线歌词搜索只向 LRCLIB 发送用户明确确认的歌曲字段，播放时不会自动搜索。

支持的音频格式取决于 AVFoundation、Android 编解码器和浏览器。文件扩展名仅用于发现候选音频，不能保证一定可以解码。原生端只按需加载所选歌曲的封面和元数据；网页版目前使用文件名和默认封面。

本仓库目前处于早期可用阶段。自动化测试不能替代真实设备上的 iCloud、USB、车机和后台音频测试。验收项目见各平台实现说明及 `docs/REQUIREMENTS.md`。

## 本地运行

使用 Flutter **3.47.5**（Dart 3.13.4），然后执行：

```sh
flutter pub get
flutter analyze
flutter test
node --test test/web/music_gateway_test.cjs
flutter run -d chrome
```

在本地浏览器使用文件夹选择器时，请通过 localhost 或 HTTPS 提供服务。桌面版 Chrome/Edge 对 File System Access 持久访问的支持最完整。其他兼容的桌面浏览器提供文件夹输入回退方案；iPhone/iPad 使用音频文件多选，并明确提示何时需要重新选择。详见 `docs/WEB_PLAYBACK.md`。

```sh
flutter run -d macos       # 需要 macOS 和 Xcode
flutter run -d ios         # 选择已配置签名的 iPhone/iPad 或模拟器设备 ID
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
flutter build macos --release
bash scripts/package_macos.sh
```

Android 最低要求为 API 24。Apple 插件支持 iOS 15 / macOS 12 及以上版本。Apple 真机测试需要适当的签名配置和 iCloud 账号。仓库包含 iOS 源码，但不提供已签名的 iOS 安装包。

Android 发布配置目前使用标准调试/测试签名密钥，因此安装包明确标记为测试签名。正式公开发行前，须换用妥善管理的生产密钥。新的 CI 构建可能使用不同密钥，届时可能需要重新安装预览版。

## GitHub 交付流程

- 网页部署工作流（`Deploy Web to GitHub Pages`）：推送到 main 分支或手动触发时，执行校验、构建并部署网页版。Pages 基础路径随仓库名称设置。仓库须支持 Pages，并允许工作流所需权限。
- 原生打包工作流（`Build APK and macOS DMG`）：手动触发时指定新的预览版标签，并将平台设为 `all`。选择 `android` 时仅构建、验证 APK 产物，不发布版本。Linux 构建通用 APK，托管 macOS 编译应用并生成 DMG。流程会验证 APK 签名和包内容、检查应用可执行文件及签名、验证 DMG、生成 SHA-256 校验值，只有两个原生构建任务都成功后才发布预发布版本。
- macOS DMG 未签名，应用未使用 Developer ID 签名，也未经过 Apple 公证；可能带有本地临时签名（ad-hoc）。发布信息会列出实际包含的 CPU 架构。

本仓库不保存证书、生产签名密钥或用户音乐。

## 代码结构

- `lib/ui/`：自适应 Flutter 音乐库和播放器界面。
- `lib/music_controller.dart`、`lib/models.dart`：带类型约束的界面状态与命令处理。
- `lib/gateway/`：原生通道适配器和浏览器桥接。
- `packages/folder_audio/darwin/`：Apple 平台共享的 Swift 书签、文件协调、iCloud 和 AVPlayer 实现。
- `packages/folder_audio/android/`：SAF 扫描器、原始 URI 播放器和媒体前台服务。
- `web/music_gateway.js`：浏览器句柄持久化和本地音频播放。
- `docs/BRIDGE_CONTRACT.md`：平台接口约定。

## 歌词更新前的验证状态

云端工作区已通过：Flutter 静态分析、17 项单元/组件测试（包括窄屏、横屏、宽屏和大字体布局）、25 项浏览器逻辑测试、JavaScript 语法检查及 Web 发布构建。Android/macOS 原生构建和安装包检查由 GitHub 发布工作流执行，须查看实际结果；仅源码检查通过不能证明编译成功。真机访问与播放测试仍需单独进行。

已部署网页版的冒烟测试验证了页面布局、完整播放器跳转、文件提供器错误提示，以及循环/随机播放偏好的恢复。自动化浏览器无法打开系统文件夹选择器，因此其中的真实目录选择、音频播放和句柄恢复尚未验证。

歌词验证情况和原生设备检查另见[歌词文档](docs/LYRICS.md)。

## 0.3.0 界面改版

新版参考 Apple Music 的视觉层次与操作习惯，但保留云听的原文件播放定位。改版说明与验证范围见[界面改版记录](docs/UI_REDESIGN.md)。文件夹权限、播放网关、歌词联网确认和缓存规则均保持原有机制。

