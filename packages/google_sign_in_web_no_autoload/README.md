# 云听专用的网页空注册器

应用使用官方 `google_sign_in` 的原生实现，但网页 Google Drive 使用自己调用官方 GIS token client 的桥接。上游 `google_sign_in_web` 在 Flutter 自动注册阶段就加载 Google GIS 脚本，即使没有配置 Client ID、也没有用户连接操作。

根 pubspec 的 `dependency_overrides` 将**网页实现**限定为这个空注册器，避免不必要的启动网络请求与重复 SDK 加载。它不提供登录功能，不修改 Android/iOS/macOS 的官方插件。网页授权仍由 `web/google_drive.js` 在用户点击后加载 `https://accounts.google.com/gsi/client` 并处理 Google 官方授权。

这是本应用的组合方式，不是通用 `google_sign_in_web` 替代品；其他项目不应引用。若将来改用官方 Flutter 网页登录组件，应移除这个 override 并重新验证加载和授权行为。
