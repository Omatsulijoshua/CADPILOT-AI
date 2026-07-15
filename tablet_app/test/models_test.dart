import 'package:cadpilot_tablet/src/ai_commands.dart';
import 'package:cadpilot_tablet/src/model_3d.dart';
import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/sketch_models.dart';
import 'package:cadpilot_tablet/src/spatial_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project serialization round-trips revision and sketch geometry', () {
    final now = DateTime.utc(2026, 7, 14);
    final project = CadProject(
      id: 'p1',
      name: 'Bracket',
      note: 'M6 holes',
      createdAt: now,
      updatedAt: now,
      revision: 3,
      syncState: SyncState.pending,
      model: ModelDocument(operations: [
        ModelOperation(
            id: 'extrude-1',
            kind: ModelOperationKind.extrude,
            profileId: 'rect-1',
            depth: 8,
            createdAt: now),
      ]),
      aiHistory: [
        AiCommandRecord(
            commandId: 'command-1',
            summary: 'Extrude base',
            status: AiCommandStatus.applied,
            createdAt: now),
      ],
      sketch: const SketchDocument(entities: [
        SketchEntity(
            id: 'line-1',
            kind: SketchEntityKind.line,
            start: Offset(5, 10),
            end: Offset(105, 10)),
      ]),
    );
    final decoded = CadProject.fromJson(project.toJson());
    expect(decoded.name, 'Bracket');
    expect(decoded.revision, 3);
    expect(decoded.note, 'M6 holes');
    expect(decoded.sketch.entities.single.id, 'line-1');
    expect(decoded.sketch.entities.single.end, const Offset(105, 10));
    expect(decoded.model.operations.single.id, 'extrude-1');
    expect(decoded.aiHistory.single.status, AiCommandStatus.applied);
  });
  test('project serialization persists AR screenshot records', () {
    final now = DateTime.utc(2026, 7, 15);
    final project = CadProject(
      id: 'p-capture',
      name: 'Placed cabinet',
      note: '',
      createdAt: now,
      updatedAt: now,
      revision: 1,
      syncState: SyncState.pending,
      arScreenshots: [
        ArScreenshot(
          path: '/captures/cabinet.png',
          widthPixels: 1920,
          heightPixels: 1080,
          capturedAt: now,
          sessionId: 'session-4',
          anchorId: 'anchor-9',
        ),
      ],
    );
    final decoded = CadProject.fromJson(project.toJson());
    expect(decoded.arScreenshots, hasLength(1));
    expect(decoded.arScreenshots.single.path, '/captures/cabinet.png');
    expect(decoded.arScreenshots.single.sessionId, 'session-4');
    expect(decoded.arScreenshots.single.capturedAt, now);
  });

  test('legacy projects load with an empty AR screenshot collection', () {
    final now = DateTime.utc(2026, 7, 15);
    final legacy = <String, Object?>{
      'id': 'legacy',
      'name': 'Legacy project',
      'note': '',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'revision': 1,
      'syncState': 'localOnly',
    };
    expect(CadProject.fromJson(legacy).arScreenshots, isEmpty);
  });
  test('cloud sync metadata persists without advancing local revision', () {
    final now = DateTime.utc(2026, 7, 15);
    final project = CadProject(
      id: 'sync-project',
      name: 'Synced part',
      note: '',
      createdAt: now,
      updatedAt: now,
      revision: 8,
      syncState: SyncState.pending,
    );
    final synced = project.markSynced(3);
    expect(synced.revision, 8);
    expect(synced.syncState, SyncState.synced);
    expect(synced.lastSyncedRevision, 3);
    final edited = synced.copyWith(note: 'Changed after backup');
    expect(edited.revision, 9);
    expect(edited.syncState, SyncState.pending);
    expect(edited.lastSyncedRevision, 3);
    expect(CadProject.fromJson(edited.toJson()).lastSyncedRevision, 3);
  });
}
