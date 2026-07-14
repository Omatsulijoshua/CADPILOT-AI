import 'dart:math' as math;

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

class NativeSpatialTransform {
  NativeSpatialTransform._({
    required this.matrixColumnMajor,
    required this.widthMeters,
    required this.heightMeters,
    required this.depthMeters,
  });

  final List<double> matrixColumnMajor;
  final double widthMeters;
  final double heightMeters;
  final double depthMeters;

  factory NativeSpatialTransform.forFloorPlacement(SpatialPlacement value) {
    if (value.plane != 'floor') {
      throw ArgumentError.value(value.plane, 'plane',
          'A floor anchor transform requires floor placement.');
    }
    final radians = value.rotationDegrees * math.pi / 180;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    return NativeSpatialTransform._(
      matrixColumnMajor: List<double>.unmodifiable(<num>[
        cosine,
        0,
        -sine,
        0,
        0,
        1,
        0,
        0,
        sine,
        0,
        cosine,
        0,
        value.offsetXMm / 1000,
        value.offsetZMm / 1000,
        -value.offsetYMm / 1000,
        1,
      ].map((value) => value.toDouble())),
      widthMeters: value.widthMm / 1000,
      heightMeters: value.heightMm / 1000,
      depthMeters: value.depthMm / 1000,
    );
  }
}

class NativeFloorAnchorRequest {
  NativeFloorAnchorRequest._({
    required this.placementId,
    required this.transform,
  });

  final String placementId;
  final NativeSpatialTransform transform;

  factory NativeFloorAnchorRequest.fromPlacement(SpatialPlacement placement) {
    if (placement.source != 'camera_ar') {
      throw StateError(
          'Only a preflight-approved camera AR placement can request an anchor.');
    }
    if (placement.anchor != null) {
      throw StateError('The placement already has a native anchor.');
    }
    return NativeFloorAnchorRequest._(
      placementId: placement.id,
      transform: placement.toFloorAnchorTransform(),
    );
  }

  Map<String, Object?> toMap() => {
        'placementId': placementId,
        'plane': 'floor',
        'scale': SpatialPlacement.trueScale,
        'matrixColumnMajor': transform.matrixColumnMajor,
        'widthMeters': transform.widthMeters,
        'heightMeters': transform.heightMeters,
        'depthMeters': transform.depthMeters,
      };
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
  NativeSpatialTransform toFloorAnchorTransform() =>
      NativeSpatialTransform.forFloorPlacement(this);
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
