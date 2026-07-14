enum SessionKind { signedIn, guest }

class Session {
  const Session({required this.kind, required this.displayName, this.email});
  final SessionKind kind;
  final String displayName;
  final String? email;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'displayName': displayName,
        'email': email,
      };

  factory Session.fromJson(Map<String, Object?> json) => Session(
        kind: SessionKind.values.byName(json['kind']! as String),
        displayName: json['displayName']! as String,
        email: json['email'] as String?,
      );
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
  });

  final String id;
  final String name;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final SyncState syncState;

  CadProject copyWith({String? name, String? note, SyncState? syncState}) =>
      CadProject(
        id: id,
        name: name ?? this.name,
        note: note ?? this.note,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
        revision: revision + 1,
        syncState: syncState ?? SyncState.pending,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'revision': revision,
        'syncState': syncState.name,
      };

  factory CadProject.fromJson(Map<String, Object?> json) => CadProject(
        id: json['id']! as String,
        name: json['name']! as String,
        note: (json['note'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
        revision: json['revision']! as int,
        syncState: SyncState.values.byName(json['syncState']! as String),
      );
}
