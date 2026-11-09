import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'cupertino_controls.dart';

/// A bounded Cupertino sheet that also preserves the caller's light/dark theme.
Future<T?> showSettingsPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final theme = CupertinoTheme.of(context);
  return showCupertinoModalPopup<T>(
    context: context,
    semanticsDismissible: true,
    builder: (context) => CupertinoTheme(
      data: theme,
      child: Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            width: 600,
            height:
                (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom) *
                .88,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: CupertinoPageScaffold(
                resizeToAvoidBottomInset: false,
                backgroundColor: CupertinoColors.systemGroupedBackground
                    .resolveFrom(context),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: DefaultTextStyle(
                      style: CupertinoTheme.of(context).textTheme.textStyle,
                      child: builder(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.contentPadding,
  });
  final Widget title;
  final Widget? subtitle, leading, trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final EdgeInsetsGeometry? contentPadding;
  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: enabled && onTap != null,
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          if (enabled) onTap?.call();
          return null;
        },
      ),
    },
    child: Semantics(
      button: onTap != null,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: CupertinoListTile(
          padding:
              contentPadding ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          title: DefaultTextStyle.merge(maxLines: 10, child: title),
          subtitle: subtitle == null
              ? null
              : DefaultTextStyle.merge(maxLines: 20, child: subtitle!),
          leading: leading,
          trailing: trailing,
          onTap: enabled ? onTap : null,
        ),
      ),
    ),
  );
}

class SettingsIconButton extends StatelessWidget {
  const SettingsIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });
  final VoidCallback? onPressed;
  final Widget icon;
  final String tooltip;
  @override
  Widget build(BuildContext context) =>
      CupertinoIconControl(label: tooltip, icon: icon, onPressed: onPressed);
}

class SettingsAction extends StatelessWidget {
  const SettingsAction({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
  });
  final VoidCallback? onPressed;
  final Widget icon, label;
  final bool filled;
  @override
  Widget build(BuildContext context) => CupertinoActionButton(
    icon: icon,
    label: label,
    onPressed: onPressed,
    filled: filled,
  );
}

class SettingsSeparator extends StatelessWidget {
  const SettingsSeparator({super.key, this.height = 20});
  final double height;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: height / 2),
    child: Container(
      height: .5,
      color: CupertinoColors.separator.resolveFrom(context),
    ),
  );
}

class SettingsProgress extends StatelessWidget {
  const SettingsProgress({super.key, this.value, this.semanticsLabel = '正在读取'});
  final double? value;
  final String semanticsLabel;
  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    child: CupertinoProgress(value: value, minHeight: 4),
  );
}
