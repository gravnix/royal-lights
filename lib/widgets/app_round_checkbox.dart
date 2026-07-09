import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Large rounded-square checkbox; no grey hover overlay; soft scale on toggle.
class AppAnimatedSquareCheckbox extends StatefulWidget {
  const AppAnimatedSquareCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.activeColor,
    this.size = 28,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;
  final Color activeColor;

  /// Base box size (before [scale]); visual size ≈ `size * scale`.
  final double size;

  /// Extra visual scale (crisp Material checkbox drawn larger).
  static const double scale = 1.32;

  static BorderRadius borderRadiusFor(double boxSize) {
    final r = (boxSize * 0.22).clamp(6.0, 10.0);
    return BorderRadius.circular(r);
  }

  @override
  State<AppAnimatedSquareCheckbox> createState() =>
      _AppAnimatedSquareCheckboxState();
}

class _AppAnimatedSquareCheckboxState extends State<AppAnimatedSquareCheckbox>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Subtle, slow ease — no sharp back curve.
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.08).chain(
          CurveTween(curve: Curves.easeInOutCubic),
        ),
        weight: 42,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.08, end: 0.97).chain(
          CurveTween(curve: Curves.easeInOutCubic),
        ),
        weight: 36,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.97, end: 1.0).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 22,
      ),
    ]).animate(_pulse);
  }

  @override
  void didUpdateWidget(covariant AppAnimatedSquareCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && widget.onChanged != null) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: AppAnimatedSquareCheckbox.borderRadiusFor(widget.size),
    );

    final outer = (widget.size * AppAnimatedSquareCheckbox.scale * 1.22).ceil();

    final checkboxTheme = CheckboxThemeData(
      splashRadius: 0,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
    );

    return SizedBox(
      width: outer.toDouble(),
      height: outer.toDouble(),
      child: Center(
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            checkboxTheme: checkboxTheme,
          ),
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Transform.scale(
              scale: AppAnimatedSquareCheckbox.scale,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Checkbox(
                  value: widget.value,
                  onChanged: widget.onChanged,
                  shape: shape,
                  splashRadius: 0,
                  side: WidgetStateBorderSide.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return BorderSide(color: widget.activeColor, width: 2.5);
                    }
                    if (states.contains(WidgetState.disabled)) {
                      return BorderSide(
                        color: AppTheme.outlineVariant.withValues(alpha: 0.35),
                      );
                    }
                    return BorderSide(
                      color: AppTheme.outlineVariant.withValues(alpha: 0.55),
                      width: 2,
                    );
                  }),
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return AppTheme.surfaceContainerHighest
                          .withValues(alpha: 0.35);
                    }
                    if (states.contains(WidgetState.selected)) {
                      return widget.activeColor;
                    }
                    return Colors.transparent;
                  }),
                  checkColor: Colors.white,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
