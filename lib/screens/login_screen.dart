import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../providers/providers.dart';
import '../widgets/brand_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Maps Supabase / GoTrue auth errors to short Hebrew copy (no exception dumps).
  String _friendlyAuthMessage(AuthException e) {
    final code = e.code ?? '';
    switch (code) {
      case 'invalid_credentials':
      case 'invalid_grant':
      case 'user_not_found':
        return 'שם המשתמש או הסיסמה שגויים. בדקו ונסו שוב.';
      case 'email_not_confirmed':
      case 'phone_not_confirmed':
        return 'יש לאשר את כתובת האימייל או הטלפון לפני ההתחברות.';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
      case 'over_sms_send_rate_limit':
        return 'יותר מדי ניסיונות התחברות. המתינו רגע ונסו שוב.';
      case 'user_banned':
        return 'החשבון חסום. לעזרה פנו לתמיכה.';
      case 'email_provider_disabled':
      case 'signup_disabled':
        return 'ההתחברות אינה זמינה כרגע. פנו למנהל המערכת.';
      default:
        final msg = e.message.toLowerCase();
        if (msg.contains('invalid login') ||
            msg.contains('invalid credentials')) {
          return 'שם המשתמש או הסיסמה שגויים. בדקו ונסו שוב.';
        }
        return 'לא הצלחנו להתחבר. נסו שוב בעוד רגע.';
    }
  }

  String _friendlyGenericMessage(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('timeout')) {
      return 'פג הזמן להתחברות. בדקו את החיבור לאינטרנט.';
    }
    return 'אירעה שגיאה. נסו שוב.';
  }

  Future<void> _handleSubmit() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      setState(() => _error = 'אנא מלא/י את כל השדות');
      return;
    }

    if (_passwordController.text.trim().length < 6) {
      setState(() => _error = 'הסיסמה חייבת להכיל לפחות 6 תווים');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signIn(
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );
    } on AuthException catch (e) {
      setState(() => _error = _friendlyAuthMessage(e));
    } catch (e) {
      setState(() => _error = _friendlyGenericMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: Stack(
          children: [
            // Subtle background glow
            Positioned(
              top: size.height * 0.15,
              left: size.width * 0.5 - 160,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.secondaryContainer.withValues(alpha: 0.15),
                      blurRadius: 120,
                      spreadRadius: 40,
                    ),
                  ],
                ),
              ),
            ),

            // Main content
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo
                        DecoratedBox(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.secondaryContainer.withValues(alpha: 0.22),
                                blurRadius: 38,
                                spreadRadius: 6,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const BrandLogo(
                            width: 180,
                            height: 180,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Login card
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: AppTheme.outlineVariant.withValues(alpha: 0.15),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color.fromRGBO(26, 28, 28, 0.06),
                                blurRadius: 40,
                                offset: Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'ברוכים הבאים',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.assistant(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'התחברו למערכת הניהול',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.assistant(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 28),

                              // Error
                              if (_error != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    color: AppTheme.error.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: AppTheme.error.withValues(alpha: 0.2),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.error.withValues(alpha: 0.06),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Icon(
                                          Icons.info_outline_rounded,
                                          color: AppTheme.error.withValues(alpha: 0.9),
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: GoogleFonts.assistant(
                                            color: AppTheme.onSurface.withValues(alpha: 0.88),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // Username
                              _buildLabel('שם משתמש'),
                              const SizedBox(height: 6),
                              _buildField(
                                controller: _usernameController,
                                icon: Icons.person_outline,
                                hint: 'הזינו שם משתמש',
                              ),
                              const SizedBox(height: 20),

                              // Password
                              _buildLabel('סיסמה'),
                              const SizedBox(height: 6),
                              _buildField(
                                controller: _passwordController,
                                icon: Icons.lock_outline,
                                hint: '••••••••',
                                isPassword: true,
                              ),
                              const SizedBox(height: 28),

                              // Connect button
                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleSubmit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: AppTheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  elevation: 0,
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.resolveWith(
                                    (states) => states.contains(WidgetState.hovered) ||
                                            states.contains(WidgetState.pressed)
                                        ? AppTheme.secondary.withValues(alpha: 0.9)
                                        : null,
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'התחברות',
                                        style: GoogleFonts.assistant(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),
                        // Footer
                        Text(
                          '© 2024 Royal Light Store',
                          style: GoogleFonts.assistant(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.0,
                            color: AppTheme.outline.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Text(
        text,
        style: GoogleFonts.assistant(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isPassword = false,
  }) {
    const radius = 18.0;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: AppTheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: TextField(
          controller: controller,
          obscureText: isPassword,
          style: GoogleFonts.assistant(color: AppTheme.onSurface, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.outline.withValues(alpha: 0.4)),
            prefixIcon: Icon(icon, color: AppTheme.outline, size: 20),
            filled: true,
            fillColor: Colors.transparent,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radius),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radius),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radius),
              borderSide: const BorderSide(color: AppTheme.secondary, width: 1.8),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }
}
