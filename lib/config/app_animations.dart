import 'package:flutter/material.dart';

/// Shared animation durations and curves for a heavier, more deliberate feel.
class AppAnimations {
  AppAnimations._();

  static const Duration durationFast = Duration(milliseconds: 220);
  static const Duration durationNormal = Duration(milliseconds: 380);
  static const Duration durationMedium = Duration(milliseconds: 500);
  static const Duration durationSlow = Duration(milliseconds: 650);

  /// Heavier curve: more deceleration at the end (weight settling).
  static const Curve curveDefault = Curves.easeOutQuart;
  static const Curve curveEmphasized = Curves.easeOutCubic;
  static const Curve curveGentle = Curves.easeInOutCubic;
}

/// Fades in a single child with optional slide and subtle scale for a heavier feel.
class AnimatedFadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final bool slideUp;
  /// Slight scale-up from this value to 1 (e.g. 0.96) for a weighted landing.
  final double scaleBegin;

  const AnimatedFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppAnimations.durationMedium,
    this.curve = AppAnimations.curveDefault,
    this.slideUp = false,
    this.scaleBegin = 1.0,
  });

  @override
  State<AnimatedFadeIn> createState() => _AnimatedFadeInState();
}

class _AnimatedFadeInState extends State<AnimatedFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _opacity = curved;
    _offset = Tween<Offset>(
      begin: widget.slideUp ? const Offset(0, 24) : Offset.zero,
      end: Offset.zero,
    ).animate(curved);
    _scale = Tween<double>(
      begin: widget.scaleBegin,
      end: 1.0,
    ).animate(curved);

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        Widget result = child!;
        if (widget.slideUp) {
          result = Transform.translate(
            offset: _offset.value,
            child: result,
          );
        }
        if (widget.scaleBegin < 1.0) {
          result = Transform.scale(
            scale: _scale.value,
            alignment: Alignment.center,
            child: result,
          );
        }
        return Opacity(
          opacity: _opacity.value,
          child: result,
        );
      },
      child: widget.child,
    );
  }
}

/// Replays a fade + soft rise whenever [active] becomes true.
/// Use for tab panes / lists that stay mounted across switches.
class AppearOnActivate extends StatefulWidget {
  const AppearOnActivate({
    super.key,
    required this.active,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppAnimations.durationNormal,
    this.curve = AppAnimations.curveDefault,
    this.slideDy = 16,
    this.scaleBegin = 0.985,
  });

  final bool active;
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final double slideDy;
  final double scaleBegin;

  @override
  State<AppearOnActivate> createState() => _AppearOnActivateState();
}

class _AppearOnActivateState extends State<AppearOnActivate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _bindTweens();
    if (widget.active) {
      _play();
    } else {
      _controller.value = 0;
    }
  }

  void _bindTweens() {
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _opacity = curved;
    _offset = Tween<Offset>(
      begin: Offset(0, widget.slideDy),
      end: Offset.zero,
    ).animate(curved);
    _scale = Tween<double>(
      begin: widget.scaleBegin,
      end: 1,
    ).animate(curved);
  }

  Future<void> _play() async {
    if (widget.delay > Duration.zero) {
      await Future<void>.delayed(widget.delay);
      if (!mounted || !widget.active) return;
    }
    _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant AppearOnActivate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.curve != oldWidget.curve ||
        widget.slideDy != oldWidget.slideDy ||
        widget.scaleBegin != oldWidget.scaleBegin) {
      _bindTweens();
    }
    if (widget.active && !oldWidget.active) {
      _play();
    } else if (!widget.active && oldWidget.active) {
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: _offset.value,
            child: Transform.scale(
              scale: _scale.value,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Cross-fade + soft slide/scale for kept-alive panes (nav pages, tab bodies).
/// Inactive children stay mounted so scroll/filter state survives.
class AnimatedVisibilityPane extends StatelessWidget {
  const AnimatedVisibilityPane({
    super.key,
    required this.active,
    required this.child,
    this.slideDx = 0,
    this.slideDy = 0.014,
    this.duration = AppAnimations.durationNormal,
    this.appearContent = true,
    this.appearDelay = const Duration(milliseconds: 40),
    this.appearSlideDy = 16,
  });

  final bool active;
  final Widget child;
  final double slideDx;
  final double slideDy;
  final Duration duration;
  final bool appearContent;
  final Duration appearDelay;
  final double appearSlideDy;

  @override
  Widget build(BuildContext context) {
    final content = appearContent
        ? AppearOnActivate(
            active: active,
            delay: appearDelay,
            slideDy: appearSlideDy,
            scaleBegin: 0.988,
            child: child,
          )
        : child;

    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: duration,
          curve: active
              ? AppAnimations.curveDefault
              : AppAnimations.curveGentle,
          child: AnimatedSlide(
            offset: active ? Offset.zero : Offset(slideDx, slideDy),
            duration: duration,
            curve: active
                ? AppAnimations.curveDefault
                : AppAnimations.curveGentle,
            child: AnimatedScale(
              scale: active ? 1 : 0.985,
              duration: duration,
              curve: AppAnimations.curveGentle,
              alignment: Alignment.topCenter,
              child: TickerMode(
                enabled: active,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a list/grid child with a staggered fade-in (use index for delay).
class StaggeredFadeIn extends StatefulWidget {
  final Widget child;
  final int index;
  final int stepMilliseconds;
  final double slideDy;

  const StaggeredFadeIn({
    super.key,
    required this.child,
    this.index = 0,
    this.stepMilliseconds = 45,
    this.slideDy = 10,
  });

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.durationNormal,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.curveDefault,
    );
    _opacity = curved;
    _offset = Tween<Offset>(
      begin: Offset(0, widget.slideDy),
      end: Offset.zero,
    ).animate(curved);
    final delay =
        Duration(milliseconds: widget.index * widget.stepMilliseconds);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: _offset.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
