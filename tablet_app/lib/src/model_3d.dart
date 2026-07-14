import 'dart:math' as math;
import 'dart:ui';
import 'sketch_models.dart';

enum ModelOperationKind { extrude, circularCut }

class ModelOperation {
  const ModelOperation({
    required this.id,
    required this.kind,
    required this.profileId,
    required this.depth,
    required this.createdAt,
    this.name,
    this.suppressed = false,
  });
  final String id;
  final ModelOperationKind kind;
  final String profileId;
  final double depth;
  final DateTime createdAt;
  final String? name;
  final bool suppressed;
  String get displayName =>
      name ?? (kind == ModelOperationKind.extrude ? 'Extrude' : 'Circular cut');
  ModelOperation copyWith({double? depth, String? name, bool? suppressed}) =>
      ModelOperation(
        id: id,
        kind: kind,
        profileId: profileId,
        depth: depth ?? this.depth,
        createdAt: createdAt,
        name: name ?? this.name,
        suppressed: suppressed ?? this.suppressed,
      );
  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'profileId': profileId,
        'depth': depth,
        'createdAt': createdAt.toIso8601String(),
        'name': name,
        'suppressed': suppressed,
      };
  factory ModelOperation.fromJson(Map<String, Object?> json) => ModelOperation(
        id: json['id']! as String,
        kind: ModelOperationKind.values.byName(json['kind']! as String),
        profileId: json['profileId']! as String,
        depth: (json['depth']! as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt']! as String),
        name: json['name'] as String?,
        suppressed: (json['suppressed'] as bool?) ?? false,
      );
}

class ModelDocument {
  const ModelDocument({this.operations = const []});
  final List<ModelOperation> operations;
  Map<String, Object> toJson() =>
      {'operations': operations.map((item) => item.toJson()).toList()};
  factory ModelDocument.fromJson(Map<String, Object?>? json) => ModelDocument(
      operations: (json?['operations'] as List<Object?>? ?? const [])
          .map((item) => ModelOperation.fromJson(item! as Map<String, Object?>))
          .toList());
  ModelDocument add(ModelOperation operation) =>
      ModelDocument(operations: [...operations, operation]);
  ModelDocument replace(ModelOperation operation) => ModelDocument(
      operations: operations
          .map((item) => item.id == operation.id ? operation : item)
          .toList());
  ModelDocument remove(String id) => ModelDocument(
      operations: operations.where((item) => item.id != id).toList());
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
      required this.cuts});
  final Offset origin;
  final double width;
  final double height;
  final double depth;
  final List<CircularCut> cuts;
  double get volume =>
      width * height * depth -
      cuts.fold(
          0, (sum, cut) => sum + math.pi * cut.radius * cut.radius * depth);
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
    final cuts = <CircularCut>[];
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
      }
    }
    if (base == null || depth == null) return null;
    final rect = Rect.fromPoints(base.start, base.end);
    return EvaluatedSolid(
        origin: rect.topLeft,
        width: rect.width,
        height: rect.height,
        depth: depth,
        cuts: cuts);
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
    if (solid.cuts.isEmpty) return _cuboid(solid);
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
              return solid.cuts
                  .every((cut) => (point - cut.center).distance >= cut.radius);
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
