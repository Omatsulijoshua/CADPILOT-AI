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
  test('project backup sends unique mutation and remote base revision',
      () async {
    final project = CadProject(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'Bracket',
      note: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      revision: 7,
      syncState: SyncState.pending,
      lastSyncedRevision: 3,
    );
    final client = MockClient((request) async {
      expect(request.url.path,
          '/v1/projects/11111111-1111-4111-8111-111111111111/sync');
      expect(request.headers['authorization'], 'Bearer access');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['mutationId'], '22222222-2222-4222-8222-222222222222');
      expect(body['baseRevision'], 3);
      expect((body['payload'] as Map<String, Object?>)['revision'], 7);
      return http.Response(
        jsonEncode({
          'mutationId': body['mutationId'],
          'appliedRevision': 4,
        }),
        201,
      );
    });
    final result = await CloudApi(
      client: client,
      baseUrl: 'https://api.test/v1',
    ).pushProject(
      project,
      'access',
      mutationId: '22222222-2222-4222-8222-222222222222',
    );
    expect(result.appliedRevision, 4);
  });

  test('first project backup uses remote revision zero', () async {
    final project = CadProject(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'First backup',
      note: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      revision: 9,
      syncState: SyncState.pending,
    );
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['baseRevision'], 0);
      return http.Response(
        jsonEncode({'mutationId': body['mutationId'], 'appliedRevision': 1}),
        201,
      );
    });
    final result = await CloudApi(
      client: client,
      baseUrl: 'https://api.test/v1',
    ).pushProject(project, 'access');
    expect(result.appliedRevision, 1);
  });

  test('invalid project sync response fails closed', () async {
    final project = CadProject(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'Part',
      note: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      revision: 1,
      syncState: SyncState.pending,
    );
    final client = MockClient((_) async => http.Response('{}', 201));
    expect(
      () => CloudApi(client: client, baseUrl: 'https://api.test/v1')
          .pushProject(project, 'access'),
      throwsA(isA<CloudApiException>()),
    );
  });
  test('same local state produces a retry-safe mutation ID', () async {
    final project = CadProject(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'Retry-safe part',
      note: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      revision: 4,
      syncState: SyncState.pending,
      lastSyncedRevision: 2,
    );
    final mutationIds = <String>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      mutationIds.add(body['mutationId']! as String);
      return http.Response(
        jsonEncode({'mutationId': body['mutationId'], 'appliedRevision': 3}),
        201,
      );
    });
    final api = CloudApi(client: client, baseUrl: 'https://api.test/v1');
    await api.pushProject(project, 'access');
    await api.pushProject(project, 'access');
    await api.pushProject(project.copyWith(note: 'New edit'), 'access');

    expect(mutationIds[0], mutationIds[1]);
    expect(mutationIds[2], isNot(mutationIds[0]));
  });
  test('cloud restore validates and marks the downloaded revision', () async {
    final now = DateTime.utc(2026, 7, 15);
    final remote = CadProject(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'Cloud bracket',
      note: 'Remote copy',
      createdAt: now,
      updatedAt: now,
      revision: 9,
      syncState: SyncState.pending,
    );
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path,
          '/v1/projects/11111111-1111-4111-8111-111111111111');
      expect(request.headers['authorization'], 'Bearer access');
      return http.Response(
        jsonEncode({'revision': 4, 'manifest': remote.toJson()}),
        200,
      );
    });
    final restored = await CloudApi(
      client: client,
      baseUrl: 'https://api.test/v1',
    ).pullProject(remote.id, 'access');
    expect(restored.note, 'Remote copy');
    expect(restored.revision, 9);
    expect(restored.lastSyncedRevision, 4);
    expect(restored.syncState, SyncState.synced);
  });

  test('cloud restore reports a missing backup safely', () async {
    final client = MockClient((_) async => http.Response('{}', 404));
    expect(
      () => CloudApi(client: client, baseUrl: 'https://api.test/v1')
          .pullProject('missing-project', 'access'),
      throwsA(isA<CloudApiException>().having(
        (error) => error.statusCode,
        'statusCode',
        404,
      )),
    );
  });

  test('cloud restore rejects a mismatched project identity', () async {
    final now = DateTime.utc(2026, 7, 15);
    final remote = CadProject(
      id: 'different-project',
      name: 'Wrong project',
      note: '',
      createdAt: now,
      updatedAt: now,
      revision: 1,
      syncState: SyncState.synced,
    );
    final client = MockClient((_) async => http.Response(
          jsonEncode({'revision': 2, 'manifest': remote.toJson()}),
          200,
        ));
    expect(
      () => CloudApi(client: client, baseUrl: 'https://api.test/v1')
          .pullProject('expected-project', 'access'),
      throwsA(isA<CloudApiException>()),
    );
  });
}
