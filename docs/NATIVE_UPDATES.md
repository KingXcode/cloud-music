# Android 与 macOS 原生更新桥接

此桥接配合 Dart 更新控制器使用：检查官方版本、下载和显示进度、验证 SHA-256、提示用户，再由用户点击安装/打开。**下载完成本身不会触发安装、修改系统权限、退出应用或重启。**

## 当前交付范围

- Android：验证 APK 属于本应用、版本代码严格递增、当前签名证书集合完全一致，然后打开 Android 系统安装器。首次安装来源授权只在用户点击安装时请求。最终安装由 Android 再做完整校验和用户确认。
- macOS：0.7.6 起改为默认浏览器打开官方对应版本发布页，由浏览器下载 DMG，再由用户安装。应用内更新不再走私有缓存下载/打开 DMG 的路径；沙盒下载可能带禁止执行标记，单独添加下载隔离属性不能解决。后文 `installDownloaded` 的 macOS 描述为旧桥接兼容逻辑，不是当前界面流程。
- 两个平台的 `automaticInstall` 都为 `false`。**当前没有接入 Sparkle，不具备自动替换应用或自动重启能力。**
- 未生成或配置生产签名密钥、EdDSA 密钥、Developer ID 证书、公证凭据，也未安装新版本或更改任何系统安全设置。

## 通道约定

通道名：`dev.cloudmusic/app_updates`。

### `openReleasePage`（macOS，0.7.6 起）

参数 `{url: String}`。Dart 和 Swift 均只接受 `https://github.com/KingXcode/cloud-music/releases/tag/v版本号`（允许预览后缀），禁止其他仓库、用户信息、查询参数和片段。通过 NSWorkspace 打开默认浏览器，不下载文件、不挂载 DMG、不安装应用。

### `getInfo`

无参数，返回：

```json
{
  "version": "0.6.0",
  "build": "7",
  "platform": "android",
  "architecture": "arm64",
  "automaticInstall": false
}
```

这里是示例值，运行时版本与构建号来自已安装应用，不从在线清单取值。`platform` 是 `android` 或 `macos`；架构为 `arm64`、`x64`、`arm`、`x86` 或 `unknown`。Android 使用设备首选 ABI；macOS 使用当前运行二进制的架构，因此 Rosetta 下可返回 `x64`。Android 的安装器仍会验证实际包是否兼容设备。

### `getDownloadDirectory`

无参数，返回专用私有缓存目录的绝对规范路径：

- Android：应用内部 `cacheDir/app_updates`。
- macOS：应用沙盒内的用户缓存目录下 `app_updates`，创建权限为 `0700`。

下载控制器必须将完成的 `.apk` 或 `.dmg` 直接放在该目录，不放在子目录。半成品使用其他扩展名，校验通过后才改为最终名称，例如 `update-<sha256>.apk`。缓存可能被系统清理，安装前须重新确认文件存在并验证摘要。缓存路径不会被发送到更新服务。

### `installDownloaded`

参数：`{"path": "/absolute/private/cache/app_updates/update-<sha256>.apk"}`。

调用前置条件：

1. 用户明确点击当前已下载更新的“安装新版”或“打开安装包”。
2. 下载控制器已完成下载、官方清单校验和 SHA-256 检查，并在此次点击后重新验证文件摘要。
3. 更新仍是当前选中版本，尚未取消或被其他下载替换。

成功返回字符串：

- `opened`：已请求系统打开安装器或 DMG。**不代表已安装成功。**
- `permissionRequired`：仅 Android 8 及以上，在未授予安装来源权限时，已打开本应用的系统授权页面。界面应说明用户返回后需再次点击安装；桥接不会在回到前台时自动续装。

失败使用 `FlutterError` / `PlatformException`。可区分的代码包括 `invalid_arguments`、`invalid_package`、`package_mismatch`、`version_not_newer`、`signature_mismatch`、`cache_unavailable`、`install_in_progress`、`install_unavailable`、`quarantine_failed`、`open_failed` 和通用的 `update_failed`。界面必须保留可理解的错误与重试入口，不能把失败当成已安装。

## Android 安全边界

- 非导出的 `FileProvider` 只映射 `app_updates/`，不暴露整棵缓存目录、外部存储、曲库或用户文件。
- URI 只授予读取权限，不授予写入、持久或目录树权限。
- 拒绝相对路径、`..`、符号链接、目录、空文件、未完成的文件、缓存外或嵌套文件。缓存目录本身也不能被符号链接重定向。
- 在申请安装来源权限前读取安装包身份：包名必须等于当前 `applicationId`；`versionCode`/`longVersionCode` 必须大于已安装值；APK 当前签名证书集合必须非空并与已安装应用的证书集合完全相同。
- 不把证书历史中的任意一个交集当成合法签名。此保守策略不自动支持签名密钥轮换；未来如需轮换，应单独审查 Android 的签名谱系策略。
- APK 元信息解析不代替 Android 安装器的最终密码学验证。安装器仍负责完整签名验证、兼容性验证与用户确认。
- `REQUEST_INSTALL_PACKAGES` 不等于已获得用户授权。Android 8+ 只在明确安装动作中打开本应用的来源设置，不修改设置；Android 7 的全局安装来源规则由系统安装器处理。
- 在工作线程校验 APK，避免阻塞下载完成后的 Flutter 界面。没有 shell、`pm install`、静默安装、卸载旧应用或自动清除数据行为。

### 当前预览版的签名限制

仓库 Android 发布构建仍使用调试/测试密钥。不同 CI 机器可能生成不同的调试密钥，因此并非每两个预览版都能原地升级。桥接会明确拒绝签名不一致的 APK，而不是绕过检查或自动卸载旧版。稳定升级需要发行者以同一妥善管理的签名密钥发布后续版本，并持续递增构建号。不能通过降低版本比较或放宽签名检查来掩盖这一限制。

## macOS 安全边界与自动更新计划

- 只接受私有更新缓存目录中直接存放的普通、非空 `.dmg` 文件，同样拒绝路径逃逸和符号链接。
- Dart HTTP 下载不保证自动获得浏览器下载隔离属性。桥接在打开之前使用 `NSURL` 的 `quarantinePropertiesKey` 读取/写入 Launch Services 隔离信息，保留已有信息，并重新读取确认写入成功。添加失败时不打开安装包。
- 只用 `NSWorkspace.open` 打开 DMG。不运行 shell、`hdiutil`、复制替换应用、重启、`xattr -d`，不移除隔离、不关闭 Gatekeeper、不绕过系统警告。
- 保持现有 App Sandbox 与网络客户端权限，不添加安全例外或扩大文件访问范围。未签名/临时签名且未公证的预览包仍可能被 macOS 阻止，UI 不应承诺其一定可以安装。
- 官方 HTTPS 清单中的 SHA-256 证明下载与清单一致；它**不是独立的发行者签名**。这不能替代生产自动更新的签名验证。

若要实现用户点击后自动替换并重启的体验，下一阶段应接入正式的 Sparkle 2，而不是自制复制脚本。启用前应具备：

1. 明确维护的官方 HTTPS appcast 地址与允许的发布源，发布包中嵌入有效 `SUPublicEDKey`。缺少或错误配置时必须禁用自动安装。
2. 在受保护的发行流程中管理 EdDSA 私钥，为每个更新包生成 `sparkle:edSignature`、大小、递增构建号和平台要求。私钥不能进入仓库或客户端。此实现没有生成或申请这些凭据。
3. 采用 Sparkle 2 当前受支持版本及其标准更新流程，固定审核后的依赖版本。保留 App Sandbox，并按官方沙盒指南集成与签名 `Installer.xpc`，按需要处理 `Downloader.xpc`。不能为了更新关闭沙盒。
4. 为正式 macOS 发行建立 Developer ID 签名、公证及内嵌组件签名流程，确认签名身份、bundle ID 和用户数据容器连续性。现有 ad-hoc/未签名预览版不是该流程已经就绪的证据。
5. 在真实 Mac 上验证签名失败/缺失、篡改 appcast、篡改下载包、降级、不同 CPU 架构、只读或受限安装目录、取消、失败回滚、保留曲库与播放状态，以及安装后安全重启。下载完成后依旧应提示用户，不因引入 Sparkle 擅自开启静默安装。

## 验证

新增 Android JVM 回归测试覆盖缓存约束、相对/嵌套/穿越/链接路径、空文件/半成品、包名、递增版本与签名集合。准备好 Flutter 和 Android SDK 后运行：

```sh
flutter pub get
flutter build apk --debug
(cd android && ./gradlew :app:testDebugUnitTest)
```

新增 macOS XCTest 覆盖 DMG 文件约束，以及隔离属性的添加和保留；测试不挂载 DMG、不安装应用：

```sh
flutter pub get
flutter build macos --debug
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS' test
```

这些单元测试不替代真实设备验收。仍需检查：Android 同签名升级、不同签名拒绝、未知来源权限返回/取消、不支持安装的车机；macOS 沙盒 DMG 打开、隔离属性、Gatekeeper 提示、用户取消与手动替换。`opened` 仅表示系统接受了打开请求，不应据此显示“已更新”。

本次实现环境使用 Maven 官方发布的 Kotlin 编译器与 JUnit 独立编译并运行了纯 JVM 策略测试，**9 项通过**；XML/plist 解析、Xcode 源文件关联、FileProvider 配置和保留沙盒权限的静态检查也已通过。此环境没有 Android SDK 或 macOS/Xcode，因此完整原生桥接编译、Gradle/XCTest 和设备行为测试尚未执行；这些局部检查不能当作原生构建通过。

## 官方参考

- [Android FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider)
- [Android 安装来源权限](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls())
- [Apple quarantinePropertiesKey](https://developer.apple.com/documentation/foundation/urlresourcekey/quarantinepropertieskey)
- [Apple NSURL setResourceValue](https://developer.apple.com/documentation/foundation/nsurl/setresourcevalue(_:forkey:))
- [Sparkle 安装与签名文档](https://sparkle-project.org/documentation/)
- [Sparkle 2 沙盒集成](https://sparkle-project.org/documentation/sandboxing/)
