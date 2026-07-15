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

class SpatialPointCloudFrame {
  const SpatialPointCloudFrame({
    required this.sessionId,
    required this.frameId,
    required this.capturedAt,
    required this.coordinateSystem,
    required this.points,
  });

  final String sessionId;
  final String frameId;
  final DateTime capturedAt;
  final String coordinateSystem;
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
      points: points,
    );
  }
}

class SpatialDepthCaptureService {
  const SpatialDepthCaptureService({
    MethodChannel channel = const MethodChannel('cadpilot/spatial'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<SpatialPointCloudFrame?> capture({
    required String sessionId,
    required SpatialCapabilities capabilities,
  }) async {
    final normalizedSessionId = _requiredId(sessionId, 'sessionId');
    final depthMethod = capabilities.captureMethod == 'lidar' ||
        capabilities.captureMethod == 'depth_camera';
    if (!capabilities.sceneDepthSupported || !depthMethod) {
      throw StateError(
        'Native depth capability is required before point-cloud capture.',
      );
    }
    if (kIsWeb) return null;
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
    throw FormatException('Spatial point $field must be numeric.');
  }
  final result = value.toDouble();
  if (!result.isFinite) {
    throw FormatException('Spatial point $field must be finite.');
  }
  return result;
}

String _requiredId(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Spatial frame requires a non-empty $field.');
  }
  return value.trim();
}
