import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

bool get usesMacosWindowChrome =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// 页面背景延伸到原生标题栏下方，控件避让红黄绿按钮；避让高度由 AppKit
/// 提供，并随全屏状态更新。
class MacosWindowChrome extends StatefulWidget {
  const MacosWindowChrome({super.key, required this.child});

  final Widget child;

  @override
  State<MacosWindowChrome> createState() => _MacosWindowChromeState();
}

class _MacosWindowChromeState extends State<MacosWindowChrome> {
  static const _channel = MethodChannel('cloud_music/window_chrome');
  final _enabled = usesMacosWindowChrome;
  double _topInset = 28;

  @override
  void initState() {
    super.initState();
    if (_enabled) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'topInsetChanged') {
          _updateInset(call.arguments as num?);
        }
      });
      _readInset();
    }
  }

  Future<void> _readInset() async {
    try {
      _updateInset(await _channel.invokeMethod<num>('getTopInset'));
    } on MissingPluginException {
      // 兼容组件预览，以及尚未启用沉浸式标题栏的旧原生宿主。
      _updateInset(0);
    }
  }

  void _updateInset(num? value) {
    if (!mounted || value == null || !value.isFinite || value < 0) return;
    final inset = value.toDouble();
    if (inset != _topInset) setState(() => _topInset = inset);
  }

  @override
  void dispose() {
    if (_enabled) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          top: math.max(media.padding.top, _topInset),
        ),
        viewPadding: media.viewPadding.copyWith(
          top: math.max(media.viewPadding.top, _topInset),
        ),
      ),
      child: widget.child,
    );
  }
}
