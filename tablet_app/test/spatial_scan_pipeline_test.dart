import 'package:cadpilot_tablet/src/spatial.dart';
import 'package:cadpilot_tablet/src/spatial_depth_capture.dart';
import 'package:cadpilot_tablet/src/spatial_point_processing.dart';
import 'package:cadpilot_tablet/src/spatial_scan_pipeline.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const channel = MethodChannel('cadpilot/spatial');
const capabilities = SpatialCapabilities(
  platform: 'android',
  cameraSupported: true,
  arSupported: true,
  lidarSupported: false,
  sceneDepthSupported: true,
  meshReconstructionSupported: false,
  planeDetectionSupported: true,
  motionTrackingSupported: true,
  captureMethod: 'depth_camera',
  nativeDepthCaptureAvailable: true,
);

Map<Object?, Object?> frame(String id, double offset) => {
      'sessionId': 'scan-1',
      'frameId': id,
      'capturedAt': '2026-07-15T12:00:00.000Z',
      'coordinateSystem': spatialCoordinateSystem,
      'sensorPose': {
        'translation': {'x': 0, 'y': 0, 'z': 0},
        'rotation': {'x': 0, 'y': 0, 'z': 0, 'w': 1},
      },
      'points': [
        {'x': offset, 'y': 0, 'z': 0, 'confidence': 1},
        {'x': offset + 0.03, 'y': 0.03, 'z': 0, 'confidence': 0.9},
        {'x': offset, 'y': 0, 'z': 0.03, 'confidence': 0.8},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('processes validated frames into advisory scan measurements', () {
    final result = const SpatialScanPipeline().processFrames([
      SpatialPointCloudFrame.fromMap(frame('frame-1', 0)),
      SpatialPointCloudFrame.fromMap(frame('frame-2', 0.03)),
    ], settings: const SpatialPointProcessingSettings(minimumNeighbors: 0));

    expect(result.status, SpatialScanStatus.completed);
    expect(result.frames, hasLength(2));
    expect(result.processedCloud?.sourceFrameIds, ['frame-1', 'frame-2']);
    expect(result.measurements?.pointCount, 6);
    expect(result.measurements?.accuracyLabel, contains('not a certified'));
  });

  test('reports insufficient data instead of manufacturing a measurement', () {
    final result = const SpatialScanPipeline().processFrames([
      SpatialPointCloudFrame.fromMap(frame('frame-1', 0)),
    ],
        settings: const SpatialPointProcessingSettings(
          minimumConfidence: 1,
          minimumNeighbors: 0,
        ));

    expect(result.status, SpatialScanStatus.insufficientData);
    expect(result.measurements, isNull);
    expect(result.processedCloud?.points, hasLength(1));
  });

  test('stops capture on unavailability and reports it truthfully', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final result = await const SpatialScanPipeline().captureAndProcess(
      sessionId: 'scan-1',
      capabilities: capabilities,
      captureService: const SpatialDepthCaptureService(channel: channel),
    );

    expect(result.status, SpatialScanStatus.unavailable);
    expect(result.frames, isEmpty);
    expect(result.measurements, isNull);
  });

  test('rejects unsafe requested frame counts before native capture', () async {
    await expectLater(
      () => const SpatialScanPipeline().captureAndProcess(
        sessionId: 'scan-1',
        capabilities: capabilities,
        captureService: const SpatialDepthCaptureService(channel: channel),
        requestedFrames: maxSpatialFramesPerScan + 1,
      ),
      throwsRangeError,
    );
  });
}
