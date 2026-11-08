# Google Drive 原生接入配置与验证边界

实现使用官方 Flutter `google_sign_in` 7.2.0（Android、iOS、macOS）及 `just_audio` 0.10.6。Windows/Linux 原生登录不支持，请使用浏览器版本。**未提供客户端 ID 的安装包不会启用登录**，现有本地音乐入口不依赖 Google 配置。

## 开发者配置

在自己的 Google Cloud 项目启用 Google Drive API，配置 OAuth 同意屏幕及测试用户。不要把 OAuth 客户端密钥、访问令牌或账户密码放进代码。客户端 ID 是公开标识符，可以通过构建参数提供。

本功能需要 `https://www.googleapis.com/auth/drive.readonly`：浏览用户已有文件夹并读取其中的音乐。更小的 `drive.file` 范围不能任意浏览用户已有曲库；本实现不申请修改或删除权限。`drive.readonly` 属于 Google **restricted scope**，公开发布可能需要 OAuth 验证；依据数据使用方式还可能需要安全评估。开发测试应限制为同意屏幕中指定的测试用户，不要把未验证应用当成正式发布版本。

### Android

1. 在同一项目注册 Android OAuth 客户端，包名应与 `android/app/build.gradle.kts` 中的 applicationId 一致，登记实际安装包的签名 SHA。调试、正式发布、Play App Signing 各种签名需分别核对。
2. 注册同项目的 Web application OAuth 客户端，其客户端 ID 作为 `serverClientId`。这里不需要 Web 客户端密钥，也不需要创建自己的服务器。
3. 构建时传入真实值：

```sh
flutter build apk --release --dart-define=GOOGLE_DRIVE_SERVER_CLIENT_ID="$YOUR_WEB_CLIENT_ID"
```

应用直接在 Dart 初始化 SDK，不依赖 `google-services.json`。Android 已有 INTERNET 权限；本改动不开放 HTTP 明文流量。如果选完账户后被取消，也可能是包名、签名 SHA 或 serverClientId 配置不匹配（SDK 无法总是区分配置错误与用户取消）。

### iOS 和 macOS

1. 按官方插件说明配置对应 bundle identifier 的 Apple OAuth 客户端。分别把真实客户端 ID 通过 `GOOGLE_DRIVE_IOS_CLIENT_ID` 或 `GOOGLE_DRIVE_MACOS_CLIENT_ID` 传给 Flutter：

```sh
flutter build ios --dart-define=GOOGLE_DRIVE_IOS_CLIENT_ID="$YOUR_IOS_CLIENT_ID"
flutter build macos --dart-define=GOOGLE_DRIVE_MACOS_CLIENT_ID="$YOUR_MACOS_CLIENT_ID"
```

2. 在对应的 `ios/Runner/Info.plist` 或 `macos/Runner/Info.plist` 添加 `CFBundleURLTypes` → `CFBundleURLSchemes`，值必须是此客户端的 **REVERSED_CLIENT_ID**。从 Google 的客户端配置中取得，不要使用示例值。Dart 提供 clientId 不能代替这个回调 URL Scheme。
3. macOS 必须在 DebugProfile 和 Release entitlements 启用 SDK 要求的 keychain access group `$(AppIdentifierPrefix)com.google.GIDSignIn`，并正确配置 Apple 开发团队、应用签名和 provisioning。工程原有 network.client entitlement 需保留。此配置依赖实际签名账户，本仓库不虚构团队或客户端，也不会自动修改用户钥匙串或安装凭据。
4. 当前解析的官方 Apple 插件最低要求 iOS 15、macOS 12。本工程现有 deployment target 已分别为 iOS 15、macOS 12，满足这些最低要求。
5. App Store 发布前检查 Apple 登录服务审核要求。

`configured` 仅表示当前平台具备格式合理的构建时客户端 ID，不代表 Google Console、回调 Scheme、签名或钥匙串已通过验证。未配置这些原生项目项，登录可能失败。

## 播放和凭据

- 原生使用 HTTPS Drive `files/{id}?alt=media` 串流，令牌只通过 Authorization 请求头发送，不附加到 URL、不写入曲库、偏好设置或应用日志。播放器与 SDK 在会话内持有令牌；Google SDK 可使用操作系统保存登录会话，应用本身不持久化 access token。
- `just_audio` 使用平台原生请求头（`useProxyForRequestHeaders: false`），不启用本地 HTTP 代理，不增加全局 ATS、明文 HTTP、网络安全豁免。系统解码器负责缓冲、Range 请求及 seek，具体格式和 seek 能力仍取决于设备、文件及服务端响应，不会主动下载整个文件到本地。
- **Apple 限制：** just_audio 的此选项使用未公开的 Apple `AVURLAssetHTTPHeaderFieldsKey` API 传递 Authorization。它不是 Apple 官方支持的自定义请求头 API。因此不能承诺所有 Apple 系统版本兼容或 App Store 审核通过。正式发行前必须真机验证，必要时另行设计受审核支持的传输方案；本实现没有通过放宽 ATS 来绕过此限制。
- 每次换歌释放旧播放器，用请求序号隔离旧异步事件；停止、断开和销毁会取消旧播放。错误提示不包含 SDK 原始异常、令牌或播放地址。
- 交互登录和请求额外授权只由明确的连接动作触发；静默恢复失败不会弹出授权。“断开并撤销授权”会停止播放，并调用官方 SDK 的 disconnect 撤销应用授权；撤销失败会显示不含敏感信息的错误，可重试或前往 Google 账户的第三方应用访问设置核对。关闭或取消连接面板仅丢弃未完成的授权结果，不主动撤销已有授权，也不会发起新的授权请求。
- 长时间播放中令牌过期或网络错误不会自动弹出登录；明确点击重新连接时，会先对最近一次仅在内存中保留的令牌调用官方 `clearAuthorizationToken`，再重新获取授权，避免 Android 重复使用已失效的缓存令牌。Apple 插件的清缓存方法为空操作，失效处理交由 Google Apple SDK，因此仍需真机验证外部撤销后的恢复流程。没有离线播放或下载缓存。

## 必须补做的真实验证

当前仅完成源码、依赖及自动化检查，没有创建 OAuth 凭据，没有访问任何真实 Google 账户，没有执行 OAuth 授权，也没有执行 iOS/macOS/Android 真机登录播放。发布前验证：拒绝/取消授权、撤销授权、令牌过期、切歌时加载未完成、停止和断开、重新连接、Range seek、暂停恢复、前后台切换及目标音频格式。macOS 的签名和 keychain、Apple 请求头播放必须单独验收。

## 官方依据

- https://pub.dev/packages/google_sign_in
- https://pub.dev/packages/google_sign_in_android
- https://pub.dev/packages/google_sign_in_ios
- https://pub.dev/packages/just_audio
- https://developers.google.com/workspace/drive/api/guides/api-specific-auth
