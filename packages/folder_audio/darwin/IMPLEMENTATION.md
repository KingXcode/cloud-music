# Apple 桥接实现与验证说明

按照应用的 `docs/BRIDGE_CONTRACT.md` 实现，目标平台为 iOS 15 和 macOS 12。Flutter 通道为 `cloud_music/control` 和 `cloud_music/events`。

## 存储与访问

- 系统目录选择器打开原始文件夹，不导入或复制歌曲。
- iOS 使用最小书签，macOS 使用只读安全作用域书签。成功开启安全作用域的调用都有对应的停止调用，准备和播放期间保持作用域有效。
- 唯一持久化文件是应用自有的 Application Support/CloudMusic/library.json，保存书签、元数据和偏好设置；此实现不持久化音频。
- 后台协调枚举使用 `.immediatelyAvailableMetadataOnly`，而非 `.withoutChanges`，且不遍历符号链接目录。启动时保留缺失条目。刷新时，只有父目录枚举成功并且直接得到 Cocoa 文件不存在的结果后，才移除引用。发生错误或遇到云端占位文件时保留原条目。已知离线的 iCloud 根目录不能用于确认删除。
- iCloud 下载由系统管理，仍会占用设备存储。取消操作会停止等待，并使待处理的播放器操作失效，但不会删除或取消 Apple 的缓存下载。
- 文件提供器协调本身可能阻塞。并发后台任务和代次令牌允许新的播放或来源请求继续执行，同时拒绝过期结果。

## 播放

AVPlayer 使用原始 URL，并通过文件呈现器处理外部写入、移动和删除。仅为选中的歌曲加载元数据和有大小限制的封面。已实现队列控制、随机播放、循环播放、进度跳转、音量、iOS 后台音频、中断/音频路由处理及系统媒体命令。解码失败不会被视为文件已删除。

## 打包

SwiftPM 处理 PrivacyInfo.xcprivacy，CocoaPods 将其作为资源包包含。此实现不使用 UserDefaults、文件时间戳、磁盘空间 API 或其他需要声明使用理由的 API；隐私清单声明不收集数据，也不进行追踪。如新增 SDK 或 API，须重新评估。macOS Runner 具有应用沙盒、用户所选文件只读访问和应用作用域书签授权。iOS Runner 启用了后台音频模式，未申请应用自有 iCloud 容器授权。

## 验证状态

已在 Linux 中完成静态源码审查和 XML/plist 解析。该工作区没有 Swift 编译器、Apple SDK、Xcode、代码签名环境或真机，因此**尚未验证 Apple 平台构建**。需运行托管 macOS CI，再执行 `docs/REQUIREMENTS.md` 中完整的设备测试矩阵，特别关注第三方文件提供器和离线枚举、过期或撤销的授权、正在播放的文件被外部重命名、下载期间中断、取消/重新选择，以及真实 iCloud 占位文件行为。未签名 CI 构建成功，不能证明签名后的 iCloud 访问或音频路由正确。

已知限制：超过 2 MB 的封面会被忽略；不支持交叉淡入淡出或均衡器；暂停的文件保留授权，直到播放或来源被替换；书签和索引仅属于当前应用安装，不跨设备同步。仅凭本源码无法保证下载的二进制文件已完成代码签名或公证。

## 文件协调修正与删除防护

Apple 明确说明，[立即可用的纯元数据读取选项 immediatelyAvailableMetadataOnly](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/immediatelyavailablemetadataonly) 可避免触发下载或将文件内容实体化。[不作更改选项 withoutChanges](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/withoutchanges) 仅抑制向文件呈现器发出的保存请求，不能用作替代。所有索引、缺失检查和下载状态轮询现均使用前者，清除缓存的 URL 元数据，并将协调器注册到操作的取消令牌。显式发起 iCloud 下载与纯元数据协调相互独立；针对所选歌曲，另行执行普通协调读取，有意允许文件提供器将内容实体化，这对非 iCloud 提供器尤为重要。AVPlayer 仍通过已注册的文件呈现器读取协调器提供的原始 URL；准备超时时也会取消该协调器。

取消时调用 [NSFileCoordinator.cancel 取消方法](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel())，每次协调还设置 15 秒定时器，以取消对文件呈现器的等待。主线程上的独立超时机制会在 90 秒后结束播放准备、180 秒后结束扫描，保留旧索引并忽略延迟完成结果。Apple 文档指出，取消无法中止已经执行中的访问闭包。因此，卡住的文件提供器系统调用可能会一直占用后台工作线程和安全作用域，直到调用返回；但不会让界面无限加载，也不会安装过期播放器。应用不承诺强制中断任意操作系统文件提供器调用。

刷新现会持久化并检查来源卷 UUID，在 macOS 上以不重新挂载卷的方式解析书签，比较扫描前后的根目录标识，并在确认子项缺失前重新枚举未发生变化且非空的父目录。遇到标识未知、网络不可用、远程卷、任何祖先目录状态不确定或子树意外为空时，拒绝清理索引。扫描期间断网会丢弃待执行的索引核对结果。若原本有内容的子树因最后一首歌被删除而变为空，此策略会有意保留该歌曲条目，因为在这一层无法将其与文件提供器视图不完整的情况区分。重新选择文件夹会明确重建列表。旧索引首次只补充卷标识，不执行清理。仍需进行文件提供器和设备测试。

## 0.5.1 promised 元数据与渐进列表

所有 metadata-only 协调闭包现通过 `CloudFileMetadata.promisedValues` 使用 `promisedItemResourceValues(forKeys:)`；Apple 明确要求这一搭配。目录枚举不预取普通属性。先分批显示文件名，再补系统可用状态，属性缺失不再默认视为 ready。播放完成/失败状态有修订保护，不被较早扫描覆盖。新增纯 Foundation 检查由 `apple-metadata.yml` 在 macOS 执行；完整 Apple 应用编译和真实 iCloud 验证仍须单独执行。详见 [按需读取说明](../../../docs/ICLOUD_ON_DEMAND.md)。
