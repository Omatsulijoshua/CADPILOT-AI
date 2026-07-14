import 'dart:convert';
import 'package:cadpilot_tablet/src/cloud_api.dart';
import 'package:cadpilot_tablet/src/models.dart';
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

  test('AI command generation sends auth context and reports usage', () async {
    final now = DateTime.utc(2026);
    final project = CadProject(
        id: 'p1',
        name: 'Part',
        note: '',
        createdAt: now,
        updatedAt: now,
        revision: 1,
        syncState: SyncState.pending);
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/ai/commands');
      expect(request.headers['authorization'], 'Bearer access');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['prompt'], 'Extrude the base');
      expect(body['context'], isA<Map>());
      return http.Response(
          jsonEncode({
            'command': {'schemaVersion': 1, 'commandId': 'c1'},
            'usage': {'inputTokens': 10, 'outputTokens': 6, 'totalTokens': 16}
          }),
          201);
    });
    final result =
        await CloudApi(client: client, baseUrl: 'https://api.test/v1')
            .generateAiCommand(
                prompt: 'Extrude the base', project: project, token: 'access');
    expect(result.command['commandId'], 'c1');
    expect(result.totalTokens, 16);
  });
}
