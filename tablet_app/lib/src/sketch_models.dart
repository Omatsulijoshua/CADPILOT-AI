import 'dart:math' as math;
import 'dart:ui';

enum SketchTool { select, line, rectangle, circle }

enum SketchEntityKind { line, rectangle, circle }

class SketchEntity {
  const SketchEntity(
      {required this.id,
      required this.kind,
      required this.start,
      required this.end});
  final String id;
  final SketchEntityKind kind;
  final Offset start;
  final Offset end;

  SketchEntity copyWith({Offset? start, Offset? end}) => SketchEntity(
      id: id, kind: kind, start: start ?? this.start, end: end ?? this.end);
  SketchEntity translated(Offset delta) =>
      copyWith(start: start + delta, end: end + delta);

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
        final radius = (end - start).distance;
        return ((point - start).distance - radius).abs() <= tolerance;
    }
  }

  Map<String, Object> toJson() => {
        'id': id,
        'kind': kind.name,
        'start': [start.dx, start.dy],
        'end': [end.dx, end.dy]
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
    );
  }
}

class SketchDocument {
  const SketchDocument({this.entities = const []});
  final List<SketchEntity> entities;
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
    commit(_document.copyWith(
        entities: _document.entities
            .map((entity) =>
                entity.id == selectedId ? entity.translated(delta) : entity)
            .toList()));
  }

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
