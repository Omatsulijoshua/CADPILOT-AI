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
}
