# Android 0.5.0 Google Drive 预览

新增音乐来源入口与 Google Drive 官方只读接入实现。需要配置 Google OAuth 客户端、Android 包名和实际安装包签名 SHA 后才可直接登录；未配置的预览版显示明确说明，系统文件播放仍可用。

Google Drive 支持文件夹浏览、递归会话索引、受保护 HTTPS 播放、切换/取消/重新连接。没有真实 Google 账户或原生设备联调；后台播放、锁屏控制、音频焦点和车机行为尚未验收。Apple 安装包不包含在本次发布。

此 APK 使用测试/调试签名，不是生产签名。签名可能随构建变化，升级可能需要卸载旧版；Google OAuth 配置的 SHA 也必须匹配实际安装包。

完整配置与限制见 [Google Drive 文档](https://github.com/KingXcode/cloud-music/blob/main/docs/GOOGLE_DRIVE.md)。

通用 APK 包含 ARM64、ARM32 和 x86_64，要求 Android 7.0 / API 24 及以上。本应用不是 Android Auto 应用，请勿驾驶时操作。可通过随版本发布的 SHA256SUMS.txt、android-signature.txt 和 android-package.txt 核对文件、签名及架构。
