import 'package:cadpilot_tablet/src/ai_commands.dart';
import 'package:cadpilot_tablet/src/model_3d.dart';
import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/sketch_models.dart';
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
}
