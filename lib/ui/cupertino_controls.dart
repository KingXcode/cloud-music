import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// An accessible Cupertino button with a platform-neutral hover/long-press hint.
/// RawTooltip belongs to Widgets, so this never introduces a Material ancestor.
class CupertinoIconControl extends StatelessWidget {
  const CupertinoIconControl({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
    this.backgroundColor,
    this.minimumSize = const Size(48, 48),
  });
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor, backgroundColor;
  final Size minimumSize;

  @override
  Widget build(BuildContext context) => RawTooltip(
    semanticsTooltip: label,
    hoverDelay: const Duration(milliseconds: 500),
    tooltipBuilder: (context, animation) => FadeTransition(
      opacity: animation,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 12),
          ],
        ),
        child: Text(
          label,
          style: CupertinoTheme.of(context).textTheme.textStyle
              .copyWith(fontSize: 13),
        ),
      ),
    ),
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: minimumSize,
      foregroundColor: foregroundColor,
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      onPressed: onPressed,
      child: icon,
    ),
  );
}

/// An icon-and-label action built from the actual Cupertino button.
class CupertinoActionButton extends StatelessWidget {
  const CupertinoActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });
  final Widget icon, label;
  final VoidCallback? onPressed;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 8),
        Flexible(child: label),
      ],
    );
    return filled
        ? CupertinoButton.filled(onPressed: onPressed, child: child)
        : CupertinoButton(onPressed: onPressed, child: child);
  }
}

/// Cupertino has no linear progress control. Determinate progress is a small
/// read-only track; unknown work uses CupertinoActivityIndicator, never a fake
/// percentage. The progress value remains available to assistive technology.
class CupertinoProgress extends StatelessWidget {
  const CupertinoProgress({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.minHeight = 3,
  });
  final double? value;
  final Color? color, backgroundColor;
  final double minHeight;
  @override
  Widget build(BuildContext context) {
    if (value == null) return const Center(child: CupertinoActivityIndicator());
    final progress = value!.clamp(0.0, 1.0);
    return Semantics(
      value: '${(progress * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(minHeight),
        child: SizedBox(
          height: minHeight,
          child: ColoredBox(
            color:
                backgroundColor ??
                CupertinoColors.systemFill.resolveFrom(context),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: progress,
                child: ColoredBox(
                  color: color ?? CupertinoTheme.of(context).primaryColor,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Native Cupertino slider with explicit non-pointer adjustment support.
/// CupertinoSlider's semantic increment does not call onChangeEnd. Committing
/// here keeps seeking functional for screen readers and desktop keyboards.
class CupertinoValueSlider extends StatefulWidget {
  const CupertinoValueSlider({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.formatValue,
    this.activeColor,
    this.step = .05,
  });
  final double value, step;
  final String label;
  final ValueChanged<double>? onChanged, onChangeStart, onChangeEnd;
  final String Function(double)? formatValue;
  final Color? activeColor;
  @override
  State<CupertinoValueSlider> createState() => _CupertinoValueSliderState();
}

class _SliderAdjustment extends Intent {
  const _SliderAdjustment(this.delta, {this.absolute = false});
  final double delta;
  final bool absolute;
}

class _CupertinoValueSliderState extends State<CupertinoValueSlider> {
  final _focus = FocusNode();
  bool _highlight = false;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  String _format(double value) =>
      widget.formatValue?.call(value) ?? '${(value * 100).round()}%';
  double _next(double delta) => (widget.value + delta).clamp(0.0, 1.0);
  void _adjust(double value) {
    if (widget.onChanged == null) return;
    widget.onChanged!(value);
    widget.onChangeEnd?.call(value);
  }

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    focusNode: _focus,
    enabled: widget.onChanged != null,
    onShowFocusHighlight: (value) => setState(() => _highlight = value),
    shortcuts: {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): _SliderAdjustment(
        -widget.step,
      ),
      const SingleActivator(LogicalKeyboardKey.arrowDown): _SliderAdjustment(
        -widget.step,
      ),
      const SingleActivator(LogicalKeyboardKey.arrowRight): _SliderAdjustment(
        widget.step,
      ),
      const SingleActivator(LogicalKeyboardKey.arrowUp): _SliderAdjustment(
        widget.step,
      ),
      const SingleActivator(LogicalKeyboardKey.home): const _SliderAdjustment(
        0,
        absolute: true,
      ),
      const SingleActivator(LogicalKeyboardKey.end): const _SliderAdjustment(
        1,
        absolute: true,
      ),
    },
    actions: {
      _SliderAdjustment: CallbackAction<_SliderAdjustment>(
        onInvoke: (intent) {
          _adjust(intent.absolute ? intent.delta : _next(intent.delta));
          return null;
        },
      ),
    },
    child: Semantics(
      label: widget.label,
      value: _format(widget.value),
      slider: true,
      enabled: widget.onChanged != null,
      increasedValue: widget.onChanged == null
          ? null
          : _format(_next(widget.step)),
      decreasedValue: widget.onChanged == null
          ? null
          : _format(_next(-widget.step)),
      onIncrease: widget.onChanged == null
          ? null
          : () => _adjust(_next(widget.step)),
      onDecrease: widget.onChanged == null
          ? null
          : () => _adjust(_next(-widget.step)),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _highlight
                  ? CupertinoTheme.of(context).primaryColor
                  : CupertinoColors.transparent,
            ),
          ),
          child: CupertinoSlider(
            value: widget.value,
            activeColor: widget.activeColor,
            onChanged: widget.onChanged,
            onChangeStart: (value) {
              _focus.requestFocus();
              widget.onChangeStart?.call(value);
            },
            onChangeEnd: widget.onChangeEnd,
          ),
        ),
      ),
    ),
  );
}
