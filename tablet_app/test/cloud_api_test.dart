import 'dart:convert';
import 'package:cadpilot_tablet/src/cloud_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('login converts server credentials into a signed-in session', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/auth/login');
      return http.Response(
          jsonEncode({
            'user': {
              'id': 'u1',
              'email': 'designer@example.com',
              'displayName': 'Designer'
            },
            'accessToken': 'access',
            'refreshToken': 'refresh'
          }),
          201,
          headers: {'content-type': 'application/json'});
    });
    final result =
        await CloudApi(client: client, baseUrl: 'https://api.test/v1')
            .login('designer@example.com', 'password123');
    expect(result.session.displayName, 'Designer');
    expect(result.accessToken, 'access');
  });

  test('login surfaces a safe error when authentication fails', () async {
    final client = MockClient((_) async => http.Response('{}', 401));
    expect(
        () => CloudApi(client: client, baseUrl: 'https://api.test/v1')
            .login('designer@example.com', 'wrongpass'),
        throwsA(isA<CloudApiException>()));
  });
}
