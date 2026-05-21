import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'services/session_local_storage.dart';
import 'config/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/providers.dart';
import 'screens/login_screen.dart';
import 'widgets/app_shell.dart';
import 'widgets/inactivity_logout_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: SessionLocalStorage(),
      autoRefreshToken: true,
    ),
  );
  runApp(const ProviderScope(child: RoyalLightApp()));
}

class RoyalLightApp extends ConsumerWidget {
  const RoyalLightApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'Royal Light Tira',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: locale,
      supportedLocales: const [Locale('he'), Locale('ar'), Locale('en')],
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, child) {
        final isRtl =
            locale.languageCode == 'he' || locale.languageCode == 'ar';
        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        );
      },
      home: authState.when(
        data: (state) {
          final session = state.session;
          if (session != null && !session.isExpired) {
            return const InactivityLogoutWrapper(child: AppShell());
          }
          return const LoginScreen();
        },
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => const LoginScreen(),
      ),
    );
  }
}
