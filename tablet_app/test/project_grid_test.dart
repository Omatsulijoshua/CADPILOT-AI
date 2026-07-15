import 'package:cadpilot_tablet/src/app.dart';
import 'package:cadpilot_tablet/src/controllers.dart';
import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('local project deletion requires confirmation', (tester) async {
    final store = _MemoryLocalStore([
      CadProject(
        id: 'local-project',
        name: 'Local bracket',
        note: '',
        createdAt: DateTime.utc(2026, 7, 15),
        updatedAt: DateTime.utc(2026, 7, 15),
        revision: 1,
        syncState: SyncState.localOnly,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(body: ProjectGrid(onOpen: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete local project'));
    await tester.pumpAndSettle();
    expect(find.text('Delete local project?'), findsOneWidget);
    expect(find.textContaining('cannot be recovered'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Local bracket'), findsOneWidget);
    expect(store.projects, hasLength(1));

    await tester.tap(find.byTooltip('Delete local project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete local project'));
    await tester.pumpAndSettle();

    expect(store.projects, isEmpty);
    expect(find.text('No projects yet. Create one to begin.'), findsOneWidget);
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
