import 'package:cadpilot_tablet/src/spatial_depth_capture.dart';
import 'package:cadpilot_tablet/src/spatial_registration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const originPoints = [
    SpatialPointSample(x: 1, y: 0, z: 0, confidence: 1),
    SpatialPointSample(x: 0, y: 1, z: 0, confidence: 0.8),
    SpatialPointSample(x: 0, y: 0, z: 1, confidence: 0.6),
  ];

  SpatialPointCloudFrame frame({
    required String id,
    required DateTime capturedAt,
    String sessionId = 'scan-1',
    SpatialSensorPose pose = SpatialSensorPose.identity,
    List<SpatialPointSample> points = originPoints,
  }) =>
      SpatialPointCloudFrame(
        sessionId: sessionId,
        frameId: id,
        capturedAt: capturedAt,
        coordinateSystem: spatialCoordinateSystem,
        sensorPose: pose,
        points: points,
      );

  test('registers ordered frames into normalized world coordinates', () {
    final first = frame(
      id: 'frame-1',
      capturedAt: DateTime.utc(2026, 7, 15, 12),
    );
    final second = frame(
      id: 'frame-2',
      capturedAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
      pose: const SpatialSensorPose(
        translation: SpatialVector3(10, 0, 0),
        rotation: SpatialQuaternion(0, 0, 0.70710678, 0.70710678),
      ),
    );

    final registered = const SpatialFrameRegistration().register([
      first,
      second,
    ]);

    expect(registered.sessionId, 'scan-1');
    expect(registered.sourceFrameIds, ['frame-1', 'frame-2']);
    expect(registered.points, hasLength(6));
    expect(registered.points[3].x, closeTo(10, 0.000001));
    expect(registered.points[3].y, closeTo(1, 0.000001));
    expect(registered.points[3].z, closeTo(0, 0.000001));
    expect(registered.points[3].confidence, 1);
  });

  test('rejects mixed sessions, duplicate frames, and time regression', () {
    final first = frame(
      id: 'frame-1',
      capturedAt: DateTime.utc(2026, 7, 15, 12),
    );
    expect(
      () => const SpatialFrameRegistration().register([
        first,
        frame(
          id: 'frame-2',
          capturedAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
          sessionId: 'scan-2',
        ),
      ]),
      throwsFormatException,
    );
    expect(
      () => const SpatialFrameRegistration().register([first, first]),
      throwsFormatException,
    );
    expect(
      () => const SpatialFrameRegistration().register([
        first,
        frame(
          id: 'frame-2',
          capturedAt: DateTime.utc(2026, 7, 15, 11, 59, 59),
        ),
      ]),
      throwsFormatException,
    );
  });

  test('pose decoder rejects non-unit rotation and unsafe translation', () {
    expect(
      () => SpatialSensorPose.fromMap({
        'translation': {'x': 0, 'y': 0, 'z': 0},
        'rotation': {'x': 0, 'y': 0, 'z': 0, 'w': 2},
      }),
      throwsFormatException,
    );
    expect(
      () => SpatialSensorPose.fromMap({
        'translation': {'x': 1001, 'y': 0, 'z': 0},
        'rotation': {'x': 0, 'y': 0, 'z': 0, 'w': 1},
      }),
      throwsFormatException,
    );
  });

  test('registration enforces the aggregate point ceiling', () {
    const sample = SpatialPointSample(x: 0, y: 0, z: 0, confidence: 1);
    final points = List<SpatialPointSample>.filled(250001, sample);
    expect(
      () => const SpatialFrameRegistration().register([
        frame(
          id: 'frame-1',
          capturedAt: DateTime.utc(2026, 7, 15, 12),
          points: points,
        ),
        frame(
          id: 'frame-2',
          capturedAt: DateTime.utc(2026, 7, 15, 12, 0, 1),
          points: points,
        ),
      ]),
      throwsFormatException,
    );
  });
}
