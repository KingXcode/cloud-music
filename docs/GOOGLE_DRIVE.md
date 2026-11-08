# Google Drive 音乐来源（0.5.0）

云听现在有独立的「音乐来源」入口，系统文件和 Google Drive 可以切换。Google Drive 路径采用 Google 官方 OAuth 和 Drive v3 API。**代码接入不等于已完成真实账号联调：仓库没有自有 OAuth Client ID，未配置的网页和安装包会明确显示「尚未配置」，不能直接登录。** 仍可正常使用系统文件音乐库。

## 本次支持范围

- 由用户主动连接，申请 `https://www.googleapis.com/auth/drive.readonly`，不申请写入、删除权限。
- 在「我的云端硬盘」浏览文件夹和音频候选，选择音乐文件夹后递归索引；文件名沿用现有歌名/歌手识别。支持列表分页，不跟随快捷方式，也未单独提供「与我共享」和共享云端硬盘入口。
- 索引使用稳定文件编号和账户身份，播放时获取短期凭据。不同账户重新连接会清空前一账户的会话曲库。
- 曲库与令牌仅保留在当前云听会话内，网页刷新或应用重启后重新连接并选择目录。原生 Google SDK 可能保留操作系统登录会话；云听不自行保存 access token、refresh token 或临时播放地址。
- 选择新来源后停止另一个播放器；切回系统文件仍保留原系统曲库。断开清除网盘会话并尝试撤销 Google 授权，撤销失败会明确提示到 Google 账户设置移除授权。
- 列目录/刷新失败保留已有曲库。取消、关闭面板、快速切歌、迟到的授权回调与来源切换均有失效检查。
- 支持播放/暂停、上一首/下一首、随机/循环、音量、进度跳转和现有歌词。Google 文件标签和封面暂不额外下载解析，标题优先按文件名识别。

递归扫描上限为 10000 首候选歌曲、500 个文件夹、20 层目录；超过限制或目录返回不完整时不提交部分曲库，请选较小的音乐文件夹。禁止下载的音频标记为不可播放。扩展名/MIME 类型只用于发现候选，能否解码取决于设备。

## 权限和隐私

`drive.file` 更窄，但不能读取任意既有文件夹中的所有歌曲。因此本版为文件夹浏览使用 `drive.readonly`。**这项授权允许读取账户内全部 Drive 文件，不限于用户随后在云听选择的文件夹。** 界面在连接前明确说明范围。应用实现仅列目录和读取音频，不上传、不改写、不删除源文件。

`drive.readonly` 是 Google restricted scope。面向公众发布前，开发者必须按 Google 要求配置应用并完成适用的 OAuth 验证；若服务器处理受限数据，可能需要额外安全评估。本版没有音频代理后端。未验证应用的测试用户、授权有效期和使用限制取决于 Google 项目状态。

访问令牌仅通过官方 HTTPS 请求的 Authorization 头传递，不出现在 URL、曲库、偏好设置或应用错误提示里。网页媒体只允许固定 Google API 路径，并拒绝重定向。错误信息不回显服务器内容或 SDK 原始异常。授权过期后由用户点击「重新连接」，不会在后台弹出 Google 授权窗口。

自动歌词仍默认关闭；若用户此前已开启，则按照原有设置把歌名、歌手及可选专辑发往 LRCLIB，不上传 Google 音频或文件编号。详见 [歌词说明](LYRICS.md)。

## 网页配置和播放

1. 在自己的 Google Cloud 项目启用 **Google Drive API**。
2. 配置 OAuth 同意屏幕、应用基本信息和测试用户，添加上述只读权限。按 Google 要求完成公开发布审核。
3. 创建 **Web application** OAuth 客户端。Authorized JavaScript origins 填网页的实际 origin，而不是包含路径的 URL。例如此仓库 Pages 的 origin 是 `https://kingxcode.github.io`，本地开发则是实际使用的 `http://localhost:端口`。
4. 使用公开客户端标识构建，不使用任何客户端密钥：

```sh
flutter build web --release --base-href /cloud-music/ \
  --dart-define=GOOGLE_DRIVE_WEB_CLIENT_ID="$YOUR_WEB_CLIENT_ID"
```

CI 可读取 GitHub repository variable `GOOGLE_DRIVE_WEB_CLIENT_ID`。值为空时发布的网页保留系统音乐和未配置提示，不会借用其他应用的客户端标识。

Google Identity Services 脚本只在用户点连接后加载。第一次加载完成后提示再次点击连接；第二次点击同步打开 Google 授权弹窗，避免浏览器阻止异步弹窗。取消或关闭面板不会接纳迟到授权。页面不自动请求持续访问，也不保存刷新令牌。

**网页不是远程分段串流：** HTML Audio 不能直接附加 Authorization，因此先通过有界 fetch 把当前整首歌曲读取到内存，再用临时 Blob URL 播放。单曲上限 **100 MiB**，即使服务端未提供 Content-Length 也累计检查字节数。会产生完整下载流量；低内存设备建议较小文件。换歌、取消、错误和断开时释放对象 URL/缓冲，不保存到 IndexedDB 或应用下载缓存。浏览器可能要求再次点播放以允许声音；已缓冲音频可以恢复播放而不重新下载。

需真实配置后验证 Google API 的 CORS、浏览器权限、网络可达性及目标格式。不能因为模拟测试通过就宣称真实 Google 账号已能播放。

## 原生端

Android、iOS、macOS 通过官方 `google_sign_in` 获取授权，再由 `just_audio` 使用 HTTPS Authorization 请求头播放，支持系统播放器的缓冲和 Range/seek。Android 需注册包名和实际签名 SHA；CI 预览使用测试签名，签名变化后必须相应更新 Google OAuth 配置。

Android CI 可读取 repository variable `GOOGLE_DRIVE_SERVER_CLIENT_ID`（同项目 Web application 客户端的公开 ID）。Apple 还需要对应 bundle ID、回调 Scheme 和签名/钥匙串设置，不能只填一个 Dart define。

**Apple 限制：** 当前 `just_audio` 的无代理请求头方式使用未公开的 Apple 请求头键，兼容性与 App Store 审核尚未验证。本次不提供已验证的 Apple 网盘安装包，也未更改 macOS 图标或网络安全设置。

配置、平台限制和官方依据详见 [原生配置说明](GOOGLE_DRIVE_NATIVE.md)。网盘播放器未接入现有 Android 本地播放器的前台媒体服务；本版仅承诺前台交互路径的实现，后台播放、锁屏控制、音频焦点中断和车机行为必须真机补测，不能视为已支持完整后台体验。

## 验证清单

自动化覆盖：官方请求/分页/ID 校验、目录递归、撤销/过期/拒绝授权、未知长度字节上限、401/403、刷新失败保留索引、快速切换/取消、完成事件去重、随机循环、来源切换竞态、弹窗首次加载与再次点击、缓冲恢复、不持久化令牌、窄屏/横屏/宽屏未配置和连接面板。

本地已通过 Flutter 静态分析、166 项单元/组件测试、58 项 JavaScript 测试、Web 发布构建和 6 个视觉夹具（12 张截图）。本地 Chrome 回归受容器 IPC socket 限制未启动，需以该提交的 GitHub Actions Chrome 结果为准；未将未执行的检查计为通过。

真实账号与原生设备仍未验证：OAuth 测试用户登录、实际 API CORS/配额、Range 跳转、不同格式、弱网、长曲令牌过期、授权撤销、Apple SDK/系统兼容性、后台/锁屏/音频焦点。

## 官方资料

- [Drive API 权限范围](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [OAuth 客户端配置](https://developers.google.com/workspace/guides/create-credentials)
- [网页令牌模式](https://developers.google.com/identity/oauth2/web/guides/use-token-model)
- [Google Identity Services JS API](https://developers.google.com/identity/oauth2/web/reference/js-reference)
- [列文件与分页](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list)
- [下载和 Range](https://developers.google.com/workspace/drive/api/guides/manage-downloads)
