import 'package:cadpilot_tablet/src/model_3d.dart';
import 'package:cadpilot_tablet/src/modeling_canvas.dart';
import 'package:cadpilot_tablet/src/sketch_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rectangle = SketchEntity(
    id: 'radial-section',
    kind: SketchEntityKind.rectangle,
    start: Offset(10, 20),
    end: Offset(110, 70),
  );
  final revolve = ModelOperation(
    id: 'revolve',
    kind: ModelOperationKind.revolve,
    profileId: rectangle.id,
    depth: 360,
    createdAt: DateTime.utc(2026),
  );

  Future<void> pumpCanvas(
    WidgetTester tester, {
    required SketchEntity circle,
    required ValueChanged<ModelDocument> onChanged,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelingCanvas(
            projectName: 'Bore test',
            sketch: SketchDocument(entities: [rectangle, circle]),
            model: ModelDocument(operations: [revolve]),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('adds a centered bore to a revolved solid', (tester) async {
    const centeredBore = SketchEntity(
      id: 'centered-bore',
      kind: SketchEntityKind.circle,
      start: Offset(10, 120),
      end: Offset(25, 120),
    );
    ModelDocument? changed;
    await pumpCanvas(tester, circle: centeredBore, onChanged: (value) {
      changed = value;
    });

    await tester.tap(find.text('Through cut'));
    await tester.pump();

    expect(changed, isNotNull);
    expect(changed!.operations.last.kind, ModelOperationKind.circularCut);
    expect(changed!.operations.last.profileId, centeredBore.id);
  });

  testWidgets('blocks an off-axis bore on a revolved solid', (tester) async {
    const offAxisBore = SketchEntity(
      id: 'off-axis-bore',
      kind: SketchEntityKind.circle,
      start: Offset(45, 40),
      end: Offset(50, 40),
    );
    ModelDocument? changed;
    await pumpCanvas(tester, circle: offAxisBore, onChanged: (value) {
      changed = value;
    });

    await tester.tap(find.text('Through cut'));
    await tester.pump();

    expect(changed, isNull);
    expect(
      find.textContaining('must be centered on the revolve axis'),
      findsOneWidget,
    );
  });
}
