import 'ai_commands.dart';
import 'model_3d.dart';
import 'sketch_models.dart';
import 'spatial_models.dart';

enum SessionKind { signedIn, guest }

class Session {
  const Session({required this.kind, required this.displayName, this.email});
  final SessionKind kind;
  final String displayName;
  final String? email;
  Map<String, Object?> toJson() =>
      {'kind': kind.name, 'displayName': displayName, 'email': email};
  factory Session.fromJson(Map<String, Object?> json) => Session(
      kind: SessionKind.values.byName(json['kind']! as String),
      displayName: json['displayName']! as String,
      email: json['email'] as String?);
}

enum SyncState { localOnly, pending, synced }

class CadProject {
  const CadProject({
    required this.id,
    required this.name,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.syncState,
    this.sketch = const SketchDocument(),
    this.model = const ModelDocument(),
    this.aiHistory = const [],
    this.spatialPlacements = const [],
  });
  final String id;
  final String name;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final SyncState syncState;
  final SketchDocument sketch;
  final ModelDocument model;
  final List<AiCommandRecord> aiHistory;
  final List<SpatialPlacement> spatialPlacements;

  CadProject copyWith(
          {String? name,
          String? note,
          SyncState? syncState,
          SketchDocument? sketch,
          ModelDocument? model,
          List<AiCommandRecord>? aiHistory,
          List<SpatialPlacement>? spatialPlacements}) =>
      CadProject(
        id: id,
        name: name ?? this.name,
        note: note ?? this.note,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
        revision: revision + 1,
        syncState: syncState ?? SyncState.pending,
        sketch: sketch ?? this.sketch,
        model: model ?? this.model,
        aiHistory: aiHistory ?? this.aiHistory,
        spatialPlacements: spatialPlacements ?? this.spatialPlacements,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'revision': revision,
        'syncState': syncState.name,
        'sketch': sketch.toJson(),
        'model': model.toJson(),
        'aiHistory': aiHistory.map((item) => item.toJson()).toList(),
        'spatialPlacements':
            spatialPlacements.map((item) => item.toJson()).toList(),
      };

  factory CadProject.fromJson(Map<String, Object?> json) => CadProject(
        id: json['id']! as String,
        name: json['name']! as String,
        note: (json['note'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
        revision: json['revision']! as int,
        syncState: SyncState.values.byName(json['syncState']! as String),
        sketch:
            SketchDocument.fromJson(json['sketch'] as Map<String, Object?>?),
        model: ModelDocument.fromJson(json['model'] as Map<String, Object?>?),
        aiHistory: (json['aiHistory'] as List<Object?>? ?? const [])
            .map((item) =>
                AiCommandRecord.fromJson(item! as Map<String, Object?>))
            .toList(),
        spatialPlacements:
            (json['spatialPlacements'] as List<Object?>? ?? const [])
                .map((item) =>
                    SpatialPlacement.fromJson(item! as Map<String, Object?>))
                .toList(),
      );
}
