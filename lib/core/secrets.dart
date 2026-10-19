import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials (LLM API keys, email app passwords, OAuth tokens) live in the
/// platform keystore, never in SharedPreferences or the database.
class SecretStore {
  SecretStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String? value) =>
      value == null || value.isEmpty ? _storage.delete(key: key) : _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);
}
