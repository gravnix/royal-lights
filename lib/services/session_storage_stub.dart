// Non-web stub. Session storage is a web-only concept; on native platforms
// fall back to simple in-memory storage so the app still runs.
final Map<String, String> _memory = {};

bool sessionHasItem(String key) => _memory.containsKey(key);

String? sessionGetItem(String key) => _memory[key];

void sessionSetItem(String key, String value) {
  _memory[key] = value;
}

void sessionRemoveItem(String key) {
  _memory.remove(key);
}
