import 'package:cadpilot_tablet/src/app.dart';
import 'package:cadpilot_tablet/src/controllers.dart';
import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renames a project and marks it pending for cloud backup',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final project = CadProject(
      id: 'rename-project',
      name: 'Original bracket',
      note: '',
      createdAt: DateTime.utc(2026, 7, 15),
      updatedAt: DateTime.utc(2026, 7, 15),
      revision: 3,
      syncState: SyncState.synced,
      lastSyncedRevision: 2,
    );
    final store = _MemoryLocalStore([project]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          home: ProjectWorkspace(projectId: 'rename-project'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rename project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      '  Final bracket  ',
    );
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();

    expect(store.projects.single.name, 'Final bracket');
    expect(store.projects.single.revision, 4);
    expect(store.projects.single.syncState, SyncState.pending);
    expect(store.projects.single.lastSyncedRevision, 2);
    expect(find.text('Final bracket'), findsOneWidget);
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
