import 'dart:math' as math;

import 'spatial_depth_capture.dart';
import 'spatial_point_processing.dart';
import 'spatial_registration.dart';

enum SpatialPlanarAxis { x, y, z, none }

class SpatialScanMeasurements {
  const SpatialScanMeasurements({
    required this.sessionId,
    required this.sourceFrameIds,
    required this.pointCount,
    required this.minimumMeters,
    required this.maximumMeters,
    required this.centroidMeters,
    required this.widthMm,
    required this.heightMm,
    required this.depthMm,
    required this.diagonalMm,
    required this.meanConfidence,
    required this.resolutionMm,
    required this.planarAxis,
  });

  final String sessionId;
  final List<String> sourceFrameIds;
  final int pointCount;
  final SpatialVector3 minimumMeters;
  final SpatialVector3 maximumMeters;
  final SpatialVector3 centroidMeters;
  final double widthMm;
  final double heightMm;
  final double depthMm;
  final double diagonalMm;
  final double meanConfidence;
  final double resolutionMm;
  final SpatialPlanarAxis planarAxis;

  bool get isPlanar => planarAxis != SpatialPlanarAxis.none;
  String get accuracyLabel =>
      'Advisory scan bounds; not a certified measurement.';
}

class SpatialMeasurementExtractor {
  const SpatialMeasurementExtractor();

  SpatialScanMeasurements extract(ProcessedSpatialPointCloud cloud) {
    cloud.settings.validate();
    if (cloud.points.length < 3) {
      throw const FormatException(
        'Spatial measurement extraction requires at least three points.',
      );
    }
    if (cloud.points.length > maxRegisteredSpatialPoints) {
      throw const FormatException(
        'Spatial measurement extraction exceeds the point safety limit.',
      );
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var maxZ = double.negativeInfinity;
    var sumX = 0.0;
    var sumY = 0.0;
    var sumZ = 0.0;
    var sumConfidence = 0.0;

    for (final point in cloud.points) {
      if (!point.x.isFinite ||
          !point.y.isFinite ||
          !point.z.isFinite ||
          !point.confidence.isFinite ||
          point.confidence < 0 ||
          point.confidence > 1) {
        throw const FormatException(
          'Spatial measurements require finite validated point samples.',
        );
      }
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      minZ = math.min(minZ, point.z);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
      maxZ = math.max(maxZ, point.z);
      sumX += point.x;
      sumY += point.y;
      sumZ += point.z;
      sumConfidence += point.confidence;
    }

    final width = maxX - minX;
    final height = maxY - minY;
    final depth = maxZ - minZ;
    final diagonal = math.sqrt(
      width * width + height * height + depth * depth,
    );
    if (!diagonal.isFinite || diagonal <= 0) {
      throw const FormatException(
        'Spatial measurements require non-degenerate point bounds.',
      );
    }
    final planarThreshold = cloud.settings.voxelSizeMeters * 2;
    final extents = [width, height, depth];
    final thinAxes = <int>[
      for (var index = 0; index < extents.length; index++)
        if (extents[index] <= planarThreshold) index,
    ];
    if (thinAxes.length > 1) {
      throw const FormatException(
        'Spatial measurements reject line-like or point-like bounds.',
      );
    }
    final planarAxis = thinAxes.length == 1
        ? SpatialPlanarAxis.values[thinAxes.single]
        : SpatialPlanarAxis.none;
    final count = cloud.points.length;

    return SpatialScanMeasurements(
      sessionId: cloud.sessionId,
      sourceFrameIds: cloud.sourceFrameIds,
      pointCount: count,
      minimumMeters: SpatialVector3(minX, minY, minZ),
      maximumMeters: SpatialVector3(maxX, maxY, maxZ),
      centroidMeters: SpatialVector3(
        sumX / count,
        sumY / count,
        sumZ / count,
      ),
      widthMm: width * 1000,
      heightMm: height * 1000,
      depthMm: depth * 1000,
      diagonalMm: diagonal * 1000,
      meanConfidence: sumConfidence / count,
      resolutionMm: cloud.settings.voxelSizeMeters * 1000,
      planarAxis: planarAxis,
    );
  }
}
