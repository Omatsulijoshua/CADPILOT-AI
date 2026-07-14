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

class StlExporter {
  const StlExporter();
  String export(EvaluatedSolid solid, {String name = 'cadpilot_part'}) {
    if (solid.cuts.isNotEmpty) {
      throw UnsupportedError(
          'STL export for cut solids is not enabled in this Phase 3 increment.');
    }
    final x = solid.width, y = solid.height, z = solid.depth;
    final vertices = <List<double>>[
      [0, 0, 0],
      [x, 0, 0],
      [x, y, 0],
      [0, y, 0],
      [0, 0, z],
      [x, 0, z],
      [x, y, z],
      [0, y, z]
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
    final buffer = StringBuffer('solid $name\n');
    for (final face in faces) {
      final a = vertices[face[0]], b = vertices[face[1]], c = vertices[face[2]];
      final ux = b[0] - a[0],
          uy = b[1] - a[1],
          uz = b[2] - a[2],
          vx = c[0] - a[0],
          vy = c[1] - a[1],
          vz = c[2] - a[2];
      final nx = uy * vz - uz * vy,
          ny = uz * vx - ux * vz,
          nz = ux * vy - uy * vx;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      buffer.writeln(
          '  facet normal ${nx / length} ${ny / length} ${nz / length}');
      buffer.writeln('    outer loop');
      for (final index in face) {
        final v = vertices[index];
        buffer.writeln('      vertex ${v[0]} ${v[1]} ${v[2]}');
      }
      buffer.writeln('    endloop\n  endfacet');
    }
    buffer.writeln('endsolid $name');
    return buffer.toString();
  }
}
