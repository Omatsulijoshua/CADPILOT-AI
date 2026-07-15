import 'spatial_depth_capture.dart';
import 'spatial_registration.dart';

class SpatialPointProcessingSettings {
  const SpatialPointProcessingSettings({
    this.minimumConfidence = 0.5,
    this.voxelSizeMeters = 0.01,
    this.outlierRadiusMeters = 0.02,
    this.minimumNeighbors = 2,
  });

  final double minimumConfidence;
  final double voxelSizeMeters;
  final double outlierRadiusMeters;
  final int minimumNeighbors;

  void validate() {
    if (!minimumConfidence.isFinite ||
        minimumConfidence < 0 ||
        minimumConfidence > 1) {
      throw const FormatException(
        'Minimum point confidence must be between 0 and 1.',
      );
    }
    if (!voxelSizeMeters.isFinite ||
        voxelSizeMeters < 0.001 ||
        voxelSizeMeters > 1) {
      throw const FormatException(
        'Voxel size must be between 0.001 and 1 meter.',
      );
    }
    if (!outlierRadiusMeters.isFinite ||
        outlierRadiusMeters < voxelSizeMeters ||
        outlierRadiusMeters > voxelSizeMeters * 4) {
      throw const FormatException(
        'Outlier radius must be between one and four voxel widths.',
      );
    }
    if (minimumNeighbors < 0 || minimumNeighbors > 26) {
      throw const FormatException(
        'Minimum neighbor count must be between 0 and 26.',
      );
    }
  }
}

class SpatialPointProcessingStats {
  const SpatialPointProcessingStats({
    required this.inputPoints,
    required this.afterConfidenceFilter,
    required this.afterVoxelDownsample,
    required this.outputPoints,
  });

  final int inputPoints;
  final int afterConfidenceFilter;
  final int afterVoxelDownsample;
  final int outputPoints;

  int get removedByConfidence => inputPoints - afterConfidenceFilter;
  int get removedByDownsampling => afterConfidenceFilter - afterVoxelDownsample;
  int get removedAsIsolated => afterVoxelDownsample - outputPoints;
}

class ProcessedSpatialPointCloud {
  const ProcessedSpatialPointCloud({
    required this.sessionId,
    required this.startedAt,
    required this.endedAt,
    required this.sourceFrameIds,
    required this.points,
    required this.settings,
    required this.stats,
  });

  final String sessionId;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<String> sourceFrameIds;
  final List<SpatialPointSample> points;
  final SpatialPointProcessingSettings settings;
  final SpatialPointProcessingStats stats;
}

class SpatialPointCloudProcessor {
  const SpatialPointCloudProcessor();

  ProcessedSpatialPointCloud process(
    RegisteredSpatialPointCloud cloud, {
    SpatialPointProcessingSettings settings =
        const SpatialPointProcessingSettings(),
  }) {
    settings.validate();
    final confident = cloud.points
        .where((point) => point.confidence >= settings.minimumConfidence)
        .toList(growable: false);

    final voxels = <_GridKey, SpatialPointSample>{};
    for (final point in confident) {
      final key = _GridKey.fromPoint(point, settings.voxelSizeMeters);
      final existing = voxels[key];
      if (existing == null || point.confidence > existing.confidence) {
        voxels[key] = point;
      }
    }
    final downsampled = voxels.values.toList(growable: false);
    final output = settings.minimumNeighbors == 0
        ? downsampled
        : _removeIsolated(downsampled, settings);

    return ProcessedSpatialPointCloud(
      sessionId: cloud.sessionId,
      startedAt: cloud.startedAt,
      endedAt: cloud.endedAt,
      sourceFrameIds: cloud.sourceFrameIds,
      points: List.unmodifiable(output),
      settings: settings,
      stats: SpatialPointProcessingStats(
        inputPoints: cloud.points.length,
        afterConfidenceFilter: confident.length,
        afterVoxelDownsample: downsampled.length,
        outputPoints: output.length,
      ),
    );
  }

  List<SpatialPointSample> _removeIsolated(
    List<SpatialPointSample> points,
    SpatialPointProcessingSettings settings,
  ) {
    final grid = <_GridKey, List<SpatialPointSample>>{};
    for (final point in points) {
      final key = _GridKey.fromPoint(point, settings.outlierRadiusMeters);
      grid.putIfAbsent(key, () => []).add(point);
    }
    final radiusSquared =
        settings.outlierRadiusMeters * settings.outlierRadiusMeters;
    return points.where((point) {
      final center = _GridKey.fromPoint(point, settings.outlierRadiusMeters);
      var neighbors = 0;
      for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
          for (var z = -1; z <= 1; z++) {
            final candidates = grid[_GridKey(
              center.x + x,
              center.y + y,
              center.z + z,
            )];
            if (candidates == null) continue;
            for (final candidate in candidates) {
              if (identical(candidate, point)) continue;
              final dx = candidate.x - point.x;
              final dy = candidate.y - point.y;
              final dz = candidate.z - point.z;
              if (dx * dx + dy * dy + dz * dz <= radiusSquared) {
                neighbors++;
                if (neighbors >= settings.minimumNeighbors) return true;
              }
            }
          }
        }
      }
      return false;
    }).toList(growable: false);
  }
}

class _GridKey {
  const _GridKey(this.x, this.y, this.z);

  factory _GridKey.fromPoint(SpatialPointSample point, double cellSize) =>
      _GridKey(
        (point.x / cellSize).floor(),
        (point.y / cellSize).floor(),
        (point.z / cellSize).floor(),
      );

  final int x;
  final int y;
  final int z;

  @override
  bool operator ==(Object other) =>
      other is _GridKey && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}
