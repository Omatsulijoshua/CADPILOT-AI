import 'package:cadpilot_tablet/src/spatial.dart';
import 'package:cadpilot_tablet/src/spatial_depth_capture.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cadpilot/spatial-depth-capture-test');
  const depthCapabilities = SpatialCapabilities(
    platform: 'test',
    cameraSupported: true,
    arSupported: true,
    lidarSupported: true,
    sceneDepthSupported: true,
    meshReconstructionSupported: false,
    planeDetectionSupported: true,
    motionTrackingSupported: true,
    captureMethod: 'lidar',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('validated depth frame preserves meters and confidence', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return {
        'sessionId': 'scan-1',
        'frameId': 'frame-9',
        'capturedAt': '2026-07-15T12:00:00.000Z',
        'coordinateSystem': spatialCoordinateSystem,
        'points': [
          {'x': 0, 'y': 0, 'z': 0, 'confidence': 1},
          {'x': 1.25, 'y': 0, 'z': 0, 'confidence': 0.8},
          {'x': 0, 'y': 2.5, 'z': -0.5, 'confidence': 0.6},
        ],
      };
    });

    final frame = await const SpatialDepthCaptureService(channel: channel)
        .capture(sessionId: ' scan-1 ', capabilities: depthCapabilities);

    expect(received?.method, 'captureDepthFrame');
    expect(received?.arguments, {
      'sessionId': 'scan-1',
      'coordinateSystem': spatialCoordinateSystem,
      'maxPoints': maxSpatialPointsPerFrame,
    });
    expect(frame?.frameId, 'frame-9');
    expect(frame?.points[1].x, 1.25);
    expect(frame?.points[2].confidence, 0.6);
  });

  test('capture is blocked when native depth is not advertised', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });

    expect(
      () => const SpatialDepthCaptureService(channel: channel).capture(
        sessionId: 'scan-1',
        capabilities: SpatialCapabilities.unsupported,
      ),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test('frame rejects non-finite, low-confidence, and unsafe points', () {
    Map<Object?, Object?> frame(Map<Object?, Object?> point) => {
          'sessionId': 'scan-1',
          'frameId': 'frame-1',
          'capturedAt': '2026-07-15T12:00:00Z',
          'coordinateSystem': spatialCoordinateSystem,
          'points': [point, point, point],
        };

    expect(
      () => SpatialPointCloudFrame.fromMap(frame(
        {'x': double.nan, 'y': 0, 'z': 0, 'confidence': 1},
      )),
      throwsFormatException,
    );
    expect(
      () => SpatialPointCloudFrame.fromMap(frame(
        {'x': 0, 'y': 0, 'z': 0, 'confidence': 1.1},
      )),
      throwsFormatException,
    );
    expect(
      () => SpatialPointCloudFrame.fromMap(frame(
        {'x': 1001, 'y': 0, 'z': 0, 'confidence': 1},
      )),
      throwsFormatException,
    );
  });

  test('frame rejects invalid metadata and mismatched sessions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => {
                  'sessionId': 'another-scan',
                  'frameId': 'frame-1',
                  'capturedAt': '2026-07-15T12:00:00Z',
                  'coordinateSystem': spatialCoordinateSystem,
                  'points': List.generate(
                    3,
                    (_) => {'x': 0, 'y': 0, 'z': 0, 'confidence': 1},
                  ),
                });

    expect(
      () => const SpatialDepthCaptureService(channel: channel).capture(
        sessionId: 'scan-1',
        capabilities: depthCapabilities,
      ),
      throwsFormatException,
    );
    expect(
      () => SpatialPointCloudFrame.fromMap({
        'sessionId': 'scan-1',
        'frameId': 'frame-1',
        'capturedAt': '2026-07-15T12:00:00',
        'coordinateSystem': 'left_handed_millimeters',
        'points': const [],
      }),
      throwsFormatException,
    );
  });

  test('missing or unavailable native capture fails closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'depth_capture_unavailable');
    });
    expect(
      await const SpatialDepthCaptureService(channel: channel).capture(
        sessionId: 'scan-1',
        capabilities: depthCapabilities,
      ),
      isNull,
    );
  });
}
