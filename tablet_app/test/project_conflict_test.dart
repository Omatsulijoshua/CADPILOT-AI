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
  testWidgets('cloud revision conflict preserves local edits', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final project = CadProject(
      id: 'project-conflict',
      name: 'Conflict bracket',
      note: 'Keep this local note',
      createdAt: DateTime.utc(2026, 7, 15),
      updatedAt: DateTime.utc(2026, 7, 15),
      revision: 2,
      syncState: SyncState.pending,
      lastSyncedRevision: 1,
    );
    final store = _MemoryLocalStore([project]);
    final api = CloudApi(
      baseUrl: 'https://api.test/v1',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/projects/project-conflict/sync');
        return http.Response(jsonEncode({'error': 'conflict'}), 409);
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          tokenStoreProvider.overrideWithValue(
            _MemoryTokenStore()..accessToken = 'access-token',
          ),
          cloudApiProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(
          home: ProjectWorkspace(projectId: 'project-conflict'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();

    expect(find.text('Cloud changes detected'), findsOneWidget);
    expect(find.textContaining('local edits have not been changed'),
        findsOneWidget);
    expect(store.projects.single.note, 'Keep this local note');
    await tester.tap(find.text('Keep local edits'));
    await tester.pumpAndSettle();
    expect(find.text('Cloud changes detected'), findsNothing);
  });
}

class _MemoryLocalStore implements LocalStore {
  _MemoryLocalStore(this.projects);

  List<CadProject> projects;

  @override
  Future<List<CadProject>> readProjects() async => projects;

  @override
  Future<Session?> readSession() async => null;

  @override
  Future<void> writeProjects(List<CadProject> value) async => projects = value;

  @override
  Future<void> writeSession(Session? value) async {}
}

class _MemoryTokenStore implements TokenStore {
  String? accessToken;

  @override
  Future<void> clear() async => accessToken = null;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
  }
}
