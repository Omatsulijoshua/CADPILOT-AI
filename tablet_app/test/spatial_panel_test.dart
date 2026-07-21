import 'package:cadpilot_tablet/src/spatial.dart';
import 'package:cadpilot_tablet/src/spatial_depth_capture.dart';
import 'package:cadpilot_tablet/src/spatial_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LiDAR capability label points users to camera/native readiness', () {
    const capabilities = SpatialCapabilities(
      platform: 'ios',
      cameraSupported: true,
      arSupported: true,
      arRuntimeInstalled: true,
      lidarSupported: true,
      sceneDepthSupported: true,
      meshReconstructionSupported: true,
      planeDetectionSupported: true,
      motionTrackingSupported: true,
      captureMethod: 'camera_ar',
      nativeDepthCaptureAvailable: false,
    );

    expect(capabilities.methodLabel,
        'Depth hardware detected; grant camera access to scan');
    expect(capabilities.depthCaptureReady, isFalse);
  });

  test('spatial capabilities preserve native LiDAR diagnostics', () {
    final capabilities = SpatialCapabilities.fromMap(const {
      'platform': 'ios',
      'cameraSupported': true,
      'arSupported': true,
      'arRuntimeInstalled': true,
      'lidarSupported': true,
      'sceneDepthSupported': true,
      'meshReconstructionSupported': true,
      'planeDetectionSupported': true,
      'motionTrackingSupported': true,
      'captureMethod': 'lidar',
      'nativeDepthCaptureAvailable': true,
      'diagnostic':
          'ios_arkit ar=true lidar=true cameraPermission=granted capture=lidar',
    });

    expect(capabilities.depthCaptureReady, isTrue);
    expect(capabilities.diagnostic, contains('cameraPermission=granted'));
  });

  testWidgets('spatial workspace remains scrollable with many placements',
      (tester) async {
    const channel = MethodChannel('cadpilot/spatial-panel-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => const {
                  'platform': 'test',
                  'cameraSupported': false,
                  'arSupported': false,
                  'lidarSupported': false,
                  'sceneDepthSupported': false,
                  'meshReconstructionSupported': false,
                  'planeDetectionSupported': false,
                  'motionTrackingSupported': false,
                  'captureMethod': 'manual',
                });
    final createdAt = DateTime.utc(2026, 7, 15);
    final placements = List.generate(
      30,
      (index) => SpatialPlacement(
        id: 'placement-$index',
        name: 'Placement $index',
        createdAt: createdAt,
        source: 'manual',
        plane: 'floor',
        widthMm: 100,
        heightMm: 100,
        depthMm: 100,
        offsetXMm: 0,
        offsetYMm: 0,
        offsetZMm: 0,
        rotationDegrees: 0,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SpatialCapabilityPanel(
          projectName: 'Large project',
          service: const SpatialCapabilityService(channel: channel),
          placements: placements,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Saved placements (30)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Placement 29'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('captures a capability-gated advisory depth scan',
      (tester) async {
    const channel = MethodChannel('cadpilot/spatial-panel-scan-test');
    var frameNumber = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getCapabilities') {
        return const {
          'platform': 'android',
          'cameraSupported': true,
          'arSupported': true,
          'arRuntimeInstalled': true,
          'lidarSupported': false,
          'sceneDepthSupported': true,
          'meshReconstructionSupported': false,
          'planeDetectionSupported': true,
          'motionTrackingSupported': true,
          'captureMethod': 'depth_camera',
          'nativeDepthCaptureAvailable': true,
        };
      }
      if (call.method == 'captureDepthFrame') {
        frameNumber++;
        return {
          'sessionId': call.arguments['sessionId'],
          'frameId': 'frame-$frameNumber',
          'capturedAt': '2026-07-15T00:00:00.000Z',
          'coordinateSystem': 'right_handed_y_up_meters',
          'sensorPose': const {
            'translation': {'x': 0.0, 'y': 0.0, 'z': 0.0},
            'rotation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0},
          },
          'points': const [
            {'x': 0.0, 'y': 0.0, 'z': 0.0, 'confidence': 1.0},
            {'x': 0.004, 'y': 0.006, 'z': 0.008, 'confidence': 1.0},
            {'x': 0.008, 'y': 0.012, 'z': 0.016, 'confidence': 1.0},
            {'x': 0.012, 'y': 0.018, 'z': 0.024, 'confidence': 1.0},
            {'x': 0.016, 'y': 0.024, 'z': 0.032, 'confidence': 1.0},
            {'x': 0.020, 'y': 0.030, 'z': 0.040, 'confidence': 1.0},
          ],
        };
      }
      return null;
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SpatialCapabilityPanel(
          projectName: 'Depth project',
          service: SpatialCapabilityService(channel: channel),
          depthCaptureService:
              SpatialDepthCaptureService(channel: channel, isWeb: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Capture advisory depth scan'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Capture advisory depth scan'));
    await tester.pumpAndSettle();

    expect(frameNumber, 3);
    expect(find.text('Capture advisory depth scan'), findsOneWidget);
  });
}
