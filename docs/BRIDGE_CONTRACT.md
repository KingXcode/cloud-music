# 共享平台桥接接口约定

方法通道：`cloud_music/control`。事件通道：`cloud_music/events`。
所有事件均为完整快照映射。所有方法都可以返回当前快照；Dart 忽略修改操作的返回值，通过事件接收状态。`initialize` 必须立即返回已加载的快照，再异步校验已有歌曲，启动时保留缺失条目。取消 `pickFolder` 时保留原音乐库。忙碌期间重复调用必须安全。Web 输入回退方案在打开选择面板后即完成选择命令，再通过快照事件发布成功选择的结果；调用方不得要求命令返回值中必须包含选择结果。播放和来源变化必须使尚未完成的异步操作失效。

方法：`initialize`、`pickFolder`、`pickFiles`（Web）、`scanDevice`（Android）、`cancelImport`（本地导入取消）、`refresh`、`play`（`id`：字符串）、`togglePlayback`、`pause`、`next`、`previous`、`seek`（`positionMs`：整数）、`setShuffle`（`enabled`：布尔值）、`setRepeat`（`mode`：`off`/`all`/`one`）、`setVolume`（`volume`：0–1 的双精度浮点数）、`cancelLoading`。

快照字段：

- `folderName`：字符串或 null；`sourceKind`：`apple`、`android` 或 `web`
- `selectionMode`：可选，值为 `folder`（默认）或 `files`；Web 适配器在旧版 iOS/iPadOS 或不支持目录选择的浏览器中使用 `files`；支持目录输入的 Safari 18.4+ 使用 `folder`
- `importRevision`：非持久整数，默认为 0；只有显式导入完成且发现至少一首歌曲后递增。取消、失败、空导入和普通刷新不递增。来源路由器在等待导入时继续保留当前 Google Drive 来源与播放，仅观察到新成功版本后才切换。
- `canPickFiles` / `canScanDevice`：可选布尔，分别表示可提供独立多文件选择 / Android 本机音乐扫描入口
- `tracks`：映射数组，每项包含 `id`：稳定的字符串标识；`title`：字符串；`artist`：字符串（允许为空）；`album`：字符串（允许为空）；`relativePath`：用于显示的字符串；`status`：`ready`/`cloud`/`unloaded`/`accessRequired`/`loading`/`offline`/`missing`/`unsupported`/`unknown`；`durationMs`：非负整数（未知时为 0）
- `currentTrackId`：字符串或 null
- `playbackSessionId`：字符串或 null，仅在一轮播放实际开始后生成。手动重播、自动切歌和单曲循环使用新值；暂停续播、缓冲和拖动进度保留原值。新歌曲准备期间清空，失败不生成，Dart 据此去重统计播放次数。
- `isPlaying`、`isLoading`、`isScanning`、`shuffle`：布尔值
- `positionMs`、`durationMs`：非负整数
- `repeatMode`：`off`/`all`/`one`；`volume`：0–1 的双精度浮点数
- `artwork`：可选，当前歌曲的平台类型化字节数据（FlutterStandardTypedData / byte[]），应控制在合理大小
- `message`：字符串或 null。优先使用易懂的中文，在此显示用户可处理或可恢复的问题。

默认值：布尔值为 false，时间为 0，音量为 1，循环模式关闭，歌曲列表为空。

仅持久化元数据、书签/目录树 URI 和偏好设置，不保存音频。根目录由用户明确选择；绝不删除、移动、写入或复制源文件。启动时进行校验和标记；手动刷新时发现新歌曲，并移除已确认缺失的索引条目。USB 未挂载、权限错误、iCloud 占位文件或离线、扫描不完整均不能作为删除证据。子目录报错时保留该目录的原有条目，根目录报错时保留全部原有条目。首次选择时递归扫描，依据音频 MIME、类型或扩展名发现候选文件，再通过播放器错误验证编解码支持，不删除不支持的条目。


## 可选歌词桥接（0.2）

快照还提供 `sourceIdentity`：持久化的不透明来源标识，具体为 Apple 根目录 UUID、
Android 目录树 URI、`mediastore:audio` 或浏览器根目录 UUID。该标识仅用于隔离本地缓存，
不会发送给歌词服务。名称相同但实际不同的文件夹不得共用该标识。
重新选择 Apple 文件夹或通过浏览器文件输入重新选择时，会创建新标识。

原生 `cloud_music/control` 额外支持：

- `readLyricsCache`（无参数）-> 可空的 UTF-8 JSON 字符串。
- `writeLyricsCache`（`value`：字符串）-> null。在应用自有存储中原子写入，最大 2 MiB。
- `importLyrics`（无参数）-> 所选 UTF-8 LRC/TXT 字符串，取消时返回 null。
  最大 256 KiB，不申请所选原始文件的写入或删除权限。

这些方法返回各自的结果，不返回音乐库快照。错误码包括
`lyrics_error`、`invalid_arguments`、`picker_busy` 或 `no_activity`。
需用户明确同意的歌词服务流程及限制见[歌词文档](LYRICS.md)。

## 渐进索引与浏览器状态（0.5.1）

扫描可发布 `isScanning=true` 的局部列表，已发现条目可播放。`unloaded` 表示有文件引用但尚未验证可读，不等于云端未下载；`accessRequired` 表示只有缓存元数据，需要恢复授权或重新选择；`loading` 表示当前播放准备。Web 只有媒体可播放事件后才标记 `ready`，不使用 `cloud` 猜测 iCloud 状态。Apple 缺少资源属性时使用 `unknown`。

## 资料库显示过滤偏好

`readLibraryFilter` 返回独立 JSON 字符串或 null；`writeLibraryFilter({value: String})` 保存不超过 512 字节的 UTF-8 设置。Apple 和 Android 仅访问本应用私有 `library-filter.json`，串行、原子写入，与曲库、歌词缓存和源音频隔离。格式为 `{"version":1,"enabled":true,"minimumSeconds":30}`；Dart 校验 1–600 秒整数。网页同格式使用独立 localStorage key。该接口不触发来源扫描、元数据读取或音频下载，设置应用于资料库显示，不修改播放队列。

## 播放统计缓存

原生额外支持 `readPlaybackStats`（返回可空 JSON 字符串）、`writePlaybackStats({value: String})`（返回 null）、`playbackStatsDeviceId`（返回本机持久设备标识）及 `playbackStatsStorageLocation`（Apple 返回 `folder` 或 `local`，Android 返回 `local`）。Apple 的 `pickPlaybackStatsFolder` 打开系统目录选择器，成功连接返回 true，取消返回 false；独立保存统计目录的读写书签，不改变音乐来源。

统计 JSON 最大 8 MiB，格式为 `{"version":1,"counts":{"trackKey":{"deviceId":1}}}`。读写在后台串行队列执行并原子保存，同一歌曲和设备分量按最大值合并，损坏缓存保留原件。Apple 使用用户选定的个人文件夹并保留本地副本，无需开发者 iCloud 容器；实际云同步取决于所选位置。Android 使用应用私有目录，网页使用独立浏览器存储。首次连接及同步限制见[播放统计与个人 iCloud 保存](PLAYBACK_STATISTICS.md)。

## 本机音乐扫描

`scanDevice` 只在 Android 提供。权限检查与弹窗由显式命令触发，不在 `initialize` 中申请。`refresh` 根据当前来源重扫所选 SAF 目录或本机媒体库。来源路由器将 `pickFolder`、`pickFiles`、`scanDevice` 发往本地网关，即使此前在使用 Google Drive。Dart 控制器暴露本地能力，避免网盘快照隐藏本机入口。扫描结果以完整快照和 `isScanning` 发布，取消及来源变更使旧结果失效。隐私和实际限制见[本机导入](LOCAL_MUSIC_IMPORT.md)。

等待本地导入时，`isLocalImportScanning` / `localImportMessage` 暴露独立进度，`cancelLocalImport` 路由到本地 `cancelImport`，仅取消本地工作，不暂停 Google Drive。失败和权限拒绝作为可关闭提示展示。来源路由器在调用系统选择器前不等待停止播放或网络操作，保留浏览器的用户手势。
