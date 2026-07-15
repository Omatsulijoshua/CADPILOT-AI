import 'package:cadpilot_tablet/src/ai_commands.dart';
import 'package:cadpilot_tablet/src/model_3d.dart';
import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/sketch_models.dart';
import 'package:cadpilot_tablet/src/spatial_capture.dart';
import 'package:cadpilot_tablet/src/spatial_models.dart';
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

  test('project serialization persists advisory scan records', () {
    final now = DateTime.utc(2026, 7, 15);
    final project = CadProject(
      id: 'scan-project',
      name: 'Measured cabinet',
      note: '',
      createdAt: now,
      updatedAt: now,
      revision: 1,
      syncState: SyncState.pending,
      spatialScans: [
        SpatialScanRecord(
            id: 'scan-1',
            sessionId: 'session-1',
            capturedAt: now,
            frameCount: 3,
            pointCount: 1024,
            widthMm: 450,
            heightMm: 700,
            depthMm: 350,
            meanConfidence: .8,
            resolutionMm: 10),
      ],
    );
    final decoded = CadProject.fromJson(project.toJson());
    expect(decoded.spatialScans.single.pointCount, 1024);
    expect(decoded.spatialScans.single.widthMm, 450);
  });

  test('spatial collection updates can preserve placements and scan records',
      () {
    final now = DateTime.utc(2026, 7, 15);
    final placement = SpatialPlacement(
      id: 'placement-1',
      name: 'Wall',
      createdAt: now,
      source: 'manual',
      plane: 'wall',
      widthMm: 100,
      heightMm: 100,
      depthMm: 100,
      offsetXMm: 0,
      offsetYMm: 0,
      offsetZMm: 0,
      rotationDegrees: 0,
    );
    final scan = SpatialScanRecord(
      id: 'scan-1',
      sessionId: 'session-1',
      capturedAt: now,
      frameCount: 3,
      pointCount: 20,
      widthMm: 100,
      heightMm: 200,
      depthMm: 300,
      meanConfidence: .8,
      resolutionMm: 10,
    );
    final project = CadProject(
      id: 'spatial',
      name: 'Spatial',
      note: '',
      createdAt: now,
      updatedAt: now,
      revision: 1,
      syncState: SyncState.pending,
      spatialPlacements: [placement],
    );
    final merged = project.copyWith(
      spatialPlacements: project.spatialPlacements,
      spatialScans: [scan],
    );
    expect(merged.spatialPlacements.single.id, placement.id);
    expect(merged.spatialScans.single.id, scan.id);
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
