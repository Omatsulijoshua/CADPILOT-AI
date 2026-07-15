import 'dart:convert';

import 'package:cadpilot_tablet/src/app.dart';
import 'package:cadpilot_tablet/src/cloud_api.dart';
import 'package:cadpilot_tablet/src/controllers.dart';
import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/storage.dart';
import 'package:cadpilot_tablet/src/token_store.dart';
import 'package:flutter/material.dart';
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

  test('temporary startup failure exposes offline verification state',
      () async {
    final store = _MemoryLocalStore(signedIn);
    final tokens = _MemoryTokenStore(refreshToken: 'active-refresh');
    final container = _container(
      store,
      tokens,
      CloudApi(
        baseUrl: 'https://api.test/v1',
        client: MockClient((_) async => throw Exception('offline')),
      ),
    );
    addTearDown(container.dispose);

    expect((await container.read(sessionProvider.future))?.kind,
        SessionKind.signedIn);
    expect(
        container.read(cloudSessionStatusProvider), CloudSessionStatus.offline);
  });

  test('offline session retries and rotates into verified state', () async {
    final store = _MemoryLocalStore(signedIn);
    final tokens = _MemoryTokenStore(refreshToken: 'active-refresh');
    var attempts = 0;
    final container = _container(
      store,
      tokens,
      CloudApi(
        baseUrl: 'https://api.test/v1',
        client: MockClient((_) async {
          attempts++;
          if (attempts == 1) throw Exception('offline');
          return http.Response(
            jsonEncode({
              'user': {
                'email': 'designer@example.com',
                'displayName': 'Verified Designer',
              },
              'accessToken': 'verified-access',
              'refreshToken': 'verified-refresh',
            }),
            201,
          );
        }),
      ),
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);

    expect(
      await container.read(sessionProvider.notifier).retryCloudVerification(),
      isTrue,
    );
    expect(container.read(cloudSessionStatusProvider),
        CloudSessionStatus.verified);
    expect(container.read(sessionProvider).value?.displayName,
        'Verified Designer');
    expect(tokens.accessToken, 'verified-access');
  });

  test('offline verification blocks stale-token project backup', () async {
    final now = DateTime.utc(2026, 7, 15);
    final project = CadProject(
      id: 'project-offline',
      name: 'Offline bracket',
      note: '',
      createdAt: now,
      updatedAt: now,
      revision: 1,
      syncState: SyncState.pending,
    );
    final store = _MemoryLocalStore(signedIn)..projects = [project];
    final tokens = _MemoryTokenStore(refreshToken: 'active-refresh')
      ..accessToken = 'stale-access';
    final container = _container(
      store,
      tokens,
      CloudApi(
        baseUrl: 'https://api.test/v1',
        client: MockClient((_) async => throw Exception('offline')),
      ),
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);
    await container.read(projectsProvider.future);

    expect(
      () => container.read(projectsProvider.notifier).sync(project),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('Reconnect and verify'),
      )),
    );
  });

  testWidgets('offline banner explains local continuity and retries',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudSessionBanner(
            onRetry: () async {
              retries++;
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Working offline'), findsOneWidget);
    expect(
        find.textContaining('Local projects remain available'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
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
  }
}
