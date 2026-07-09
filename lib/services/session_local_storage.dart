import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_storage_stub.dart'
    if (dart.library.js_interop) 'session_storage_web.dart';

/// Persists the Supabase auth session in the browser's `sessionStorage`
/// (per-tab) instead of `localStorage` (shared across tabs). This lets two
/// users sign in independently in two tabs of the same browser.
///
/// On non-web platforms it falls back to a simple in-memory map, so the
/// session is lost on app restart — acceptable since the multi-user issue
/// only exists on the web build.
class SessionLocalStorage extends LocalStorage {
  const SessionLocalStorage({this.persistSessionKey = 'supabase.auth.token'});

  final String persistSessionKey;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => sessionHasItem(persistSessionKey);

  @override
  Future<String?> accessToken() async => sessionGetItem(persistSessionKey);

  @override
  Future<void> removePersistedSession() async {
    sessionRemoveItem(persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    sessionSetItem(persistSessionKey, persistSessionString);
  }
}
