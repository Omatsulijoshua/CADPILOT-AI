import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStore {
  Future<void> write(
      {required String accessToken, required String refreshToken});
  Future<String?> readAccessToken();
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore();
  static const _storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  @override
  Future<void> write(
          {required String accessToken, required String refreshToken}) =>
      _storage.write(
          key: 'cadpilot.tokens', value: '$accessToken\n$refreshToken');
  @override
  Future<String?> readAccessToken() async =>
      (await _storage.read(key: 'cadpilot.tokens'))?.split('\n').first;
  @override
  Future<void> clear() => _storage.delete(key: 'cadpilot.tokens');
}
