import 'dart:math' as math;
import 'dart:ui';
import 'sketch_models.dart';

enum CadMaterial {
  generic('Generic', 0),
  pla('PLA', 1.24),
  aluminum6061('Aluminum 6061', 2.70),
  mildSteel('Mild steel', 7.85);

  const CadMaterial(this.label, this.densityGramsPerCm3);
  final String label;
  final double densityGramsPerCm3;
}

enum ModelOperationKind {
  extrude,
  circularCut,
  linearPattern,
  mirrorCut,
  chamfer,
  fillet
}

class ModelOperation {
  const ModelOperation({
    required this.id,
    required this.kind,
    required this.profileId,
    required this.depth,
    required this.createdAt,
    this.name,
    this.suppressed = false,
    this.sourceOperationId,
    this.instanceCount = 1,
    this.spacing = 0,
  });
  final String id;
  final ModelOperationKind kind;
  final String profileId;
  final double depth;
  final DateTime createdAt;
  final String? name;
  final bool suppressed;
  final String? sourceOperationId;
  final int instanceCount;
  final double spacing;
  String get displayName =>
      name ??
      switch (kind) {
        ModelOperationKind.extrude => 'Extrude',
        ModelOperationKind.circularCut => 'Circular cut',
        ModelOperationKind.linearPattern => 'Linear pattern',
        ModelOperationKind.mirrorCut => 'Mirror cut',
        ModelOperationKind.chamfer => 'Chamfer',
        ModelOperationKind.fillet => 'Fillet',
      };
  ModelOperation copyWith(
          {double? depth,
          String? name,
          bool? suppressed,
          int? instanceCount,
          double? spacing}) =>
      ModelOperation(
        id: id,
        kind: kind,
        profileId: profileId,
        depth: depth ?? this.depth,
        createdAt: createdAt,
        name: name ?? this.name,
        suppressed: suppressed ?? this.suppressed,
        sourceOperationId: sourceOperationId,
        instanceCount: instanceCount ?? this.instanceCount,
        spacing: spacing ?? this.spacing,
      );
  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'profileId': profileId,
        'depth': depth,
        'createdAt': createdAt.toIso8601String(),
        'name': name,
        'suppressed': suppressed,
        'sourceOperationId': sourceOperationId,
        'instanceCount': instanceCount,
        'spacing': spacing,
      };
  factory ModelOperation.fromJson(Map<String, Object?> json) => ModelOperation(
        id: json['id']! as String,
        kind: ModelOperationKind.values.byName(json['kind']! as String),
        profileId: json['profileId']! as String,
        depth: (json['depth']! as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt']! as String),
        name: json['name'] as String?,
        suppressed: (json['suppressed'] as bool?) ?? false,
        sourceOperationId: json['sourceOperationId'] as String?,
        instanceCount: (json['instanceCount'] as int?) ?? 1,
        spacing: (json['spacing'] as num?)?.toDouble() ?? 0,
      );
}

class ModelDocument {
  const ModelDocument(
      {this.operations = const [], this.material = CadMaterial.generic});
  final List<ModelOperation> operations;
  final CadMaterial material;
  Map<String, Object> toJson() => {
        'operations': operations.map((item) => item.toJson()).toList(),
        'material': material.name,
      };
  factory ModelDocument.fromJson(Map<String, Object?>? json) => ModelDocument(
      operations: (json?['operations'] as List<Object?>? ?? const [])
          .map((item) => ModelOperation.fromJson(item! as Map<String, Object?>))
          .toList(),
      material: CadMaterial.values
          .byName((json?['material'] as String?) ?? CadMaterial.generic.name));
  ModelDocument copyWith(
          {List<ModelOperation>? operations, CadMaterial? material}) =>
      ModelDocument(
          operations: operations ?? this.operations,
          material: material ?? this.material);
  ModelDocument add(ModelOperation operation) =>
      copyWith(operations: [...operations, operation]);
  ModelDocument replace(ModelOperation operation) => copyWith(
      operations: operations
          .map((item) => item.id == operation.id ? operation : item)
          .toList());
  ModelDocument remove(String id) =>
      copyWith(operations: operations.where((item) => item.id != id).toList());
}

class ModelHistory {
  ModelHistory(ModelDocument initial) : _document = initial;
  ModelDocument _document;
  final List<ModelDocument> _undo = [];
  final List<ModelDocument> _redo = [];
  ModelDocument get document => _document;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void commit(ModelDocument next) {
    _undo.add(_document);
    _document = next;
    _redo.clear();
  }

  void add(ModelOperation operation) => commit(_document.add(operation));
  void replace(ModelOperation operation) =>
      commit(_document.replace(operation));
  void remove(String id) => commit(_document.remove(id));
  void undo() {
    if (!canUndo) return;
    _redo.add(_document);
    _document = _undo.removeLast();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_document);
    _document = _redo.removeLast();
  }
}

class EvaluatedSolid {
  const EvaluatedSolid(
      {required this.origin,
      required this.width,
      required this.height,
      required this.depth,
      required this.cuts,
      this.chamfer = 0,
      this.cornerRadius = 0});
  final Offset origin;
  final double width;
  final double height;
  final double depth;
  final List<CircularCut> cuts;
  final double chamfer;
  final double cornerRadius;
  double get planArea => cornerRadius > 0
      ? width * height - (4 - math.pi) * cornerRadius * cornerRadius
      : width * height - 2 * chamfer * chamfer;
  double get planPerimeter => cornerRadius > 0
      ? 2 * (width + height) - 8 * cornerRadius + 2 * math.pi * cornerRadius
      : 2 * (width + height) + 4 * chamfer * (math.sqrt2 - 2);
  bool containsPlanPoint(Offset point) {
    final x = point.dx - origin.dx;
    final y = point.dy - origin.dy;
    if (x < 0 || y < 0 || x > width || y > height) return false;
    if (cornerRadius > 0) {
      final r = cornerRadius;
      if (x < r && y < r) return (Offset(x, y) - Offset(r, r)).distance <= r;
      if (x > width - r && y < r) {
        return (Offset(x, y) - Offset(width - r, r)).distance <= r;
      }
      if (x > width - r && y > height - r) {
        return (Offset(x, y) - Offset(width - r, height - r)).distance <= r;
      }
      if (x < r && y > height - r) {
        return (Offset(x, y) - Offset(r, height - r)).distance <= r;
      }
      return true;
    }
    if (chamfer <= 0) return true;
    return x + y >= chamfer &&
        (width - x) + y >= chamfer &&
        x + (height - y) >= chamfer &&
        (width - x) + (height - y) >= chamfer;
  }

  double get volume =>
      planArea * depth -
      cuts.fold(
          0, (sum, cut) => sum + math.pi * cut.radius * cut.radius * depth);
}

class FilletValidator {
  const FilletValidator();

  String? validate(EvaluatedSolid solid, double radius) {
    if (!radius.isFinite || radius <= 0) {
      return 'Fillet radius must be greater than zero.';
    }
    if (solid.chamfer > 0) {
      return 'Suppress or delete the chamfer before adding a fillet.';
    }
    if (radius >= math.min(solid.width, solid.height) / 2) {
      return 'Fillet radius must be less than half the shortest side.';
    }
    final candidate = EvaluatedSolid(
        origin: solid.origin,
        width: solid.width,
        height: solid.height,
        depth: solid.depth,
        cuts: solid.cuts,
        cornerRadius: radius);
    for (final cut in solid.cuts) {
      for (var index = 0; index < 48; index++) {
        final angle = index * math.pi * 2 / 48;
        final boundary = cut.center +
            Offset(math.cos(angle) * cut.radius, math.sin(angle) * cut.radius);
        if (!candidate.containsPlanPoint(boundary)) {
          return 'The fillet would intersect existing cut geometry.';
        }
      }
    }
    return null;
  }
}

class ChamferValidator {
  const ChamferValidator();

  String? validate(EvaluatedSolid solid, double distance) {
    if (!distance.isFinite || distance <= 0) {
      return 'Chamfer distance must be greater than zero.';
    }
    if (solid.cornerRadius > 0) {
      return 'Suppress or delete the fillet before adding a chamfer.';
    }
    if (distance >= math.min(solid.width, solid.height) / 2) {
      return 'Chamfer distance must be less than half the shortest side.';
    }
    final candidate = EvaluatedSolid(
        origin: solid.origin,
        width: solid.width,
        height: solid.height,
        depth: solid.depth,
        cuts: solid.cuts,
        chamfer: distance);
    for (final cut in solid.cuts) {
      for (var index = 0; index < 32; index++) {
        final angle = index * math.pi * 2 / 32;
        final boundary = cut.center +
            Offset(math.cos(angle) * cut.radius, math.sin(angle) * cut.radius);
        if (!candidate.containsPlanPoint(boundary)) {
          return 'The chamfer would intersect existing cut geometry.';
        }
      }
    }
    return null;
  }
}

class MirrorCutValidator {
  const MirrorCutValidator();

  String? validate(EvaluatedSolid solid, SketchEntity profile) {
    if (profile.kind != SketchEntityKind.circle) {
      return 'A mirrored cut requires a circular profile.';
    }
    final radius = profile.primaryDimension;
    final bounds = Rect.fromLTWH(
        solid.origin.dx, solid.origin.dy, solid.width, solid.height);
    if (profile.start.dx - radius < bounds.left ||
        profile.start.dx + radius > bounds.right ||
        profile.start.dy - radius < bounds.top ||
        profile.start.dy + radius > bounds.bottom) {
      return 'The source hole extends outside the solid.';
    }
    final mirrored =
        Offset(bounds.left + bounds.right - profile.start.dx, profile.start.dy);
    for (final cut in solid.cuts) {
      if ((mirrored - cut.center).distance < radius + cut.radius - 0.001) {
        return 'The mirrored hole overlaps existing cut geometry.';
      }
    }
    return null;
  }

  Offset mirroredCenter(EvaluatedSolid solid, SketchEntity profile) => Offset(
      solid.origin.dx + solid.origin.dx + solid.width - profile.start.dx,
      profile.start.dy);
}

class LinearPatternValidator {
  const LinearPatternValidator();

  String? validate(EvaluatedSolid solid, SketchEntity profile,
      {required int count, required double spacing}) {
    if (profile.kind != SketchEntityKind.circle) {
      return 'A linear cut pattern requires a circular profile.';
    }
    if (count < 2 || count > 50) {
      return 'Instance count must be between 2 and 50.';
    }
    final radius = profile.primaryDimension;
    if (!spacing.isFinite || spacing < radius * 2) {
      return 'Spacing must be at least the hole diameter.';
    }
    final bounds = Rect.fromLTWH(
        solid.origin.dx, solid.origin.dy, solid.width, solid.height);
    final first = profile.start;
    final last = first + Offset(spacing * (count - 1), 0);
    if (first.dx - radius < bounds.left ||
        first.dy - radius < bounds.top ||
        first.dy + radius > bounds.bottom ||
        last.dx + radius > bounds.right) {
      return 'The pattern extends outside the solid.';
    }
    return null;
  }
}

class SolidMeasurements {
  const SolidMeasurements(
      {required this.volumeMm3,
      required this.surfaceAreaMm2,
      required this.massGrams});
  final double volumeMm3;
  final double surfaceAreaMm2;
  final double? massGrams;

  factory SolidMeasurements.from(EvaluatedSolid solid, CadMaterial material) {
    final outerArea = 2 * solid.planArea + solid.planPerimeter * solid.depth;
    final cutAreaDelta = solid.cuts.fold<double>(
        0,
        (sum, cut) =>
            sum +
            2 * math.pi * cut.radius * solid.depth -
            2 * math.pi * cut.radius * cut.radius);
    final mass = material.densityGramsPerCm3 == 0
        ? null
        : solid.volume / 1000 * material.densityGramsPerCm3;
    return SolidMeasurements(
        volumeMm3: solid.volume,
        surfaceAreaMm2: outerArea + cutAreaDelta,
        massGrams: mass);
  }
}

class CircularCut {
  const CircularCut({required this.center, required this.radius});
  final Offset center;
  final double radius;
}

class ModelEvaluator {
  const ModelEvaluator();
  EvaluatedSolid? evaluate(SketchDocument sketch, ModelDocument model) {
    SketchEntity? base;
    double? depth;
    double chamfer = 0;
    double cornerRadius = 0;
    final cuts = <CircularCut>[];
    final activeOperations = <String>{};
    for (final operation in model.operations) {
      if (operation.suppressed) continue;
      final profile = sketch.entities
          .where((item) => item.id == operation.profileId)
          .firstOrNull;
      if (profile == null) continue;
      if (operation.kind == ModelOperationKind.extrude &&
          profile.kind == SketchEntityKind.rectangle) {
        base = profile;
        depth = operation.depth;
      }
      if (operation.kind == ModelOperationKind.circularCut &&
          profile.kind == SketchEntityKind.circle &&
          base != null) {
        cuts.add(CircularCut(
            center: profile.start, radius: profile.primaryDimension));
        activeOperations.add(operation.id);
      }
      if (operation.kind == ModelOperationKind.linearPattern &&
          profile.kind == SketchEntityKind.circle &&
          base != null &&
          activeOperations.contains(operation.sourceOperationId)) {
        for (var index = 1; index < operation.instanceCount; index++) {
          cuts.add(CircularCut(
              center: profile.start + Offset(operation.spacing * index, 0),
              radius: profile.primaryDimension));
        }
      }
      if (operation.kind == ModelOperationKind.mirrorCut &&
          profile.kind == SketchEntityKind.circle &&
          base != null &&
          activeOperations.contains(operation.sourceOperationId)) {
        final rect = Rect.fromPoints(base.start, base.end);
        cuts.add(CircularCut(
            center: Offset(
                rect.left + rect.right - profile.start.dx, profile.start.dy),
            radius: profile.primaryDimension));
      }
      if (operation.kind == ModelOperationKind.chamfer &&
          profile.kind == SketchEntityKind.rectangle &&
          base != null &&
          profile.id == base.id) {
        chamfer = operation.depth;
      }
      if (operation.kind == ModelOperationKind.fillet &&
          profile.kind == SketchEntityKind.rectangle &&
          base != null &&
          profile.id == base.id) {
        cornerRadius = operation.depth;
      }
    }
    if (base == null || depth == null) return null;
    final rect = Rect.fromPoints(base.start, base.end);
    return EvaluatedSolid(
        origin: rect.topLeft,
        width: rect.width,
        height: rect.height,
        depth: depth,
        cuts: cuts,
        chamfer: chamfer,
        cornerRadius: cornerRadius);
  }
}

class MeshPoint {
  const MeshPoint(this.x, this.y, this.z);
  final double x, y, z;
  String get key =>
      '${x.toStringAsFixed(8)},${y.toStringAsFixed(8)},${z.toStringAsFixed(8)}';
}

class MeshTriangle {
  const MeshTriangle(this.a, this.b, this.c);
  final MeshPoint a, b, c;
  List<MeshPoint> get vertices => [a, b, c];
}

class SolidMesh {
  const SolidMesh(
      {required this.triangles,
      required this.tolerance,
      required this.estimatedVolume});
  final List<MeshTriangle> triangles;
  final double tolerance;
  final double estimatedVolume;
  bool get isClosedManifold {
    final edges = <String, int>{};
    for (final triangle in triangles) {
      final vertices = triangle.vertices;
      for (var index = 0; index < 3; index++) {
        final first = vertices[index].key;
        final second = vertices[(index + 1) % 3].key;
        final key =
            first.compareTo(second) < 0 ? '$first|$second' : '$second|$first';
        edges[key] = (edges[key] ?? 0) + 1;
      }
    }
    return edges.isNotEmpty && edges.values.every((count) => count == 2);
  }
}

class SolidMesher {
  const SolidMesher({this.targetCells = 56});
  final int targetCells;
  SolidMesh tessellate(EvaluatedSolid solid) {
    if (solid.cuts.isEmpty) {
      if (solid.cornerRadius > 0) return _filletedPrism(solid);
      return solid.chamfer > 0 ? _chamferedPrism(solid) : _cuboid(solid);
    }
    final nx = targetCells.clamp(12, 120);
    final ny =
        (targetCells * solid.height / solid.width).round().clamp(12, 120);
    final dx = solid.width / nx;
    final dy = solid.height / ny;
    final occupied = List.generate(
        nx,
        (x) => List.generate(ny, (y) {
              final point = Offset(solid.origin.dx + (x + 0.5) * dx,
                  solid.origin.dy + (y + 0.5) * dy);
              return solid.containsPlanPoint(point) &&
                  solid.cuts.every(
                      (cut) => (point - cut.center).distance >= cut.radius);
            }));
    final triangles = <MeshTriangle>[];
    var cells = 0;
    bool filled(int x, int y) =>
        x >= 0 && y >= 0 && x < nx && y < ny && occupied[x][y];
    for (var x = 0; x < nx; x++) {
      for (var y = 0; y < ny; y++) {
        if (!occupied[x][y]) continue;
        cells++;
        final x0 = x * dx,
            x1 = (x + 1) * dx,
            y0 = y * dy,
            y1 = (y + 1) * dy,
            z = solid.depth;
        final b00 = MeshPoint(x0, y0, 0),
            b10 = MeshPoint(x1, y0, 0),
            b11 = MeshPoint(x1, y1, 0),
            b01 = MeshPoint(x0, y1, 0);
        final t00 = MeshPoint(x0, y0, z),
            t10 = MeshPoint(x1, y0, z),
            t11 = MeshPoint(x1, y1, z),
            t01 = MeshPoint(x0, y1, z);
        triangles
          ..add(MeshTriangle(t00, t10, t11))
          ..add(MeshTriangle(t00, t11, t01));
        triangles
          ..add(MeshTriangle(b00, b11, b10))
          ..add(MeshTriangle(b00, b01, b11));
        if (!filled(x - 1, y)) _quad(triangles, b00, t00, t01, b01);
        if (!filled(x + 1, y)) _quad(triangles, b10, b11, t11, t10);
        if (!filled(x, y - 1)) _quad(triangles, b00, b10, t10, t00);
        if (!filled(x, y + 1)) _quad(triangles, b01, t01, t11, b11);
      }
    }
    return SolidMesh(
        triangles: triangles,
        tolerance: math.max(dx, dy),
        estimatedVolume: cells * dx * dy * solid.depth);
  }

  void _quad(List<MeshTriangle> target, MeshPoint a, MeshPoint b, MeshPoint c,
      MeshPoint d) {
    target
      ..add(MeshTriangle(a, b, c))
      ..add(MeshTriangle(a, c, d));
  }

  SolidMesh _cuboid(EvaluatedSolid solid) {
    final x = solid.width, y = solid.height, z = solid.depth;
    final v = <MeshPoint>[
      const MeshPoint(0, 0, 0),
      MeshPoint(x, 0, 0),
      MeshPoint(x, y, 0),
      MeshPoint(0, y, 0),
      MeshPoint(0, 0, z),
      MeshPoint(x, 0, z),
      MeshPoint(x, y, z),
      MeshPoint(0, y, z)
    ];
    const faces = <List<int>>[
      [0, 2, 1],
      [0, 3, 2],
      [4, 5, 6],
      [4, 6, 7],
      [0, 1, 5],
      [0, 5, 4],
      [1, 2, 6],
      [1, 6, 5],
      [2, 3, 7],
      [2, 7, 6],
      [3, 0, 4],
      [3, 4, 7]
    ];
    return SolidMesh(
        triangles: faces
            .map((face) => MeshTriangle(v[face[0]], v[face[1]], v[face[2]]))
            .toList(),
        tolerance: 0,
        estimatedVolume: solid.width * solid.height * solid.depth);
  }

  SolidMesh _filletedPrism(EvaluatedSolid solid) {
    const segments = 8;
    final r = solid.cornerRadius;
    final centers = <Offset>[
      Offset(r, r),
      Offset(solid.width - r, r),
      Offset(solid.width - r, solid.height - r),
      Offset(r, solid.height - r),
    ];
    const starts = [-math.pi, -math.pi / 2, 0.0, math.pi / 2];
    final plan = <MeshPoint>[];
    for (var corner = 0; corner < 4; corner++) {
      for (var step = 0; step <= segments; step++) {
        final angle = starts[corner] + step * math.pi / 2 / segments;
        plan.add(MeshPoint(centers[corner].dx + math.cos(angle) * r,
            centers[corner].dy + math.sin(angle) * r, 0));
      }
    }
    final top =
        plan.map((point) => MeshPoint(point.x, point.y, solid.depth)).toList();
    final triangles = <MeshTriangle>[];
    for (var index = 1; index < plan.length - 1; index++) {
      triangles
        ..add(MeshTriangle(plan[0], plan[index + 1], plan[index]))
        ..add(MeshTriangle(top[0], top[index], top[index + 1]));
    }
    for (var index = 0; index < plan.length; index++) {
      final next = (index + 1) % plan.length;
      _quad(triangles, plan[index], plan[next], top[next], top[index]);
    }
    final tolerance = r * (1 - math.cos(math.pi / (segments * 4)));
    return SolidMesh(
        triangles: triangles,
        tolerance: tolerance,
        estimatedVolume: solid.planArea * solid.depth);
  }

  SolidMesh _chamferedPrism(EvaluatedSolid solid) {
    final c = solid.chamfer;
    final x = solid.width, y = solid.height, z = solid.depth;
    final plan = <MeshPoint>[
      MeshPoint(c, 0, 0),
      MeshPoint(x - c, 0, 0),
      MeshPoint(x, c, 0),
      MeshPoint(x, y - c, 0),
      MeshPoint(x - c, y, 0),
      MeshPoint(c, y, 0),
      MeshPoint(0, y - c, 0),
      MeshPoint(0, c, 0),
    ];
    final top = plan.map((point) => MeshPoint(point.x, point.y, z)).toList();
    final triangles = <MeshTriangle>[];
    for (var index = 1; index < plan.length - 1; index++) {
      triangles
        ..add(MeshTriangle(plan[0], plan[index + 1], plan[index]))
        ..add(MeshTriangle(top[0], top[index], top[index + 1]));
    }
    for (var index = 0; index < plan.length; index++) {
      final next = (index + 1) % plan.length;
      _quad(triangles, plan[index], plan[next], top[next], top[index]);
    }
    return SolidMesh(
        triangles: triangles,
        tolerance: 0,
        estimatedVolume: solid.planArea * solid.depth);
  }
}

class StlExporter {
  const StlExporter({this.mesher = const SolidMesher()});
  final SolidMesher mesher;
  String export(EvaluatedSolid solid, {String name = 'cadpilot_part'}) {
    final mesh = mesher.tessellate(solid);
    if (!mesh.isClosedManifold) {
      throw StateError('Tessellation did not produce a closed manifold mesh.');
    }
    final buffer = StringBuffer('solid $name\n');
    for (final triangle in mesh.triangles) {
      final a = triangle.a, b = triangle.b, c = triangle.c;
      final ux = b.x - a.x,
          uy = b.y - a.y,
          uz = b.z - a.z,
          vx = c.x - a.x,
          vy = c.y - a.y,
          vz = c.z - a.z;
      final nx = uy * vz - uz * vy,
          ny = uz * vx - ux * vz,
          nz = ux * vy - uy * vx,
          length = math.sqrt(nx * nx + ny * ny + nz * nz);
      buffer.writeln(
          '  facet normal ${nx / length} ${ny / length} ${nz / length}');
      buffer.writeln('    outer loop');
      for (final point in triangle.vertices) {
        buffer.writeln('      vertex ${point.x} ${point.y} ${point.z}');
      }
      buffer.writeln('    endloop\n  endfacet');
    }
    buffer.writeln('endsolid $name');
    return buffer.toString();
  }
}
