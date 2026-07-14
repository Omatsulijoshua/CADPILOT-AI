class SpatialPlacement {
  const SpatialPlacement({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.source,
    required this.plane,
    required this.widthMm,
    required this.heightMm,
    required this.depthMm,
    required this.offsetXMm,
    required this.offsetYMm,
    required this.offsetZMm,
    required this.rotationDegrees,
    this.isLocked = false,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final String source;
  final String plane;
  final double widthMm;
  final double heightMm;
  final double depthMm;
  final double offsetXMm;
  final double offsetYMm;
  final double offsetZMm;
  final double rotationDegrees;
  final bool isLocked;

  static const double trueScale = 1.0;

  SpatialPlacement copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    String? source,
    String? plane,
    double? widthMm,
    double? heightMm,
    double? depthMm,
    double? offsetXMm,
    double? offsetYMm,
    double? offsetZMm,
    double? rotationDegrees,
    bool? isLocked,
  }) =>
      SpatialPlacement(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        source: source ?? this.source,
        plane: plane ?? this.plane,
        widthMm: widthMm ?? this.widthMm,
        heightMm: heightMm ?? this.heightMm,
        depthMm: depthMm ?? this.depthMm,
        offsetXMm: offsetXMm ?? this.offsetXMm,
        offsetYMm: offsetYMm ?? this.offsetYMm,
        offsetZMm: offsetZMm ?? this.offsetZMm,
        rotationDegrees: rotationDegrees ?? this.rotationDegrees,
        isLocked: isLocked ?? this.isLocked,
      );
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'source': source,
        'plane': plane,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'depthMm': depthMm,
        'offsetXMm': offsetXMm,
        'offsetYMm': offsetYMm,
        'offsetZMm': offsetZMm,
        'rotationDegrees': rotationDegrees,
        'scale': trueScale,
        'isLocked': isLocked,
      };

  factory SpatialPlacement.fromJson(Map<String, Object?> json) =>
      SpatialPlacement(
        id: json['id']! as String,
        name: json['name'] as String? ?? 'Placement',
        createdAt: DateTime.parse(json['createdAt']! as String),
        source: json['source'] as String? ?? 'manual',
        plane: json['plane'] as String? ?? 'floor',
        widthMm: (json['widthMm'] as num?)?.toDouble() ?? 0,
        heightMm: (json['heightMm'] as num?)?.toDouble() ?? 0,
        depthMm: (json['depthMm'] as num?)?.toDouble() ?? 0,
        offsetXMm: (json['offsetXMm'] as num?)?.toDouble() ?? 0,
        offsetYMm: (json['offsetYMm'] as num?)?.toDouble() ?? 0,
        offsetZMm: (json['offsetZMm'] as num?)?.toDouble() ?? 0,
        rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
        isLocked: json['isLocked'] as bool? ?? false,
      );
}
