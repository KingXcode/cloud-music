# 0.7.0 全页面 Cupertino 组件迁移

本版不是更换 Material 配色，而是移除应用代码中的 Material 导入和控件。所有业务网关、音乐导入、歌词同意流程、播放控制、缓存与更新逻辑继续使用原实现。

## 页面与组件清单

| 界面 | 实际组件 |
| --- | --- |
| 应用入口、资料库 | `CupertinoApp`、`CupertinoPageScaffold`、`CupertinoTabBar` |
| 歌曲 / 专辑 / 歌手分类、搜索 | `CupertinoSlidingSegmentedControl`、`CupertinoSearchTextField` |
| 侧栏、歌曲、迷你播放器 | `CupertinoListTile`、`CupertinoButton`、Cupertino 图标 |
| 完整播放器、待播清单 | `CupertinoPageRoute`、`CupertinoPageScaffold`、`CupertinoButton` |
| 播放进度、音量 | `CupertinoSlider`；紧凑音量使用 `CupertinoActionSheet` |
| 资料库选项、添加音乐、来源、更新 | `showCupertinoModalPopup`、有宽高限制的 `CupertinoPageScaffold`、`CupertinoListTile` |
| 短音频过滤 | `CupertinoListSection`、`CupertinoSwitch`、`CupertinoTextField` |
| 歌词设置、候选和文字切换 | `CupertinoButton`、`CupertinoSlidingSegmentedControl`、`CupertinoSwitch` |
| 歌词联网同意、搜索、预览、粘贴、资料库提示、安装确认 | `CupertinoAlertDialog`、`CupertinoDialogAction`、`CupertinoTextField` |
| 字形转换开源许可 | `CupertinoPageRoute`、`CupertinoNavigationBar`、Cupertino 文本选择工具栏 |
| 加载与下载进度 | 未知进度使用 `CupertinoActivityIndicator`；已知进度使用带语义数值的只读进度条（Cupertino 没有线性进度原生控件） |

图标按钮的悬停/长按提示使用 Flutter Widgets 层的 `RawTooltip`，内部仍是 `CupertinoButton`，不会引入 Material。封面、渐变背景、只读状态标记等视觉元素继续用通用布局与绘制组件。

## 交互与适配

- 手机保留底部资料库 / 搜索，宽屏保留侧栏；分类使用真正的滑动分段控件。
- 播放器使用全屏 Cupertino 路由，返回后恢复搜索、分类和滚动位置。
- 管理弹层提供完成 / 关闭入口，支持返回键和外部点击关闭；表单弹层考虑键盘高度，内容可滚动。
- 暗色播放器及从其打开的歌词弹层显式继承 Cupertino 深色主题和文字样式。
- 48 点图标按钮、键盘可激活的管理列表、控件语义标签和读屏进度值；进度与音量支持读屏增减和键盘方向键 / Home / End，播放进度会真正提交跳转；中文 Cupertino 本地化保留中文复制、粘贴与系统返回文案。
- 保留重复打开保护、取消异步导入、歌词候选身份校验与更新安装确认。
- 发布版本号为 `0.7.0+12`。

## 验证与边界

本地静态分析无问题；Flutter 351 项回归通过（另 12 项按环境条件跳过）、138 项浏览器 JavaScript 逻辑测试、6 项发布清单测试和 Web Release 构建通过。额外执行 12 个视觉捕获场景，产生并检查 54 张合成曲库截图。自动化覆盖资料库、搜索、过滤、歌词和更新流程，以及窄屏、横屏、宽屏、大字体与键盘场景。视觉截图使用合成测试曲库，不包含真实用户音乐。

本次变更不代表 iCloud/Google Drive 真实账号、设备目录权限、USB、后台播放或系统安装器已在真机复测。浏览器端逻辑测试与 Flutter 组件截图不能替代已部署页面的浏览器实测。Android/iOS/macOS 安装包需平台构建环境；无构建产物时不宣称已发布新安装包。

本机未配置 Android SDK 或 Apple 构建环境，未产出新 APK / IPA / DMG。GitHub Actions 状态接口的既有访问限制没有绕过；部署验证以公开网页的发布清单与资源哈希为准。Web 字体裁剪器仍因 Flutter / 插件传递依赖报告 MaterialIcons 字体警告，应用代码和运行控件树均无 Material 控件，所用图标全部来自已打包的 CupertinoIcons。
