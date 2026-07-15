import 'package:cadpilot_tablet/src/app.dart';
import 'package:cadpilot_tablet/src/controllers.dart';
import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('filters projects by name and shows an empty search state',
      (tester) async {
    final now = DateTime.utc(2026, 7, 15);
    final store = _MemoryLocalStore([
      CadProject(
        id: 'bracket',
        name: 'Mounting bracket',
        note: '',
        createdAt: now,
        updatedAt: now.subtract(const Duration(days: 1)),
        revision: 1,
        syncState: SyncState.localOnly,
      ),
      CadProject(
        id: 'cabinet',
        name: 'Kitchen cabinet',
        note: '',
        createdAt: now,
        updatedAt: now,
        revision: 1,
        syncState: SyncState.localOnly,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(body: ProjectGrid(onOpen: (_) {}, query: 'cabinet')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kitchen cabinet'), findsOneWidget);
    expect(find.text('Mounting bracket'), findsNothing);
    expect(find.byTooltip('Back up project'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(body: ProjectGrid(onOpen: (_) {}, query: 'missing')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No projects match your search.'), findsOneWidget);
  });
  testWidgets('duplicates a project as an independent local draft',
      (tester) async {
    final now = DateTime.utc(2026, 7, 15);
    final source = CadProject(
      id: 'source-project',
      name: 'Original bracket',
      note: 'M6 holes',
      createdAt: now,
      updatedAt: now,
      revision: 4,
      syncState: SyncState.synced,
      lastSyncedRevision: 3,
    );
    final store = _MemoryLocalStore([source]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(body: ProjectGrid(onOpen: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Duplicate project'));
    await tester.pumpAndSettle();

    expect(store.projects, hasLength(2));
    final duplicate = store.projects.first;
    expect(duplicate.id, isNot(source.id));
    expect(duplicate.name, 'Original bracket copy');
    expect(duplicate.note, source.note);
    expect(duplicate.revision, 1);
    expect(duplicate.syncState, SyncState.localOnly);
    expect(duplicate.lastSyncedRevision, isNull);
    expect(
        find.textContaining('Created Original bracket copy'), findsOneWidget);

    await tester.tap(find.byTooltip('Duplicate project').last);
    await tester.pumpAndSettle();
    expect(store.projects, hasLength(3));
    expect(store.projects.first.name, 'Original bracket copy 2');
  });
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
