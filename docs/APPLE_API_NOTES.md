# Apple API 选型与限制

已于 2026-11-07 对照 Apple 官方资料核对。

## 文件夹访问

在 iOS/iPadOS 上使用 `UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)`。原生 macOS 可使用仅允许选择目录的 `NSOpenPanel`。文件夹授权覆盖其所有子项。

- https://developer.apple.com/documentation/uikit/providing-access-to-directories
- https://developer.apple.com/videos/play/wwdc2019/719/

在 iOS 上使用 `.minimalBookmark` 创建书签，使用普通选项解析。macOS 使用 `[.withSecurityScope, .securityScopeAllowOnlyReadAccess]` 创建，并使用 `.withSecurityScope` 解析。macOS 标志不得编译进 iOS 分支。创建或使用书签前，应先开启安全作用域访问；成功开启与停止的调用次数必须对应，播放期间须保持访问有效。过期书签应更新，失败时必须提供重新选择入口，不能假定权限永久有效。

- https://developer.apple.com/documentation/Foundation/NSURL/BookmarkCreationOptions/withSecurityScope
- https://developer.apple.com/forums/thread/797469

原生 macOS 所需授权包括应用沙盒、用户所选文件的只读访问和应用作用域书签。避免申请读写权限或整个“音乐”文件夹的访问权限。此设计不需要应用自有的 iCloud 容器，但仍须验证最小签名配置下的设备目标，因为旧版归档文档中的选择器配置指引与现代用户自选文件夹访问机制存在差异。

- https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html

## 扫描与下载

使用后台文件协调访问（`NSFileCoordinator`），包括元数据读取和目录遍历。远程文件提供器可能阻塞。纯元数据读取应避免触发所有歌曲的实体文件下载。发起下载请求不等于下载完成，必须检查 iCloud 文件状态和播放就绪状态。

- https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system
- https://developer.apple.com/documentation/foundation/nsfilecoordinator
- https://developer.apple.com/documentation/foundation/filemanager/startdownloadingubiquitousitem(at:)
- https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/DocumentPickerProgrammingGuide/CreatinganOutstandingUserExperience/CreatinganOutstandingUserExperience.html

通过文件协调准备可用文件，保持安全作用域，并处理后续播放器错误。仅在协调器闭包中创建 AVPlayerItem，不能证明 AVPlayer 后续的异步读取仍受协调保护。应使用文件呈现器（file presenter）及文件变化处理机制，并验证外部修改文件的场景。

## 播放

使用 AVURLAsset/AVPlayerItem/AVPlayer 访问原始 URL。扩展名识别仅用于发现候选文件，不能保证编解码器支持。应检查可播放性及播放项状态，将不支持或损坏与文件缺失分别报告。所选歌曲可用后，再按需加载内嵌标签和封面。目录扫描结束后可单独为已确认驻留的歌曲读取时长，使用独立后台串行队列、读取前状态复核及超时，不创建播放器、不主动请求未下载文件。

- https://developer.apple.com/documentation/avfoundation/avplayer
- https://developer.apple.com/documentation/avfoundation/avurlasset/audiovisualcontenttypes
- https://developer.apple.com/documentation/avfoundation/avpartialasyncproperty/isplayable-45h5v

iOS 需处理音频会话的播放类别、后台音频模式、中断和音频路由变化。macOS 对 AVAudioSession 的使用方式不同。

- https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback

## Flutter 平台边界

Flutter 平台通道可在 iOS 和 macOS 上调用 Swift 代码。普通文件路径不代表持久访问权限，不得用其替代原生文件夹书签层。

- https://docs.flutter.dev/platform-integration/platform-channels
- https://docs.flutter.dev/platform-integration/ios/apple-frameworks
- https://docs.flutter.dev/platform-integration

编译 iOS 或 macOS 目标需要 macOS/Xcode，使用 Flutter 时也不例外。
