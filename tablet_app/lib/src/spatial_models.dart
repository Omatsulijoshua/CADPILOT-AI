enum SpatialTrackingState { tracking, limited, paused, stopped }

class SpatialAnchor {
  const SpatialAnchor({
    required this.id,
    required this.platform,
    required this.trackingState,
    required this.updatedAt,
  });

  final String id;
  final String platform;
  final SpatialTrackingState trackingState;
  final DateTime updatedAt;

  SpatialAnchor copyWith({
    SpatialTrackingState? trackingState,
    DateTime? updatedAt,
  }) =>
      SpatialAnchor(
        id: id,
        platform: platform,
        trackingState: trackingState ?? this.trackingState,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'platform': platform,
        'trackingState': trackingState.name,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SpatialAnchor.fromJson(Map<String, Object?> json) => SpatialAnchor(
        id: json['id']! as String,
        platform: json['platform'] as String? ?? 'unknown',
        trackingState: SpatialTrackingState.values.firstWhere(
          (value) => value.name == json['trackingState'],
          orElse: () => SpatialTrackingState.stopped,
        ),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
      );
}

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
    this.anchor,
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
  final SpatialAnchor? anchor;

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
    SpatialAnchor? anchor,
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
        anchor: anchor ?? this.anchor,
      );
  SpatialPlacement attachAnchor(SpatialAnchor value) => copyWith(anchor: value);

  SpatialPlacement detachAnchor() => SpatialPlacement(
        id: id,
        name: name,
        createdAt: createdAt,
        source: source,
        plane: plane,
        widthMm: widthMm,
        heightMm: heightMm,
        depthMm: depthMm,
        offsetXMm: offsetXMm,
        offsetYMm: offsetYMm,
        offsetZMm: offsetZMm,
        rotationDegrees: rotationDegrees,
        isLocked: false,
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
        'anchor': anchor?.toJson(),
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
        anchor: json['anchor'] is Map<String, Object?>
            ? SpatialAnchor.fromJson(json['anchor']! as Map<String, Object?>)
            : null,
      );
}
