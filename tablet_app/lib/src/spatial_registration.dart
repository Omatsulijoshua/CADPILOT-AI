import 'spatial_depth_capture.dart';

const int maxRegisteredSpatialPoints = 500000;

class RegisteredSpatialPointCloud {
  const RegisteredSpatialPointCloud({
    required this.sessionId,
    required this.startedAt,
    required this.endedAt,
    required this.sourceFrameIds,
    required this.points,
  });

  final String sessionId;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<String> sourceFrameIds;
  final List<SpatialPointSample> points;
}

class SpatialFrameRegistration {
  const SpatialFrameRegistration();

  RegisteredSpatialPointCloud register(List<SpatialPointCloudFrame> frames) {
    if (frames.isEmpty) {
      throw const FormatException(
        'Spatial registration requires at least one frame.',
      );
    }
    final sessionId = frames.first.sessionId;
    final frameIds = <String>{};
    var pointCount = 0;
    DateTime? previousCapture;
    for (final frame in frames) {
      if (frame.sessionId != sessionId) {
        throw const FormatException(
          'Spatial registration cannot mix capture sessions.',
        );
      }
      if (!frameIds.add(frame.frameId)) {
        throw const FormatException(
          'Spatial registration cannot contain duplicate frame IDs.',
        );
      }
      if (previousCapture != null &&
          frame.capturedAt.isBefore(previousCapture)) {
        throw const FormatException(
          'Spatial registration frames must be time ordered.',
        );
      }
      previousCapture = frame.capturedAt;
      pointCount += frame.points.length;
      if (pointCount > maxRegisteredSpatialPoints) {
        throw const FormatException(
          'Spatial registration exceeds the aggregate point limit.',
        );
      }
    }

    final points = <SpatialPointSample>[];
    for (final frame in frames) {
      points.addAll(frame.points.map(frame.sensorPose.transform));
    }
    return RegisteredSpatialPointCloud(
      sessionId: sessionId,
      startedAt: frames.first.capturedAt,
      endedAt: frames.last.capturedAt,
      sourceFrameIds: List.unmodifiable(frameIds),
      points: List.unmodifiable(points),
    );
  }
}
