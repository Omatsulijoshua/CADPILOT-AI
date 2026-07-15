import 'dart:convert';

import 'package:cadpilot_tablet/src/cloud_api.dart';
import 'package:cadpilot_tablet/src/controllers.dart';
import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/storage.dart';
import 'package:cadpilot_tablet/src/token_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const signedIn = Session(
    kind: SessionKind.signedIn,
    displayName: 'Original Designer',
    email: 'designer@example.com',
  );

  test('startup rotates tokens and refreshes the stored identity', () async {
    final store = _MemoryLocalStore(signedIn);
    final tokens = _MemoryTokenStore(refreshToken: 'old-refresh');
    final api = CloudApi(
      baseUrl: 'https://api.test/v1',
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'user': {
                'email': 'designer@example.com',
                'displayName': 'Updated Designer',
              },
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
            }),
            201,
          )),
    );
    final container = _container(store, tokens, api);
    addTearDown(container.dispose);

    final session = await container.read(sessionProvider.future);

    expect(session?.displayName, 'Updated Designer');
    expect(store.session?.displayName, 'Updated Designer');
    expect(tokens.accessToken, 'new-access');
    expect(tokens.refreshToken, 'new-refresh');
  });

  test('confirmed invalid refresh clears the local session', () async {
    final store = _MemoryLocalStore(signedIn);
    final tokens = _MemoryTokenStore(refreshToken: 'expired-refresh');
    final api = CloudApi(
      baseUrl: 'https://api.test/v1',
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    final container = _container(store, tokens, api);
    addTearDown(container.dispose);

    expect(await container.read(sessionProvider.future), isNull);
    expect(store.session, isNull);
    expect(tokens.wasCleared, isTrue);
  });

  test('temporary refresh failure preserves the signed-in session', () async {
    final store = _MemoryLocalStore(signedIn);
    final tokens = _MemoryTokenStore(refreshToken: 'active-refresh');
    final api = CloudApi(
      baseUrl: 'https://api.test/v1',
      client: MockClient((_) async => throw Exception('offline')),
    );
    final container = _container(store, tokens, api);
    addTearDown(container.dispose);

    final session = await container.read(sessionProvider.future);

    expect(session?.displayName, 'Original Designer');
    expect(store.session, isNotNull);
    expect(tokens.wasCleared, isFalse);
  });

  test('sign-out clears local state even when server revocation fails',
      () async {
    final store = _MemoryLocalStore(signedIn);
    final tokens = _MemoryTokenStore(refreshToken: 'active-refresh');
    final api = CloudApi(
      baseUrl: 'https://api.test/v1',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          return http.Response(
            jsonEncode({
              'user': {
                'email': 'designer@example.com',
                'displayName': 'Original Designer',
              },
              'accessToken': 'rotated-access',
              'refreshToken': 'rotated-refresh',
            }),
            201,
          );
        }
        return http.Response('{}', 503);
      }),
    );
    final container = _container(store, tokens, api);
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);

    await container.read(sessionProvider.notifier).signOut();

    expect(container.read(sessionProvider).value, isNull);
    expect(store.session, isNull);
    expect(tokens.wasCleared, isTrue);
  });
  test('archives the remote cloud copy with a verified token', () async {
    final tokens = _MemoryTokenStore()..accessToken = 'access';
    final api = CloudApi(
        baseUrl: 'https://api.test/v1',
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.headers['authorization'], 'Bearer access');
          return http.Response('{"success":true}', 200);
        }));
    final container = _container(_MemoryLocalStore(signedIn), tokens, api);
    addTearDown(container.dispose);
    container.read(cloudSessionStatusProvider.notifier).state =
        CloudSessionStatus.verified;
    await container.read(projectsProvider.future);
    await expectLater(
        container
            .read(projectsProvider.notifier)
            .archiveCloudCopy('cloud-project'),
        completes);
  });
}

ProviderContainer _container(
  LocalStore store,
  TokenStore tokens,
  CloudApi api,
) =>
    ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      tokenStoreProvider.overrideWithValue(tokens),
      cloudApiProvider.overrideWithValue(api),
    ]);

class _MemoryLocalStore implements LocalStore {
  _MemoryLocalStore(this.session);

  Session? session;
  List<CadProject> projects = [];

  @override
  Future<Session?> readSession() async => session;

  @override
  Future<void> writeSession(Session? value) async => session = value;

  @override
  Future<List<CadProject>> readProjects() async => projects;

  @override
  Future<void> writeProjects(List<CadProject> value) async => projects = value;
}

class _MemoryTokenStore implements TokenStore {
  _MemoryTokenStore({this.refreshToken});

  String? accessToken;
  String? refreshToken;
  bool wasCleared = false;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    wasCleared = true;
  }
}
