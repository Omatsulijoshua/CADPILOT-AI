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
  testWidgets('archives a cloud backup only after confirmation',
      (tester) async {
    var archived = false;
    final api = CloudApi(
      baseUrl: 'https://api.test/v1',
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/projects')) {
          return http.Response(
            jsonEncode(archived
                ? <Object?>[]
                : [
                    {
                      'id': 'cloud-project',
                      'name': 'Cloud bracket',
                      'revision': 2,
                      'updatedAt': '2026-07-15T00:00:00.000Z',
                    }
                  ]),
            200,
          );
        }
        if (request.method == 'DELETE' &&
            request.url.path.endsWith('/projects/cloud-project')) {
          expect(request.headers['authorization'], 'Bearer access-token');
          archived = true;
          return http.Response('{"success":true}', 200);
        }
        return http.Response('{}', 404);
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cloudApiProvider.overrideWithValue(api),
          localStoreProvider.overrideWithValue(_MemoryLocalStore()),
          tokenStoreProvider.overrideWithValue(
            _MemoryTokenStore()..accessToken = 'access-token',
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CloudProjectsPanel(
              session: const Session(
                kind: SessionKind.signedIn,
                displayName: 'Designer',
                email: 'designer@example.com',
              ),
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Archive cloud backup'));
    await tester.pumpAndSettle();
    expect(find.text('Archive cloud backup?'), findsOneWidget);
    expect(
      find.textContaining('local project on this device will not be deleted'),
      findsOneWidget,
    );

    await tester.tap(find.text('Archive backup'));
    await tester.pumpAndSettle();

    expect(archived, isTrue);
    expect(find.textContaining('Cloud backup archived'), findsOneWidget);
    expect(find.text('No cloud backups yet'), findsOneWidget);
  });
}

class _MemoryLocalStore implements LocalStore {
  @override
  Future<List<CadProject>> readProjects() async => const [];

  @override
  Future<Session?> readSession() async => null;

  @override
  Future<void> writeProjects(List<CadProject> value) async {}

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
