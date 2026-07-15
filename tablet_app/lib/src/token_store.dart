import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStore {
  Future<void> write(
      {required String accessToken, required String refreshToken});
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
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
  Future<List<String>> _readTokens() async =>
      (await _storage.read(key: 'cadpilot.tokens'))?.split('\n') ?? const [];

  @override
  Future<String?> readAccessToken() async {
    final tokens = await _readTokens();
    return tokens.isNotEmpty && tokens.first.isNotEmpty ? tokens.first : null;
  }

  @override
  Future<String?> readRefreshToken() async {
    final tokens = await _readTokens();
    return tokens.length > 1 && tokens[1].isNotEmpty ? tokens[1] : null;
  }

  @override
  Future<void> clear() => _storage.delete(key: 'cadpilot.tokens');
}
