import 'dart:math' as math;
import 'dart:ui';

enum SketchTool { select, line, rectangle, circle, arc }

enum SketchEntityKind { line, rectangle, circle, arc }

enum SketchConstraint { horizontal, vertical }

enum SketchSolveState { underConstrained, fullyConstrained, conflicting }

class SketchEntity {
  const SketchEntity(
      {required this.id,
      required this.kind,
      required this.start,
      required this.end,
      this.constraint,
      this.dimensionLocked = false});
  final String id;
  final SketchEntityKind kind;
  final Offset start;
  final Offset end;
  final SketchConstraint? constraint;
  final bool dimensionLocked;

  SketchEntity copyWith(
          {Offset? start,
          Offset? end,
          SketchConstraint? constraint,
          bool clearConstraint = false,
          bool? dimensionLocked}) =>
      SketchEntity(
        id: id,
        kind: kind,
        start: start ?? this.start,
        end: end ?? this.end,
        constraint: clearConstraint ? null : constraint ?? this.constraint,
        dimensionLocked: dimensionLocked ?? this.dimensionLocked,
      );
  SketchEntity translated(Offset delta) =>
      copyWith(start: start + delta, end: end + delta);
  double get primaryDimension => switch (kind) {
        SketchEntityKind.line => (end - start).distance,
        SketchEntityKind.rectangle => (end.dx - start.dx).abs(),
        SketchEntityKind.circle ||
        SketchEntityKind.arc =>
          (end - start).distance,
      };
  double? get secondaryDimension =>
      kind == SketchEntityKind.rectangle ? (end.dy - start.dy).abs() : null;
  String get measurementLabel => switch (kind) {
        SketchEntityKind.line => '${primaryDimension.toStringAsFixed(1)} mm',
        SketchEntityKind.rectangle =>
          '${primaryDimension.toStringAsFixed(1)} x ${secondaryDimension!.toStringAsFixed(1)} mm',
        SketchEntityKind.circle =>
          'R ${primaryDimension.toStringAsFixed(1)} mm',
        SketchEntityKind.arc =>
          'Arc R ${primaryDimension.toStringAsFixed(1)} mm',
      };

  SketchEntity withDimensions(double primary, [double? secondary]) {
    final safePrimary = primary.clamp(0.1, 100000.0);
    switch (kind) {
      case SketchEntityKind.line:
        final vector = end - start;
        final direction = vector.distance == 0
            ? const Offset(1, 0)
            : vector / vector.distance;
        return copyWith(
            end: start + direction * safePrimary, dimensionLocked: true);
      case SketchEntityKind.rectangle:
        final xSign = end.dx < start.dx ? -1.0 : 1.0;
        final ySign = end.dy < start.dy ? -1.0 : 1.0;
        final height = (secondary ?? secondaryDimension ?? safePrimary)
            .clamp(0.1, 100000.0);
        return copyWith(
            end: Offset(
                start.dx + safePrimary * xSign, start.dy + height * ySign),
            dimensionLocked: true);
      case SketchEntityKind.circle:
      case SketchEntityKind.arc:
        final vector = end - start;
        final direction = vector.distance == 0
            ? const Offset(1, 0)
            : vector / vector.distance;
        return copyWith(
            end: start + direction * safePrimary, dimensionLocked: true);
    }
  }

  SketchEntity constrained(SketchConstraint value) {
    if (kind != SketchEntityKind.line) return this;
    return switch (value) {
      SketchConstraint.horizontal =>
        copyWith(end: Offset(end.dx, start.dy), constraint: value),
      SketchConstraint.vertical =>
        copyWith(end: Offset(start.dx, end.dy), constraint: value),
    };
  }

  bool hitTest(Offset point, {double tolerance = 14}) {
    switch (kind) {
      case SketchEntityKind.line:
        final lengthSquared = (end - start).distanceSquared;
        if (lengthSquared == 0) return (point - start).distance <= tolerance;
        final t = (((point.dx - start.dx) * (end.dx - start.dx) +
                    (point.dy - start.dy) * (end.dy - start.dy)) /
                lengthSquared)
            .clamp(0.0, 1.0);
        final closest = Offset(start.dx + (end.dx - start.dx) * t,
            start.dy + (end.dy - start.dy) * t);
        return (point - closest).distance <= tolerance;
      case SketchEntityKind.rectangle:
        final rect = Rect.fromPoints(start, end).inflate(tolerance);
        final inner = Rect.fromPoints(start, end).deflate(tolerance);
        return rect.contains(point) &&
            (inner.width <= 0 || inner.height <= 0 || !inner.contains(point));
      case SketchEntityKind.circle:
      case SketchEntityKind.arc:
        final radius = (end - start).distance;
        return ((point - start).distance - radius).abs() <= tolerance;
    }
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'start': [start.dx, start.dy],
        'end': [end.dx, end.dy],
        if (constraint != null) 'constraint': constraint!.name,
        'dimensionLocked': dimensionLocked,
      };
  factory SketchEntity.fromJson(Map<String, Object?> json) {
    final start = json['start']! as List<Object?>;
    final end = json['end']! as List<Object?>;
    return SketchEntity(
      id: json['id']! as String,
      kind: SketchEntityKind.values.byName(json['kind']! as String),
      start:
          Offset((start[0]! as num).toDouble(), (start[1]! as num).toDouble()),
      end: Offset((end[0]! as num).toDouble(), (end[1]! as num).toDouble()),
      constraint: json['constraint'] == null
          ? null
          : SketchConstraint.values.byName(json['constraint']! as String),
      dimensionLocked: (json['dimensionLocked'] as bool?) ?? false,
    );
  }
}

class SketchDocument {
  const SketchDocument({this.entities = const []});
  final List<SketchEntity> entities;
  SketchSolveState get solveState {
    for (final entity in entities) {
      if (entity.constraint == SketchConstraint.horizontal &&
          (entity.end.dy - entity.start.dy).abs() > 0.001) {
        return SketchSolveState.conflicting;
      }
      if (entity.constraint == SketchConstraint.vertical &&
          (entity.end.dx - entity.start.dx).abs() > 0.001) {
        return SketchSolveState.conflicting;
      }
    }
    if (entities.isNotEmpty &&
        entities.every((entity) =>
            entity.dimensionLocked &&
            (entity.kind != SketchEntityKind.line ||
                entity.constraint != null))) {
      return SketchSolveState.fullyConstrained;
    }
    return SketchSolveState.underConstrained;
  }

  SketchDocument copyWith({List<SketchEntity>? entities}) =>
      SketchDocument(entities: List.unmodifiable(entities ?? this.entities));
  Map<String, Object> toJson() =>
      {'entities': entities.map((entity) => entity.toJson()).toList()};
  factory SketchDocument.fromJson(Map<String, Object?>? json) {
    if (json == null) return const SketchDocument();
    final entities = (json['entities'] as List<Object?>? ?? const [])
        .map((item) => SketchEntity.fromJson(item! as Map<String, Object?>))
        .toList();
    return SketchDocument(entities: entities);
  }
}

class SketchHistory {
  SketchHistory(SketchDocument initial) : _document = initial;
  SketchDocument _document;
  final List<SketchDocument> _undo = [];
  final List<SketchDocument> _redo = [];
  String? selectedId;
  SketchDocument get document => _document;
  SketchEntity? get selected => selectedId == null
      ? null
      : _document.entities
          .where((entity) => entity.id == selectedId)
          .firstOrNull;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void commit(SketchDocument next) {
    if (identical(next, _document)) return;
    _undo.add(_document);
    _document = next;
    _redo.clear();
  }

  void add(SketchEntity entity) =>
      commit(_document.copyWith(entities: [..._document.entities, entity]));
  void selectAt(Offset point) {
    selectedId = _document.entities.reversed
        .where((entity) => entity.hitTest(point))
        .map((entity) => entity.id)
        .firstOrNull;
  }

  void _replaceSelected(SketchEntity Function(SketchEntity) update) {
    if (selectedId == null) return;
    commit(_document.copyWith(
        entities: _document.entities
            .map((entity) => entity.id == selectedId ? update(entity) : entity)
            .toList()));
  }

  void deleteSelected() {
    if (selectedId == null) return;
    commit(_document.copyWith(
        entities: _document.entities
            .where((entity) => entity.id != selectedId)
            .toList()));
    selectedId = null;
  }

  void moveSelected(Offset delta) {
    if (selectedId == null || delta.distanceSquared < math.pow(0.1, 2)) return;
    _replaceSelected((entity) => entity.translated(delta));
  }

  void dimensionSelected(double primary, [double? secondary]) =>
      _replaceSelected((entity) => entity.withDimensions(primary, secondary));
  void constrainSelected(SketchConstraint constraint) =>
      _replaceSelected((entity) => entity.constrained(constraint));
  void undo() {
    if (!canUndo) return;
    _redo.add(_document);
    _document = _undo.removeLast();
    selectedId = null;
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_document);
    _document = _redo.removeLast();
    selectedId = null;
  }
}

class SketchSnapper {
  const SketchSnapper({this.gridSize = 12, this.threshold = 10});
  final double gridSize;
  final double threshold;
  Offset snap(Offset point, SketchDocument document) {
    Offset? nearest;
    var nearestDistance = threshold;
    for (final entity in document.entities) {
      for (final candidate in [entity.start, entity.end]) {
        final distance = (point - candidate).distance;
        if (distance < nearestDistance) {
          nearest = candidate;
          nearestDistance = distance;
        }
      }
    }
    if (nearest != null) return nearest;
    return Offset((point.dx / gridSize).round() * gridSize,
        (point.dy / gridSize).round() * gridSize);
  }
}
