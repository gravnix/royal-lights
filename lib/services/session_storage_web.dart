import 'package:web/web.dart';

final Storage _storage = window.sessionStorage;

bool sessionHasItem(String key) => _storage.getItem(key) != null;

String? sessionGetItem(String key) => _storage.getItem(key);

void sessionSetItem(String key, String value) {
  _storage.setItem(key, value);
}

void sessionRemoveItem(String key) {
  _storage.removeItem(key);
}
