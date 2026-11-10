# iCloud 列表与按需读取（0.5.1）

## Apple 原生应用

选择文件夹后，目录扫描只读取名称和系统提供的属性。同层音频候选先按文件名显示，再补充可用状态；子目录继续扫描时，已显示的歌曲可以点播。扫描使用 `immediatelyAvailableMetadataOnly` 协调，并在协调闭包内调用 `promisedItemResourceValues`，不读取音频内容。目录枚举也不预取普通资源属性。

目录扫描完成后，独立串行后台队列为“内容可用”且尚无时长的歌曲读取并缓存时长，无需播放。已有缓存直接使用；结果分批刷新列表，不影响播放。每次读取前重新检查驻留状态，跳过未下载、状态不明、符号链接及不可用文件；读取失败或超时保留未知时长，下次启动或刷新时可重试。刷新、取消导入和更换来源会使旧批次失效。仅请求时长，不提前加载封面及标签，也不调用 iCloud 下载接口。文件提供器可能在状态检查后回收或重新准备文件，应用无法锁定系统的驻留策略。

- 系统明确报告 `notDownloaded`，或返回旧式 `.歌曲.mp3.icloud` 占位文件：内部标记为云端歌曲，播放时再下载。
- 系统报告 `current` / `downloaded`：内容已在本机。普通本地文件必须有可确认的类型和卷属性。
- 属性不全、提供器状态不明：内部保留未知状态，不推断成已下载或未下载。
- 启动先显示缓存列表，缓存中的可用状态重新检查，避免沿用已经过期的“内容可用”。
- 未下载歌曲在点歌后才请求该项的 iCloud 下载，等待系统准备原始 URL，再交给 AVPlayer。播放时补充封面、标签及准确时长。
- 切歌、取消和更换来源会使旧结果失效。扫描不会覆盖刚获得的播放元数据或错误状态。取消只停止应用等待，不删除缓存，也不能保证系统停止下载。

首次列表只能包含系统当时提供的目录元数据。如果 iCloud 尚未同步目录信息，应用无法凭空列出完整云端清单；可待系统同步后刷新。遇到慢目录或报错，保留已发现的歌曲及旧记录。应用不会删除、移动或写入源音频。

列表不再展示“内容可用”等静态状态标签。正常、云端待下载和待确认歌曲按普通样式显示；权限不足、离线、文件缺失或格式不支持的歌曲置灰，仍可点击重试；正在准备的歌曲保留加载提示。

## macOS / iOS 网页

浏览器不能使用 Apple 的 iCloud 下载状态 API，不能可靠区分“云端未下载”和“已经在本机”。因此网页采用不同且明确的状态：

- `unloaded`：已有文件句柄或当前会话的 File 引用，本页尚未验证播放，不等于未下载。
- `accessRequired`：只有缓存的歌曲名称，尚无可用访问权限，列表置灰。
- `loading`：正在读取当前歌曲或等待浏览器播放，显示“正在准备”。
- `ready`：浏览器已经发出可播放/播放事件，不代表永久离线缓存，不额外显示标签。

支持 `showDirectoryPicker` 的浏览器只枚举名称和句柄，第一首立即显示，后续分批显示；只有点播才调用该文件的 `getFile()`。不把整库音频写入 IndexedDB，也不上传音频。播放准备等待有时限，取消、切歌和超时后会忽略迟到的结果。

Safari（含 iOS/iPadOS 18.4+）的目录输入回退，以及独立的文件多选，只能等系统选择器交回 File 列表后显示。**系统可能在交回选择结果前就下载文件，网页无法保证“完整列出所有未下载歌曲，点播时才开始下载”。** 本页不会为扫描主动读取音频内容；它无法控制选择器及 iCloud 文件提供器。刷新网页后，文件输入方式须重新选择，支持持久句柄的浏览器则尝试恢复已授权目录。

## 验证范围

新增浏览器回归测试覆盖渐进列表、不读音频、扫描途中点播、来源替换回滚、旧请求抑制、不可恢复访问状态、非阻塞目录保存、准备超时和取消。新增 Flutter 测试覆盖扫描期间的可点击列表、空列表扫描提示及状态解析。

`Verify Apple metadata-only indexing` 工作流在 macOS 上编译并运行纯 Foundation 状态规则和普通本地文件的 promised-metadata 协调用例，并使用 Flutter 框架与 Apple SDK 对完整桥接执行 iOS/macOS 类型检查。这不是完整的 Flutter Apple 应用编译，也不是 iCloud 真机测试。Pages 与 Android 工作流仍执行各自的完整检查和发布构建。

仍需使用签名后的 iOS/macOS 应用及真实 Safari/iCloud 验收：
1. 同目录混合已下载、未下载、大文件、嵌套目录；扫描时不批量下载。
2. 目录尚未同步或断网时刷新，不能清空已知歌曲或误报全部可用。
3. 扫描中点播、快速切歌、下载中取消、超时、切换来源，不得播放旧请求。
4. 下载后在“文件”或 Finder 中移除本地下载，再刷新检查状态。
5. iPhone Safari 18.4+ 目录选择、多选与 Mac Safari 目录选择，验证系统提前下载、取消、重试及重新打开页面的提示符合实际。

平台依据：[Apple promised-item 属性](https://developer.apple.com/documentation/foundation/url/promiseditemresourcevalues(forkeys:))、[Apple metadata-only 协调](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/immediatelyavailablemetadataonly)、[Apple 按需下载](https://developer.apple.com/documentation/foundation/filemanager/startdownloadingubiquitousitem(at:))、[MDN 目录选择器](https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker)、[MDN 文件句柄读取](https://developer.mozilla.org/en-US/docs/Web/API/FileSystemFileHandle/getFile)。
