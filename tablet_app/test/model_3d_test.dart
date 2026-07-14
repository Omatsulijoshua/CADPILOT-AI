import 'dart:ui' show Size;
import 'package:cadpilot_tablet/src/model_3d.dart';
import 'package:cadpilot_tablet/src/modeling_canvas.dart';
import 'package:cadpilot_tablet/src/sketch_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rectangle = SketchEntity(
      id: 'rect',
      kind: SketchEntityKind.rectangle,
      start: Offset(10, 20),
      end: Offset(110, 70));
  const circle = SketchEntity(
      id: 'hole',
      kind: SketchEntityKind.circle,
      start: Offset(45, 40),
      end: Offset(50, 40));
  final extrude = ModelOperation(
      id: 'op-1',
      kind: ModelOperationKind.extrude,
      profileId: 'rect',
      depth: 8,
      createdAt: DateTime.utc(2026));

  test('extrude evaluates rectangle into a bounded solid', () {
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle]),
        ModelDocument(operations: [extrude]));
    expect(solid, isNotNull);
    expect(solid!.width, 100);
    expect(solid.height, 50);
    expect(solid.depth, 8);
    expect(solid.volume, 40000);
  });

  test('circular cut reduces evaluated volume and persists', () {
    final cut = ModelOperation(
        id: 'op-2',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final model = ModelDocument(operations: [extrude, cut]);
    final decoded = ModelDocument.fromJson(model.toJson());
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]), decoded)!;
    expect(solid.cuts, hasLength(1));
    expect(solid.volume, lessThan(40000));
    expect(decoded.operations.last.kind, ModelOperationKind.circularCut);
  });

  test('cuboid STL contains twelve valid triangular facets', () {
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle]),
        ModelDocument(operations: [extrude]))!;
    final stl = const StlExporter().export(solid, name: 'bracket');
    expect(RegExp('facet normal').allMatches(stl), hasLength(12));
    expect(RegExp('vertex ').allMatches(stl), hasLength(36));
    expect(stl, startsWith('solid bracket'));
    expect(stl.trim(), endsWith('endsolid bracket'));
  });

  test('export refuses to silently omit circular cuts', () {
    final cut = ModelOperation(
        id: 'op-2',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]),
        ModelDocument(operations: [extrude, cut]))!;
    expect(() => const StlExporter().export(solid), throwsUnsupportedError);
  });

  test('model history edit suppress delete undo and redo are deterministic',
      () {
    final history = ModelHistory(ModelDocument(operations: [extrude]));
    history.replace(extrude.copyWith(name: 'Base plate', depth: 12));
    expect(history.document.operations.single.displayName, 'Base plate');
    expect(history.document.operations.single.depth, 12);
    history
        .replace(history.document.operations.single.copyWith(suppressed: true));
    expect(
        const ModelEvaluator().evaluate(
            const SketchDocument(entities: [rectangle]), history.document),
        isNull);
    history.undo();
    expect(history.document.operations.single.suppressed, isFalse);
    history.remove('op-1');
    expect(history.document.operations, isEmpty);
    history.undo();
    history.redo();
    expect(history.document.operations, isEmpty);
  });

  test('solid projection distinguishes edge and face hits', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero, width: 100, height: 60, depth: 15, cuts: []);
    final projection = SolidProjection(solid,
        yaw: -0.65,
        pitch: 0.45,
        zoom: 1,
        pan: Offset.zero,
        size: const Size(600, 500));
    final edgeHit = projection.hitTest(projection.points.first);
    expect(edgeHit.edge, isNotNull);
    final top = [
      projection.points[4],
      projection.points[7],
      projection.points[6],
      projection.points[5]
    ];
    final center = top.reduce((a, b) => a + b) / top.length.toDouble();
    final faceHit = projection.hitTest(center);
    expect(faceHit.face, isNotNull);
  });
}
