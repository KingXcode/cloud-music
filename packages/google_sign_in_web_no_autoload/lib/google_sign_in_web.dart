import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// 原生端使用官方 google_sign_in；网页端只使用 web/google_drive.js。
/// 官方网页插件在自动注册时便加载 GIS，空注册器避免本地音乐用户的额外网络请求。
/// 不实现或冒充网页登录能力，不替换 Android/iOS/macOS 的官方 SDK。
class GoogleSignInWebDisabled {
  static void registerWith(Registrar registrar) {}
}
