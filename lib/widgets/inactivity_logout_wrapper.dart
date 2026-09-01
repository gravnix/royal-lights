import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../providers/providers.dart';
import '../screens/login_screen.dart';

/// Signs the user out after a fixed period of input inactivity.
/// Resets the timer on any pointer interaction, keyboard input, or focus change.
class InactivityLogoutWrapper extends ConsumerStatefulWidget {
  static const Duration timeout = Duration(minutes: 60);

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
    if (_signingOut) return;
    _timer = Timer(InactivityLogoutWrapper.timeout, _handleTimeout);
  }

  Future<void> _handleTimeout() async {
    if (_signingOut || !mounted) return;
    _signingOut = true;
    _timer?.cancel();

    try {
      final confirmed = await _showInactivityDialog();
      if (!confirmed || !mounted) return;

      // Navigate FIRST while this State is still mounted. Signing out first
      // rebuilds MaterialApp.home and can dispose this widget before we clear
      // nested routes (order form, customer detail, …), leaving the user stuck
      // on the previous screen.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );

      await _signOutLocally();
    } catch (_) {
      // Still try to clear the session if navigation somehow failed.
      await _signOutLocally();
    } finally {
      _signingOut = false;
    }
  }

  /// Clear the local session even if the network is down, so authStateProvider
  /// flips to logged-out and main.dart keeps showing LoginScreen.
  Future<void> _signOutLocally() async {
    try {
      await ref
          .read(authServiceProvider)
          .signOut()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        await Supabase.instance.client.auth.signOut(
          scope: SignOutScope.local,
        );
      } catch (_) {}
    }
  }

  /// Returns `true` when the user taps OK.
  Future<bool> _showInactivityDialog() async {
    if (!mounted) return false;
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

    final result = await showDialog<bool>(
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
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
              child: Text(
                okLabel,
                style: GoogleFonts.assistant(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );

    return result == true;
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
