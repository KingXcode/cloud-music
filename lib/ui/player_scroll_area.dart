import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

/// 播放器的轻量滚动提示，滚动条与正文之间保留独立留白。
class PlayerScrollArea extends StatelessWidget {
  const PlayerScrollArea({
    super.key,
    required this.controller,
    required this.child,
    this.hideAutomaticScrolling = false,
  });

  final ScrollController controller;
  final Widget child;
  final bool hideAutomaticScrolling;

  @override
  Widget build(BuildContext context) {
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    if (!desktop) return child;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: RawScrollbar(
        controller: controller,
        thumbColor: const Color(0x47FFFFFF),
        thickness: 3,
        radius: const Radius.circular(3),
        mainAxisMargin: 12,
        crossAxisMargin: 6,
        minThumbLength: 32,
        timeToFade: const Duration(milliseconds: 650),
        fadeDuration: const Duration(milliseconds: 200),
        interactive: true,
        notificationPredicate: (notification) {
          if (notification.depth != 0) return false;
          if (!hideAutomaticScrolling ||
              notification is! ScrollUpdateNotification ||
              notification.scrollDelta == null) {
            return true;
          }
          // 更新布局指标，但不因歌词自动跟随而反复唤出滚动条。
          return notification.dragDetails != null ||
              (controller.hasClients &&
                  controller.position.userScrollDirection !=
                      ScrollDirection.idle);
        },
        child: Padding(padding: const EdgeInsets.only(right: 24), child: child),
      ),
    );
  }
}
