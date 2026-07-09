import 'secrets.dart';

class SupabaseConfig {
  // ⚡ This will default to false locally, but Vercel can set it to true!
  static const bool isProduction =
      bool.fromEnvironment('IS_PROD', defaultValue: false);
  static String get supabaseUrl =>
      isProduction ? Secrets.prodSupabaseUrl : Secrets.testSupabaseUrl;
  static String get supabaseAnonKey =>
      isProduction ? Secrets.prodSupabaseKey : Secrets.testSupabaseKey;
}
