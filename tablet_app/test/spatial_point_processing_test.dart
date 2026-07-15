import 'package:cadpilot_tablet/src/spatial_depth_capture.dart';
import 'package:cadpilot_tablet/src/spatial_point_processing.dart';
import 'package:cadpilot_tablet/src/spatial_registration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RegisteredSpatialPointCloud cloud(List<SpatialPointSample> points) =>
      RegisteredSpatialPointCloud(
        sessionId: 'scan-1',
        startedAt: DateTime.utc(2026, 7, 15, 12),
        endedAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
        sourceFrameIds: const ['frame-1', 'frame-2'],
        points: points,
      );

  test('filters confidence and keeps the best sample in each voxel', () {
    final result = const SpatialPointCloudProcessor().process(
      cloud(const [
        SpatialPointSample(x: 0.001, y: 0, z: 0, confidence: 0.4),
        SpatialPointSample(x: 0.002, y: 0, z: 0, confidence: 0.7),
        SpatialPointSample(x: 0.003, y: 0, z: 0, confidence: 0.9),
        SpatialPointSample(x: 0.02, y: 0, z: 0, confidence: 0.8),
      ]),
      settings: const SpatialPointProcessingSettings(
        minimumConfidence: 0.5,
        voxelSizeMeters: 0.01,
        outlierRadiusMeters: 0.01,
        minimumNeighbors: 0,
      ),
    );

    expect(result.points, hasLength(2));
    expect(result.points.first.confidence, 0.9);
    expect(result.stats.removedByConfidence, 1);
    expect(result.stats.removedByDownsampling, 1);
    expect(result.stats.removedAsIsolated, 0);
  });

  test('removes isolated points while retaining a local cluster', () {
    final result = const SpatialPointCloudProcessor().process(
      cloud(const [
        SpatialPointSample(x: 0, y: 0, z: 0, confidence: 1),
        SpatialPointSample(x: 0.011, y: 0, z: 0, confidence: 1),
        SpatialPointSample(x: 0, y: 0.011, z: 0, confidence: 1),
        SpatialPointSample(x: 5, y: 5, z: 5, confidence: 1),
      ]),
      settings: const SpatialPointProcessingSettings(
        voxelSizeMeters: 0.01,
        outlierRadiusMeters: 0.02,
        minimumNeighbors: 2,
      ),
    );

    expect(result.points, hasLength(3));
    expect(result.points.any((point) => point.x == 5), isFalse);
    expect(result.stats.removedAsIsolated, 1);
  });

  test('processing is deterministic and preserves scan provenance', () {
    final input = cloud(const [
      SpatialPointSample(x: -0.001, y: 0, z: 0, confidence: 0.8),
      SpatialPointSample(x: 0.001, y: 0, z: 0, confidence: 0.8),
    ]);
    const settings = SpatialPointProcessingSettings(
      minimumConfidence: 0,
      voxelSizeMeters: 0.001,
      outlierRadiusMeters: 0.001,
      minimumNeighbors: 0,
    );
    final first =
        const SpatialPointCloudProcessor().process(input, settings: settings);
    final second =
        const SpatialPointCloudProcessor().process(input, settings: settings);

    expect(first.points.map((point) => point.x), [-0.001, 0.001]);
    expect(second.points.map((point) => point.x), [-0.001, 0.001]);
    expect(first.sessionId, 'scan-1');
    expect(first.sourceFrameIds, ['frame-1', 'frame-2']);
  });

  test('invalid processing settings fail before point work', () {
    final input = cloud(const []);
    for (final settings in [
      const SpatialPointProcessingSettings(minimumConfidence: 1.1),
      const SpatialPointProcessingSettings(voxelSizeMeters: 0),
      const SpatialPointProcessingSettings(
        voxelSizeMeters: 0.01,
        outlierRadiusMeters: 0.009,
      ),
      const SpatialPointProcessingSettings(minimumNeighbors: 27),
    ]) {
      expect(
        () => const SpatialPointCloudProcessor()
            .process(input, settings: settings),
        throwsFormatException,
      );
    }
  });

  test('all-rejected input returns an empty typed result with statistics', () {
    final result = const SpatialPointCloudProcessor().process(
      cloud(const [
        SpatialPointSample(x: 0, y: 0, z: 0, confidence: 0.2),
      ]),
      settings: const SpatialPointProcessingSettings(minimumConfidence: 0.9),
    );

    expect(result.points, isEmpty);
    expect(result.stats.inputPoints, 1);
    expect(result.stats.afterConfidenceFilter, 0);
    expect(result.stats.outputPoints, 0);
  });
}
