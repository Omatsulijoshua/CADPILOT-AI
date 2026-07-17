import 'package:cadpilot_tablet/src/ai_commands.dart';
import 'package:cadpilot_tablet/src/model_3d.dart';
import 'package:cadpilot_tablet/src/sketch_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rectangle = SketchEntity(
      id: 'base',
      kind: SketchEntityKind.rectangle,
      start: Offset.zero,
      end: Offset(100, 50));
  const circle = SketchEntity(
      id: 'hole',
      kind: SketchEntityKind.circle,
      start: Offset(50, 25),
      end: Offset(55, 25));
  const sketch = SketchDocument(entities: [rectangle, circle]);

  Map<String, Object?> command(List<Map<String, Object?>> operations) => {
        'schemaVersion': 1,
        'commandId': 'command-1',
        'intent': 'modify_model',
        'target': {'type': 'model', 'ids': <String>[]},
        'operations': operations,
        'assumptions': <String>['Dimensions are millimetres.'],
        'requiresConfirmation': true,
      };

  test('valid command previews an atomic extrude and cut transaction', () {
    final parsed = AiCadCommand.fromJson(command([
      {
        'operationId': 'extrude-1',
        'type': 'extrude',
        'parameters': {'profileId': 'base', 'depth': 8}
      },
      {
        'operationId': 'cut-1',
        'type': 'cut',
        'parameters': {'profileId': 'hole', 'depth': 8}
      },
    ]));
    final preview =
        const AiCommandEngine().preview(parsed, sketch, const ModelDocument());
    expect(preview.model.operations, hasLength(2));
    expect(const ModelEvaluator().evaluate(sketch, preview.model)!.cuts,
        hasLength(1));
    expect(preview.summary, contains('Extrude base'));
  });

  test('full revolve produces an editable revolved operation', () {
    final parsed = AiCadCommand.fromJson(command([
      {
        'operationId': 'revolve-1',
        'type': 'revolve',
        'parameters': {'profileId': 'base', 'angle': 360}
      },
    ]));
    final preview =
        const AiCommandEngine().preview(parsed, sketch, const ModelDocument());
    expect(preview.model.operations.single.kind, ModelOperationKind.revolve);
    expect(preview.summary, contains('360 degrees'));
  });

  test('AI can create a toothed gear from a circular profile', () {
    final parsed = AiCadCommand.fromJson(command([
      {
        'operationId': 'gear-1',
        'type': 'gear',
        'parameters': {
          'profileId': 'hole',
          'depth': 6,
          'teeth': 18,
          'boreRadius': 2
        }
      },
    ]));
    final preview =
        const AiCommandEngine().preview(parsed, sketch, const ModelDocument());
    expect(preview.model.operations.single.kind, ModelOperationKind.gear);
    expect(preview.model.operations.single.instanceCount, 18);
    expect(preview.summary, contains('18-tooth gear'));
    final solid = const ModelEvaluator().evaluate(sketch, preview.model)!;
    expect(solid.gearTeeth, 18);
    expect(solid.cuts.single.radius, 2);
  });

  test('partial AI revolve is rejected before mutation', () {
    final parsed = AiCadCommand.fromJson(command([
      {
        'operationId': 'revolve-1',
        'type': 'revolve',
        'parameters': {'profileId': 'base', 'angle': 180}
      },
    ]));
    expect(
        () => const AiCommandEngine()
            .preview(parsed, sketch, const ModelDocument()),
        throwsFormatException);
  });

  test('AI can shell an extrusion only with safe wall thickness', () {
    final parsed = AiCadCommand.fromJson(command([
      {
        'operationId': 'extrude-1',
        'type': 'extrude',
        'parameters': {'profileId': 'base', 'depth': 20}
      },
      {
        'operationId': 'shell-1',
        'type': 'shell',
        'parameters': {'thickness': 2}
      },
    ]));
    final preview =
        const AiCommandEngine().preview(parsed, sketch, const ModelDocument());
    expect(preview.model.operations.last.kind, ModelOperationKind.shell);
    expect(
        const ModelEvaluator().evaluate(sketch, preview.model)!.shellThickness,
        2);
  });

  test('AI rejects an unsafe shell thickness', () {
    final parsed = AiCadCommand.fromJson(command([
      {
        'operationId': 'extrude-1',
        'type': 'extrude',
        'parameters': {'profileId': 'base', 'depth': 20}
      },
      {
        'operationId': 'shell-1',
        'type': 'shell',
        'parameters': {'thickness': 20}
      },
    ]));
    expect(
        () => const AiCommandEngine()
            .preview(parsed, sketch, const ModelDocument()),
        throwsFormatException);
  });

  test('AI can fillet an extrusion with a validated radius', () {
    final parsed = AiCadCommand.fromJson(command([
      {
        'operationId': 'extrude-1',
        'type': 'extrude',
        'parameters': {'profileId': 'base', 'depth': 20}
      },
      {
        'operationId': 'fillet-1',
        'type': 'fillet',
        'parameters': {'radius': 4}
      },
    ]));
    final preview =
        const AiCommandEngine().preview(parsed, sketch, const ModelDocument());
    expect(preview.model.operations.last.kind, ModelOperationKind.fillet);
    expect(const ModelEvaluator().evaluate(sketch, preview.model)!.cornerRadius,
        4);
  });

  test('AI can chamfer an extrusion with a validated distance', () {
    final parsed = AiCadCommand.fromJson(command([
      {
        'operationId': 'extrude-1',
        'type': 'extrude',
        'parameters': {'profileId': 'base', 'depth': 20}
      },
      {
        'operationId': 'chamfer-1',
        'type': 'chamfer',
        'parameters': {'distance': 3}
      },
    ]));
    final preview =
        const AiCommandEngine().preview(parsed, sketch, const ModelDocument());
    expect(preview.model.operations.last.kind, ModelOperationKind.chamfer);
    expect(const ModelEvaluator().evaluate(sketch, preview.model)!.chamfer, 3);
  });

  test('unsupported and invalid operations are rejected before mutation', () {
    final unsupported = AiCadCommand.fromJson(command([
      {
        'operationId': 'shell-1',
        'type': 'shell',
        'parameters': <String, Object?>{}
      }
    ]));
    expect(
        () => const AiCommandEngine()
            .preview(unsupported, sketch, const ModelDocument()),
        throwsFormatException);
    final invalid = AiCadCommand.fromJson(command([
      {
        'operationId': 'cut-1',
        'type': 'cut',
        'parameters': {'profileId': 'missing', 'depth': -1}
      }
    ]));
    expect(
        () => const AiCommandEngine()
            .preview(invalid, sketch, const ModelDocument()),
        throwsFormatException);
  });

  test('duplicate operation IDs are rejected', () {
    final parsed = AiCadCommand.fromJson(command([
      {
        'operationId': 'same',
        'type': 'extrude',
        'parameters': {'profileId': 'base', 'depth': 8}
      },
      {
        'operationId': 'same',
        'type': 'cut',
        'parameters': {'profileId': 'hole', 'depth': 8}
      },
    ]));
    expect(
        () => const AiCommandEngine()
            .preview(parsed, sketch, const ModelDocument()),
        throwsFormatException);
  });

  test('AI audit records persist the undo snapshot and status', () {
    final before = ModelDocument(operations: [
      ModelOperation(
          id: 'base-op',
          kind: ModelOperationKind.extrude,
          profileId: 'base',
          depth: 8,
          createdAt: DateTime.utc(2026))
    ]);
    final record = AiCommandRecord(
        commandId: 'command-undo',
        summary: 'Cut circular profile hole',
        status: AiCommandStatus.applied,
        createdAt: DateTime.utc(2026),
        previousModel: before);
    final decoded = AiCommandRecord.fromJson(record.toJson());
    expect(decoded.previousModel!.operations.single.id, 'base-op');
    expect(decoded.copyWith(status: AiCommandStatus.undone).status,
        AiCommandStatus.undone);
  });
}
