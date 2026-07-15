import 'package:cadpilot_tablet/src/spatial_depth_capture.dart';
import 'package:cadpilot_tablet/src/spatial_measurements.dart';
import 'package:cadpilot_tablet/src/spatial_point_processing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProcessedSpatialPointCloud cloud(List<SpatialPointSample> points) =>
      ProcessedSpatialPointCloud(
        sessionId: 'scan-1',
        startedAt: DateTime.utc(2026, 7, 15, 12),
        endedAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
        sourceFrameIds: const ['frame-1', 'frame-2'],
        points: points,
        settings: const SpatialPointProcessingSettings(
          voxelSizeMeters: 0.01,
          outlierRadiusMeters: 0.02,
        ),
        stats: SpatialPointProcessingStats(
          inputPoints: points.length,
          afterConfidenceFilter: points.length,
          afterVoxelDownsample: points.length,
          outputPoints: points.length,
        ),
      );

  test('extracts axis-aligned millimeter bounds and centroid', () {
    final result = const SpatialMeasurementExtractor().extract(cloud(const [
      SpatialPointSample(x: -1, y: -2, z: -3, confidence: 0.6),
      SpatialPointSample(x: 1, y: 1, z: 1, confidence: 0.8),
      SpatialPointSample(x: 0, y: 0, z: 0, confidence: 1),
    ]));

    expect(result.widthMm, 2000);
    expect(result.heightMm, 3000);
    expect(result.depthMm, 4000);
    expect(result.diagonalMm, closeTo(5385.164807, 0.000001));
    expect(result.centroidMeters.x, 0);
    expect(result.centroidMeters.y, closeTo(-1 / 3, 0.000001));
    expect(result.centroidMeters.z, closeTo(-2 / 3, 0.000001));
    expect(result.meanConfidence, closeTo(0.8, 0.000001));
  });

  test('detects a planar cloud using the processed voxel resolution', () {
    final result = const SpatialMeasurementExtractor().extract(cloud(const [
      SpatialPointSample(x: 0, y: 0, z: 0, confidence: 1),
      SpatialPointSample(x: 1, y: 0, z: 0.005, confidence: 1),
      SpatialPointSample(x: 0, y: 2, z: 0.01, confidence: 1),
    ]));

    expect(result.isPlanar, isTrue);
    expect(result.planarAxis, SpatialPlanarAxis.z);
    expect(result.resolutionMm, 10);
  });

  test('preserves provenance and carries an explicit advisory label', () {
    final result = const SpatialMeasurementExtractor().extract(cloud(const [
      SpatialPointSample(x: 0, y: 0, z: 0, confidence: 1),
      SpatialPointSample(x: 1, y: 0, z: 0, confidence: 1),
      SpatialPointSample(x: 0, y: 1, z: 0, confidence: 1),
    ]));

    expect(result.sessionId, 'scan-1');
    expect(result.sourceFrameIds, ['frame-1', 'frame-2']);
    expect(result.pointCount, 3);
    expect(result.accuracyLabel, contains('not a certified measurement'));
  });

  test('rejects too-small and degenerate point clouds', () {
    expect(
      () => const SpatialMeasurementExtractor().extract(cloud(const [
        SpatialPointSample(x: 0, y: 0, z: 0, confidence: 1),
        SpatialPointSample(x: 1, y: 0, z: 0, confidence: 1),
      ])),
      throwsFormatException,
    );
    expect(
      () => const SpatialMeasurementExtractor().extract(cloud(const [
        SpatialPointSample(x: 1, y: 1, z: 1, confidence: 1),
        SpatialPointSample(x: 1, y: 1, z: 1, confidence: 1),
        SpatialPointSample(x: 1, y: 1, z: 1, confidence: 1),
      ])),
      throwsFormatException,
    );
    expect(
      () => const SpatialMeasurementExtractor().extract(cloud(const [
        SpatialPointSample(x: 0, y: 0, z: 0, confidence: 1),
        SpatialPointSample(x: 1, y: 0, z: 0, confidence: 1),
        SpatialPointSample(x: 2, y: 0, z: 0, confidence: 1),
      ])),
      throwsFormatException,
    );
  });

  test('revalidates finite coordinates and confidence at extraction', () {
    for (final point in const [
      SpatialPointSample(x: double.nan, y: 0, z: 0, confidence: 1),
      SpatialPointSample(x: 0, y: 0, z: 0, confidence: 2),
    ]) {
      expect(
        () => const SpatialMeasurementExtractor().extract(cloud([
          point,
          const SpatialPointSample(x: 1, y: 0, z: 0, confidence: 1),
          const SpatialPointSample(x: 0, y: 1, z: 0, confidence: 1),
        ])),
        throwsFormatException,
      );
    }
  });
}
