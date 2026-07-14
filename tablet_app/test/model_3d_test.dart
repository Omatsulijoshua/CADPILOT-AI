import 'dart:math' as math;
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

  test('cut-solid tessellation is closed manifold and volume-bounded', () {
    final cut = ModelOperation(
        id: 'op-2',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]),
        ModelDocument(operations: [extrude, cut]))!;
    final mesh = const SolidMesher(targetCells: 48).tessellate(solid);
    expect(mesh.isClosedManifold, isTrue);
    expect(mesh.triangles.length, greaterThan(12));
    final relativeError =
        (mesh.estimatedVolume - solid.volume).abs() / solid.volume;
    expect(relativeError, lessThan(0.03));
    expect(mesh.tolerance, lessThanOrEqualTo(100 / 48));
  });

  test('cut-solid STL contains the tessellated hole', () {
    final cut = ModelOperation(
        id: 'op-2',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]),
        ModelDocument(operations: [extrude, cut]))!;
    final stl = const StlExporter(mesher: SolidMesher(targetCells: 48))
        .export(solid, name: 'cut_bracket');
    expect(RegExp('facet normal').allMatches(stl).length, greaterThan(12));
    expect(stl.trim(), endsWith('endsolid cut_bracket'));
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

  test('materials persist through operations and remain undoable', () {
    final history = ModelHistory(
        ModelDocument(operations: [extrude], material: CadMaterial.generic));
    history.commit(history.document.copyWith(material: CadMaterial.pla));
    history.add(ModelOperation(
        id: 'op-extra',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026)));
    expect(history.document.material, CadMaterial.pla);
    final decoded = ModelDocument.fromJson(history.document.toJson());
    expect(decoded.material, CadMaterial.pla);
    history.undo();
    expect(history.document.material, CadMaterial.pla);
    history.undo();
    expect(history.document.material, CadMaterial.generic);
  });

  test('measurements include through-hole area and material mass', () {
    final cut = ModelOperation(
        id: 'op-2',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]),
        ModelDocument(
            operations: [extrude, cut], material: CadMaterial.aluminum6061))!;
    final values = SolidMeasurements.from(solid, CadMaterial.aluminum6061);
    expect(values.volumeMm3, closeTo(40000 - math.pi * 25 * 8, 0.001));
    expect(values.surfaceAreaMm2, closeTo(12400 + math.pi * 30, 0.001));
    expect(values.massGrams, closeTo(values.volumeMm3 / 1000 * 2.70, 0.001));
    expect(
        SolidMeasurements.from(solid, CadMaterial.generic).massGrams, isNull);
  });

  test('linear cut pattern persists and evaluates repeated holes', () {
    final cut = ModelOperation(
        id: 'cut-source',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final pattern = ModelOperation(
        id: 'pattern-1',
        kind: ModelOperationKind.linearPattern,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026),
        sourceOperationId: cut.id,
        instanceCount: 3,
        spacing: 20);
    final decoded = ModelDocument.fromJson(
        ModelDocument(operations: [extrude, cut, pattern]).toJson());
    expect(decoded.operations.last.instanceCount, 3);
    expect(decoded.operations.last.spacing, 20);
    expect(decoded.operations.last.sourceOperationId, cut.id);
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]), decoded)!;
    expect(solid.cuts.map((item) => item.center.dx), [45, 65, 85]);
    expect(solid.volume, closeTo(40000 - 3 * math.pi * 25 * 8, 0.001));
  });

  test('pattern follows source and feature suppression', () {
    final cut = ModelOperation(
        id: 'cut-source',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final pattern = ModelOperation(
        id: 'pattern-1',
        kind: ModelOperationKind.linearPattern,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026),
        sourceOperationId: cut.id,
        instanceCount: 3,
        spacing: 20);
    EvaluatedSolid evaluate(ModelOperation source, ModelOperation repeated) =>
        const ModelEvaluator().evaluate(
            const SketchDocument(entities: [rectangle, circle]),
            ModelDocument(operations: [extrude, source, repeated]))!;
    expect(
        evaluate(cut, pattern.copyWith(suppressed: true)).cuts, hasLength(1));
    expect(evaluate(cut.copyWith(suppressed: true), pattern).cuts, isEmpty);
  });

  test('multi-hole pattern exports as a closed manifold STL', () {
    final cut = ModelOperation(
        id: 'cut-source',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final pattern = ModelOperation(
        id: 'pattern-1',
        kind: ModelOperationKind.linearPattern,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026),
        sourceOperationId: cut.id,
        instanceCount: 3,
        spacing: 20);
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]),
        ModelDocument(operations: [extrude, cut, pattern]))!;
    final mesh = const SolidMesher(targetCells: 64).tessellate(solid);
    expect(mesh.isClosedManifold, isTrue);
    expect(const StlExporter().export(solid), contains('facet normal'));
  });

  test('linear pattern validator rejects overlap and escaped instances', () {
    const solid = EvaluatedSolid(
        origin: Offset(10, 20), width: 100, height: 50, depth: 8, cuts: []);
    const validator = LinearPatternValidator();
    expect(validator.validate(solid, circle, count: 3, spacing: 9),
        contains('diameter'));
    expect(validator.validate(solid, circle, count: 5, spacing: 20),
        contains('outside'));
    expect(validator.validate(solid, circle, count: 3, spacing: 20), isNull);
  });

  test('mirror cut persists and evaluates across the vertical center plane',
      () {
    final cut = ModelOperation(
        id: 'cut-source',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final mirror = ModelOperation(
        id: 'mirror-1',
        kind: ModelOperationKind.mirrorCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026),
        sourceOperationId: cut.id);
    final decoded = ModelDocument.fromJson(
        ModelDocument(operations: [extrude, cut, mirror]).toJson());
    expect(decoded.operations.last.kind, ModelOperationKind.mirrorCut);
    expect(decoded.operations.last.sourceOperationId, cut.id);
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]), decoded)!;
    expect(solid.cuts.map((item) => item.center.dx), [45, 75]);
    expect(solid.volume, closeTo(40000 - 2 * math.pi * 25 * 8, 0.001));
    expect(
        const SolidMesher(targetCells: 64).tessellate(solid).isClosedManifold,
        isTrue);
  });

  test('mirror cut follows source suppression', () {
    final cut = ModelOperation(
        id: 'cut-source',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026),
        suppressed: true);
    final mirror = ModelOperation(
        id: 'mirror-1',
        kind: ModelOperationKind.mirrorCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026),
        sourceOperationId: cut.id);
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]),
        ModelDocument(operations: [extrude, cut, mirror]))!;
    expect(solid.cuts, isEmpty);
  });

  test('mirror validator rejects a self-overlapping centerline hole', () {
    const centerlineCircle = SketchEntity(
        id: 'center',
        kind: SketchEntityKind.circle,
        start: Offset(60, 40),
        end: Offset(65, 40));
    const solid = EvaluatedSolid(
        origin: Offset(10, 20),
        width: 100,
        height: 50,
        depth: 8,
        cuts: [CircularCut(center: Offset(60, 40), radius: 5)]);
    const validator = MirrorCutValidator();
    expect(validator.validate(solid, centerlineCircle), contains('overlaps'));
    expect(validator.mirroredCenter(solid, centerlineCircle),
        const Offset(60, 40));
  });
  test('chamfer persists evaluates and follows suppression', () {
    final chamfer = ModelOperation(
        id: 'chamfer-1',
        kind: ModelOperationKind.chamfer,
        profileId: 'rect',
        depth: 5,
        createdAt: DateTime.utc(2026));
    final decoded = ModelDocument.fromJson(
        ModelDocument(operations: [extrude, chamfer]).toJson());
    expect(decoded.operations.last.kind, ModelOperationKind.chamfer);
    expect(decoded.operations.last.depth, 5);
    final solid = const ModelEvaluator()
        .evaluate(const SketchDocument(entities: [rectangle]), decoded)!;
    expect(solid.chamfer, 5);
    expect(solid.volume, closeTo((5000 - 50) * 8, 0.001));
    final suppressed = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle]),
        ModelDocument(
            operations: [extrude, chamfer.copyWith(suppressed: true)]))!;
    expect(suppressed.chamfer, 0);
    expect(suppressed.volume, 40000);
  });

  test('chamfer measurements use reduced plan area and perimeter', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [],
        chamfer: 5);
    final values = SolidMeasurements.from(solid, CadMaterial.pla);
    const expectedArea = 2 * (5000 - 50) + (300 + 20 * (math.sqrt2 - 2)) * 8;
    expect(values.volumeMm3, 39600);
    expect(values.surfaceAreaMm2, closeTo(expectedArea, 0.001));
    expect(values.massGrams, closeTo(39.6 * 1.24, 0.001));
  });

  test('chamfer validator rejects invalid distances and cut collisions', () {
    const validator = ChamferValidator();
    const plain = EvaluatedSolid(
        origin: Offset.zero, width: 100, height: 50, depth: 8, cuts: []);
    expect(validator.validate(plain, 0), contains('greater than zero'));
    expect(validator.validate(plain, 25), contains('half'));
    expect(validator.validate(plain, 5), isNull);
    const cornerCut = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [CircularCut(center: Offset(4, 4), radius: 3)]);
    expect(validator.validate(cornerCut, 10), contains('intersect'));
  });

  test('plain chamfer uses an exact closed 28-triangle mesh', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [],
        chamfer: 5);
    final mesh = const SolidMesher().tessellate(solid);
    expect(mesh.triangles, hasLength(28));
    expect(mesh.isClosedManifold, isTrue);
    expect(mesh.tolerance, 0);
    expect(mesh.estimatedVolume, solid.volume);
    expect(
        const StlExporter().export(solid), contains('endsolid cadpilot_part'));
  });

  test('chamfer with through hole remains manifold and volume-bounded', () {
    const solid = EvaluatedSolid(
        origin: Offset(10, 20),
        width: 100,
        height: 50,
        depth: 8,
        cuts: [CircularCut(center: Offset(45, 40), radius: 5)],
        chamfer: 5);
    final mesh = const SolidMesher(targetCells: 64).tessellate(solid);
    expect(mesh.isClosedManifold, isTrue);
    expect((mesh.estimatedVolume - solid.volume).abs() / solid.volume,
        lessThan(0.03));
  });
  test('fillet persists evaluates and follows suppression', () {
    final fillet = ModelOperation(
        id: 'fillet-1',
        kind: ModelOperationKind.fillet,
        profileId: 'rect',
        depth: 6,
        createdAt: DateTime.utc(2026));
    final decoded = ModelDocument.fromJson(
        ModelDocument(operations: [extrude, fillet]).toJson());
    expect(decoded.operations.last.kind, ModelOperationKind.fillet);
    expect(decoded.operations.last.depth, 6);
    final solid = const ModelEvaluator()
        .evaluate(const SketchDocument(entities: [rectangle]), decoded)!;
    expect(solid.cornerRadius, 6);
    expect(solid.volume, closeTo((5000 - (4 - math.pi) * 36) * 8, 0.001));
    final suppressed = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle]),
        ModelDocument(
            operations: [extrude, fillet.copyWith(suppressed: true)]))!;
    expect(suppressed.cornerRadius, 0);
    expect(suppressed.volume, 40000);
  });

  test('fillet measurements use analytic rounded area and perimeter', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [],
        cornerRadius: 5);
    final values = SolidMeasurements.from(solid, CadMaterial.aluminum6061);
    const expectedArea =
        2 * (5000 - (4 - math.pi) * 25) + (300 - 40 + 10 * math.pi) * 8;
    expect(values.volumeMm3, closeTo((5000 - (4 - math.pi) * 25) * 8, 0.001));
    expect(values.surfaceAreaMm2, closeTo(expectedArea, 0.001));
    expect(values.massGrams, closeTo(values.volumeMm3 / 1000 * 2.70, 0.001));
  });

  test('fillet validator rejects invalid radii conflicts and cut collisions',
      () {
    const validator = FilletValidator();
    const plain = EvaluatedSolid(
        origin: Offset.zero, width: 100, height: 50, depth: 8, cuts: []);
    expect(validator.validate(plain, 0), contains('greater than zero'));
    expect(validator.validate(plain, 25), contains('half'));
    expect(validator.validate(plain, 5), isNull);
    const chamfered = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [],
        chamfer: 4);
    expect(validator.validate(chamfered, 5), contains('chamfer'));
    const cornerCut = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [CircularCut(center: Offset(4, 4), radius: 3)]);
    expect(validator.validate(cornerCut, 10), contains('intersect'));
  });

  test('plain fillet uses a closed 140-triangle rounded mesh', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [],
        cornerRadius: 5);
    final mesh = const SolidMesher().tessellate(solid);
    expect(mesh.triangles, hasLength(140));
    expect(mesh.isClosedManifold, isTrue);
    expect(mesh.tolerance, greaterThan(0));
    expect(mesh.tolerance, lessThan(0.1));
    expect(mesh.estimatedVolume, solid.volume);
    expect(
        const StlExporter().export(solid), contains('endsolid cadpilot_part'));
  });

  test('fillet with through hole remains manifold and volume-bounded', () {
    const solid = EvaluatedSolid(
        origin: Offset(10, 20),
        width: 100,
        height: 50,
        depth: 8,
        cuts: [CircularCut(center: Offset(45, 40), radius: 5)],
        cornerRadius: 6);
    final mesh = const SolidMesher(targetCells: 64).tessellate(solid);
    expect(mesh.isClosedManifold, isTrue);
    expect((mesh.estimatedVolume - solid.volume).abs() / solid.volume,
        lessThan(0.03));
  });
  test('shell persists evaluates and follows suppression', () {
    final shell = ModelOperation(
        id: 'shell-1',
        kind: ModelOperationKind.shell,
        profileId: 'rect',
        depth: 2,
        createdAt: DateTime.utc(2026));
    final decoded = ModelDocument.fromJson(
        ModelDocument(operations: [extrude, shell]).toJson());
    expect(decoded.operations.last.kind, ModelOperationKind.shell);
    expect(decoded.operations.last.depth, 2);
    final solid = const ModelEvaluator()
        .evaluate(const SketchDocument(entities: [rectangle]), decoded)!;
    expect(solid.shellThickness, 2);
    expect(solid.volume, 40000 - 96 * 46 * 6);
    final suppressed = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle]),
        ModelDocument(
            operations: [extrude, shell.copyWith(suppressed: true)]))!;
    expect(suppressed.shellThickness, 0);
    expect(suppressed.volume, 40000);
  });

  test('shell measurements include outer rim and internal cavity', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [],
        shellThickness: 2);
    final values = SolidMeasurements.from(solid, CadMaterial.pla);
    expect(values.volumeMm3, 13504);
    expect(values.surfaceAreaMm2, 14104);
    expect(values.massGrams, closeTo(13.504 * 1.24, 0.001));
  });

  test('shell validator rejects invalid thickness and modified bases', () {
    const validator = ShellValidator();
    const plain = EvaluatedSolid(
        origin: Offset.zero, width: 100, height: 50, depth: 8, cuts: []);
    expect(validator.validate(plain, 0), contains('greater than zero'));
    expect(validator.validate(plain, 8), contains('smaller'));
    expect(validator.validate(plain, 2), isNull);
    const cutSolid = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [CircularCut(center: Offset(50, 25), radius: 4)]);
    expect(validator.validate(cutSolid, 2), contains('unmodified'));
    const filleted = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [],
        cornerRadius: 4);
    expect(validator.validate(filleted, 2), contains('unmodified'));
  });

  test('open-top shell exports an exact closed 28-triangle mesh', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [],
        shellThickness: 2);
    final mesh = const SolidMesher().tessellate(solid);
    expect(mesh.triangles, hasLength(28));
    expect(mesh.isClosedManifold, isTrue);
    expect(mesh.tolerance, 0);
    expect(mesh.estimatedVolume, solid.volume);
    final stl = const StlExporter().export(solid, name: 'shell_part');
    expect(RegExp('facet normal').allMatches(stl), hasLength(28));
    expect(stl.trim(), endsWith('endsolid shell_part'));
  });

  test('shell conflicts are rejected by edge modifiers', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero,
        width: 100,
        height: 50,
        depth: 8,
        cuts: [],
        shellThickness: 2);
    expect(const FilletValidator().validate(solid, 3), contains('shell'));
    expect(const ChamferValidator().validate(solid, 3), contains('shell'));
  });
  test('revolve persists and evaluates a rectangular radial section', () {
    final revolve = ModelOperation(
        id: 'revolve-1',
        kind: ModelOperationKind.revolve,
        profileId: 'rect',
        depth: 360,
        createdAt: DateTime.utc(2026));
    final decoded =
        ModelDocument.fromJson(ModelDocument(operations: [revolve]).toJson());
    expect(decoded.operations.single.kind, ModelOperationKind.revolve);
    expect(decoded.operations.single.depth, 360);
    final solid = const ModelEvaluator()
        .evaluate(const SketchDocument(entities: [rectangle]), decoded)!;
    expect(solid.revolved, isTrue);
    expect(solid.revolveRadius, 100);
    expect(solid.width, 200);
    expect(solid.height, 200);
    expect(solid.depth, 50);
    expect(solid.volume, closeTo(math.pi * 100 * 100 * 50, 0.001));
  });

  test('revolve suppression removes the base solid', () {
    final revolve = ModelOperation(
        id: 'revolve-1',
        kind: ModelOperationKind.revolve,
        profileId: 'rect',
        depth: 360,
        createdAt: DateTime.utc(2026),
        suppressed: true);
    expect(
        const ModelEvaluator().evaluate(
            const SketchDocument(entities: [rectangle]),
            ModelDocument(operations: [revolve])),
        isNull);
  });

  test('revolved measurements use analytic cylinder properties', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero,
        width: 20,
        height: 20,
        depth: 30,
        cuts: [],
        revolved: true,
        revolveRadius: 10);
    final values = SolidMeasurements.from(solid, CadMaterial.aluminum6061);
    expect(values.volumeMm3, closeTo(math.pi * 100 * 30, 0.001));
    expect(values.surfaceAreaMm2, closeTo(2 * math.pi * 10 * 40, 0.001));
    expect(values.massGrams, closeTo(values.volumeMm3 / 1000 * 2.70, 0.001));
  });

  test('revolved cylinder exports a closed 252-triangle mesh', () {
    const solid = EvaluatedSolid(
        origin: Offset.zero,
        width: 20,
        height: 20,
        depth: 30,
        cuts: [],
        revolved: true,
        revolveRadius: 10);
    final mesh = const SolidMesher().tessellate(solid);
    expect(mesh.triangles, hasLength(252));
    expect(mesh.isClosedManifold, isTrue);
    expect(mesh.tolerance, greaterThan(0));
    expect(mesh.estimatedVolume, solid.volume);
    final stl = const StlExporter().export(solid, name: 'revolved_part');
    expect(RegExp('facet normal').allMatches(stl), hasLength(252));
    expect(stl.trim(), endsWith('endsolid revolved_part'));
  });

  test('revolve validator and evaluator protect base topology', () {
    const validator = RevolveValidator();
    expect(validator.validate(rectangle, const ModelDocument()), isNull);
    expect(validator.validate(rectangle, ModelDocument(operations: [extrude])),
        contains('new base'));
    final revolve = ModelOperation(
        id: 'revolve-1',
        kind: ModelOperationKind.revolve,
        profileId: 'rect',
        depth: 360,
        createdAt: DateTime.utc(2026));
    final cut = ModelOperation(
        id: 'cut-after-revolve',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 50,
        createdAt: DateTime.utc(2026));
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]),
        ModelDocument(operations: [revolve, cut]))!;
    expect(solid.cuts, isEmpty);
    expect(solid.volume, closeTo(math.pi * 100 * 100 * 50, 0.001));
  });
  test('circular cut pattern persists and evaluates rotated holes', () {
    final cut = ModelOperation(
        id: 'cut-source',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final pattern = ModelOperation(
        id: 'circular-pattern-1',
        kind: ModelOperationKind.circularPattern,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026),
        sourceOperationId: cut.id,
        instanceCount: 4,
        spacing: 90);
    final decoded = ModelDocument.fromJson(
        ModelDocument(operations: [extrude, cut, pattern]).toJson());
    expect(decoded.operations.last.kind, ModelOperationKind.circularPattern);
    expect(decoded.operations.last.instanceCount, 4);
    expect(decoded.operations.last.spacing, 90);
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]), decoded)!;
    expect(solid.cuts, hasLength(4));
    expect(solid.cuts[0].center, const Offset(45, 40));
    expect(solid.cuts[1].center.dx, closeTo(65, 0.001));
    expect(solid.cuts[1].center.dy, closeTo(30, 0.001));
    expect(solid.cuts[2].center.dx, closeTo(75, 0.001));
    expect(solid.cuts[2].center.dy, closeTo(50, 0.001));
    expect(solid.volume, closeTo(40000 - 4 * math.pi * 25 * 8, 0.001));
  });

  test('circular pattern follows source and feature suppression', () {
    final cut = ModelOperation(
        id: 'cut-source',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final pattern = ModelOperation(
        id: 'circular-pattern-1',
        kind: ModelOperationKind.circularPattern,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026),
        sourceOperationId: cut.id,
        instanceCount: 4,
        spacing: 90);
    EvaluatedSolid evaluate(ModelOperation source, ModelOperation repeated) =>
        const ModelEvaluator().evaluate(
            const SketchDocument(entities: [rectangle, circle]),
            ModelDocument(operations: [extrude, source, repeated]))!;
    expect(
        evaluate(cut, pattern.copyWith(suppressed: true)).cuts, hasLength(1));
    expect(evaluate(cut.copyWith(suppressed: true), pattern).cuts, isEmpty);
  });

  test('circular pattern validator rejects center overlap and escape', () {
    const solid = EvaluatedSolid(
        origin: Offset(10, 20), width: 100, height: 50, depth: 8, cuts: []);
    const centerProfile = SketchEntity(
        id: 'center-hole',
        kind: SketchEntityKind.circle,
        start: Offset(60, 45),
        end: Offset(65, 45));
    const edgeProfile = SketchEntity(
        id: 'edge-hole',
        kind: SketchEntityKind.circle,
        start: Offset(15, 25),
        end: Offset(20, 25));
    const validator = CircularPatternValidator();
    expect(
        validator.validate(solid, centerProfile, count: 4), contains('away'));
    expect(validator.validate(solid, circle, count: 50), contains('overlap'));
    expect(
        validator.validate(solid, edgeProfile, count: 4), contains('outside'));
    expect(validator.validate(solid, circle, count: 4), isNull);
  });

  test('circular pattern exports as a closed manifold STL', () {
    final cut = ModelOperation(
        id: 'cut-source',
        kind: ModelOperationKind.circularCut,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026));
    final pattern = ModelOperation(
        id: 'circular-pattern-1',
        kind: ModelOperationKind.circularPattern,
        profileId: 'hole',
        depth: 8,
        createdAt: DateTime.utc(2026),
        sourceOperationId: cut.id,
        instanceCount: 4,
        spacing: 90);
    final solid = const ModelEvaluator().evaluate(
        const SketchDocument(entities: [rectangle, circle]),
        ModelDocument(operations: [extrude, cut, pattern]))!;
    final mesh = const SolidMesher(targetCells: 64).tessellate(solid);
    expect(mesh.isClosedManifold, isTrue);
    expect((mesh.estimatedVolume - solid.volume).abs() / solid.volume,
        lessThan(0.03));
    expect(const StlExporter().export(solid), contains('facet normal'));
  });
}
