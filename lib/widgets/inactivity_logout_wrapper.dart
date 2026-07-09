import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../providers/providers.dart';
import '../screens/login_screen.dart';

/// Signs the user out after a fixed period of input inactivity.
/// Resets the timer on any pointer interaction, keyboard input, or focus change.
class InactivityLogoutWrapper extends ConsumerStatefulWidget {
  static const Duration timeout = Duration(minutes: 20);

  final Widget child;

  const InactivityLogoutWrapper({super.key, required this.child});

  @override
  ConsumerState<InactivityLogoutWrapper> createState() =>
      _InactivityLogoutWrapperState();
}

class _InactivityLogoutWrapperState
    extends ConsumerState<InactivityLogoutWrapper> {
  Timer? _timer;
  bool _signingOut = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _resetTimer();
    // Listen to focus changes (indicates user is interacting with the app)
    _focusNode.addListener(_onActivity);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.removeListener(_onActivity);
    _focusNode.dispose();
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(InactivityLogoutWrapper.timeout, _handleTimeout);
  }

  Future<void> _handleTimeout() async {
    if (_signingOut || !mounted) return;
    _signingOut = true;
    try {
      // Show a modal popup informing the user before forcing the logout/redirect.
      // The popup MUST be acknowledged (no barrier dismiss) — pressing OK signs
      // the user out and routes them to LoginScreen.
      await _showInactivityDialog();

      if (!mounted) return;
      await ref.read(authServiceProvider).signOut();

      // Force-navigate to LoginScreen, bypassing any PopScope / WillPopScope
      // guards (e.g. the order form's unsaved-changes prompt). Using
      // pushAndRemoveUntil with a (route) => false predicate pushes the new
      // route and REMOVES all previous routes — no popping is performed, so
      // PopScope cannot intercept and block the navigation.
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (_) {
      // Auth state stream drives navigation; swallow transient errors.
    } finally {
      _signingOut = false;
    }
  }

  Future<void> _showInactivityDialog() async {
    if (!mounted) return;
    final lang = Localizations.localeOf(context).languageCode;
    final title = switch (lang) {
      'he' => 'פג תוקף ההפעלה',
      'ar' => 'انتهت صلاحية الجلسة',
      _ => 'Session expired',
    };
    final body = switch (lang) {
      'he' => 'עקב חוסר פעילות, ההפעלה הסתיימה. עליך להתחבר מחדש כדי להמשיך.',
      'ar' =>
        'بسبب عدم النشاط، انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى للمتابعة.',
      _ =>
        'Due to inactivity, your session has ended. Please sign in again to continue.',
    };
    final okLabel = switch (lang) {
      'he' => 'אישור',
      'ar' => 'موافق',
      _ => 'OK',
    };

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: Icon(Icons.lock_clock, color: AppTheme.secondary, size: 32),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.assistant(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          content: Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.assistant(fontSize: 14),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                okLabel,
                style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onActivity([Object? _]) {
    if (_focusNode.hasFocus) {
      _resetTimer();
    }
  }

  void _onPointerEvent([Object? _]) => _resetTimer();

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) => _onActivity(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerEvent,
        onPointerMove: _onPointerEvent,
        onPointerSignal: _onPointerEvent,
        child: widget.child,
      ),
    );
  }
}
