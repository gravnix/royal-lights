import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

class AuthService {
  final SupabaseClient _client;
  AuthService(this._client);

  User? get currentUser => _client.auth.currentUser;
  String get currentUsername =>
      _client.auth.currentUser?.userMetadata?['username'] as String? ??
      'unknown';

  /// Convert username to a synthetic email for Supabase Email Auth
  String _usernameToEmail(String username) {
    final cleaned = username.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    return '${cleaned.isEmpty ? "user" : cleaned}@royallight.store';
  }

  /// Sign in with username
  Future<AuthResponse> signIn(String usernameInput, String password) async {
    return await _client.auth
        .signInWithPassword(email: _usernameToEmail(usernameInput), password: password)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () =>
              throw Exception('Connection timeout. Check your internet.'),
        );
  }

  /// Sign up with username
  Future<AuthResponse> signUp(String username, String password) async {
    return await _client.auth
        .signUp(
          email: _usernameToEmail(username),
          password: password,
          data: {'username': username, 'full_name': username, 'phone': ''},
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () =>
              throw Exception('Connection timeout. Check your internet.'),
        );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  bool get isAuthenticated => _client.auth.currentSession != null;

  /// True if a session exists AND its JWT is not expired.
  bool get hasValidSession {
    final session = _client.auth.currentSession;
    return session != null && !session.isExpired;
  }

  /// True if a session exists but its JWT is expired.
  bool get isSessionExpired {
    final session = _client.auth.currentSession;
    return session != null && session.isExpired;
  }
}
