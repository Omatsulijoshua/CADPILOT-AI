import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'spatial.dart';

const int maxSpatialPointsPerFrame = 250000;
const String spatialCoordinateSystem = 'right_handed_y_up_meters';

class SpatialPointSample {
  const SpatialPointSample({
    required this.x,
    required this.y,
    required this.z,
    required this.confidence,
  });

  final double x;
  final double y;
  final double z;
  final double confidence;

  factory SpatialPointSample.fromMap(Map<Object?, Object?> value) {
    final x = _finiteDouble(value['x'], 'x');
    final y = _finiteDouble(value['y'], 'y');
    final z = _finiteDouble(value['z'], 'z');
    final confidence = _finiteDouble(value['confidence'], 'confidence');
    if (confidence < 0 || confidence > 1) {
      throw const FormatException(
        'Spatial point confidence must be between 0 and 1.',
      );
    }
    if (x.abs() > 1000 || y.abs() > 1000 || z.abs() > 1000) {
      throw const FormatException(
        'Spatial point exceeds the 1000 meter safety bound.',
      );
    }
    return SpatialPointSample(
      x: x,
      y: y,
      z: z,
      confidence: confidence,
    );
  }
}

class SpatialVector3 {
  const SpatialVector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  factory SpatialVector3.fromMap(Map<Object?, Object?> value) => SpatialVector3(
        _finiteDouble(value['x'], 'pose translation x'),
        _finiteDouble(value['y'], 'pose translation y'),
        _finiteDouble(value['z'], 'pose translation z'),
      );
}

class SpatialQuaternion {
  const SpatialQuaternion(this.x, this.y, this.z, this.w);

  final double x;
  final double y;
  final double z;
  final double w;

  factory SpatialQuaternion.fromMap(Map<Object?, Object?> value) {
    final quaternion = SpatialQuaternion(
      _finiteDouble(value['x'], 'pose rotation x'),
      _finiteDouble(value['y'], 'pose rotation y'),
      _finiteDouble(value['z'], 'pose rotation z'),
      _finiteDouble(value['w'], 'pose rotation w'),
    );
    final magnitudeSquared = quaternion.x * quaternion.x +
        quaternion.y * quaternion.y +
        quaternion.z * quaternion.z +
        quaternion.w * quaternion.w;
    if ((magnitudeSquared - 1).abs() > 0.01) {
      throw const FormatException(
        'Spatial pose rotation must be a normalized quaternion.',
      );
    }
    return quaternion;
  }
}

class SpatialSensorPose {
  const SpatialSensorPose({
    required this.translation,
    required this.rotation,
  });

  final SpatialVector3 translation;
  final SpatialQuaternion rotation;

  static const identity = SpatialSensorPose(
    translation: SpatialVector3(0, 0, 0),
    rotation: SpatialQuaternion(0, 0, 0, 1),
  );

  factory SpatialSensorPose.fromMap(Map<Object?, Object?> value) {
    final translationValue = value['translation'];
    final rotationValue = value['rotation'];
    if (translationValue is! Map<Object?, Object?> ||
        rotationValue is! Map<Object?, Object?>) {
      throw const FormatException(
        'Spatial frame pose requires translation and rotation maps.',
      );
    }
    final translation = SpatialVector3.fromMap(translationValue);
    if (translation.x.abs() > 1000 ||
        translation.y.abs() > 1000 ||
        translation.z.abs() > 1000) {
      throw const FormatException(
        'Spatial pose translation exceeds the 1000 meter safety bound.',
      );
    }
    return SpatialSensorPose(
      translation: translation,
      rotation: SpatialQuaternion.fromMap(rotationValue),
    );
  }

  SpatialPointSample transform(SpatialPointSample point) {
    final q = rotation;
    final tx = 2 * (q.y * point.z - q.z * point.y);
    final ty = 2 * (q.z * point.x - q.x * point.z);
    final tz = 2 * (q.x * point.y - q.y * point.x);
    return SpatialPointSample(
      x: point.x + q.w * tx + (q.y * tz - q.z * ty) + translation.x,
      y: point.y + q.w * ty + (q.z * tx - q.x * tz) + translation.y,
      z: point.z + q.w * tz + (q.x * ty - q.y * tx) + translation.z,
      confidence: point.confidence,
    );
  }
}

class SpatialPointCloudFrame {
  const SpatialPointCloudFrame({
    required this.sessionId,
    required this.frameId,
    required this.capturedAt,
    required this.coordinateSystem,
    required this.sensorPose,
    required this.points,
  });

  final String sessionId;
  final String frameId;
  final DateTime capturedAt;
  final String coordinateSystem;
  final SpatialSensorPose sensorPose;
  final List<SpatialPointSample> points;

  factory SpatialPointCloudFrame.fromMap(Map<Object?, Object?> value) {
    final sessionId = _requiredId(value['sessionId'], 'sessionId');
    final frameId = _requiredId(value['frameId'], 'frameId');
    final capturedAtValue = value['capturedAt'] as String?;
    final capturedAt =
        capturedAtValue == null ? null : DateTime.tryParse(capturedAtValue);
    if (capturedAt == null || !capturedAt.isUtc) {
      throw const FormatException(
        'Spatial frame capturedAt must be an ISO-8601 UTC timestamp.',
      );
    }
    final coordinateSystem = value['coordinateSystem'] as String?;
    if (coordinateSystem != spatialCoordinateSystem) {
      throw const FormatException(
        'Spatial frame uses an unsupported coordinate system.',
      );
    }
    final sensorPoseValue = value['sensorPose'];
    if (sensorPoseValue is! Map<Object?, Object?>) {
      throw const FormatException(
          'Spatial frame requires sensor pose metadata.');
    }
    final sensorPose = SpatialSensorPose.fromMap(sensorPoseValue);
    final rawPoints = value['points'];
    if (rawPoints is! List<Object?> || rawPoints.length < 3) {
      throw const FormatException(
        'Spatial frame requires at least three point samples.',
      );
    }
    if (rawPoints.length > maxSpatialPointsPerFrame) {
      throw const FormatException(
        'Spatial frame exceeds the point-count safety limit.',
      );
    }
    final points = rawPoints.map((point) {
      if (point is! Map<Object?, Object?>) {
        throw const FormatException('Spatial point sample must be a map.');
      }
      return SpatialPointSample.fromMap(point);
    }).toList(growable: false);
    return SpatialPointCloudFrame(
      sessionId: sessionId,
      frameId: frameId,
      capturedAt: capturedAt,
      coordinateSystem: spatialCoordinateSystem,
      sensorPose: sensorPose,
      points: points,
    );
  }
}

class SpatialDepthCaptureService {
  const SpatialDepthCaptureService({
    MethodChannel channel = const MethodChannel('cadpilot/spatial'),
    bool isWeb = kIsWeb,
  })  : _channel = channel,
        _isWeb = isWeb;

  final MethodChannel _channel;
  final bool _isWeb;

  Future<SpatialPointCloudFrame?> capture({
    required String sessionId,
    required SpatialCapabilities capabilities,
  }) async {
    final normalizedSessionId = _requiredId(sessionId, 'sessionId');
    final depthMethod = capabilities.captureMethod == 'lidar' ||
        capabilities.captureMethod == 'depth_camera';
    if (!capabilities.depthCaptureReady || !depthMethod) {
      throw StateError(
        'CadPilot native depth capture must be available before point-cloud capture.',
      );
    }
    if (_isWeb) return null;
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'captureDepthFrame',
        {
          'sessionId': normalizedSessionId,
          'coordinateSystem': spatialCoordinateSystem,
          'maxPoints': maxSpatialPointsPerFrame,
        },
      );
      if (value == null) return null;
      final frame = SpatialPointCloudFrame.fromMap(value);
      if (frame.sessionId != normalizedSessionId) {
        throw const FormatException(
          'Spatial frame does not match the active capture session.',
        );
      }
      return frame;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

double _finiteDouble(Object? value, String field) {
  if (value is! num) {
    throw FormatException('Spatial value $field must be numeric.');
  }
  final result = value.toDouble();
  if (!result.isFinite) {
    throw FormatException('Spatial value $field must be finite.');
  }
  return result;
}

String _requiredId(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Spatial frame requires a non-empty $field.');
  }
  return value.trim();
}
