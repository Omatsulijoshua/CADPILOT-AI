import 'package:cadpilot_tablet/src/model_3d.dart';
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
}
