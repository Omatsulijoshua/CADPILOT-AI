import 'package:cadpilot_tablet/src/spatial.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('capability map preserves truthful LiDAR and camera labels', () {
    final capabilities = SpatialCapabilities.fromMap(const {
      'platform': 'android',
      'cameraSupported': true,
      'arSupported': true,
      'lidarSupported': false,
      'sceneDepthSupported': false,
      'meshReconstructionSupported': false,
      'planeDetectionSupported': true,
      'motionTrackingSupported': true,
      'captureMethod': 'camera_ar',
    });
    expect(capabilities.methodLabel, 'Camera AR tracking');
    expect(capabilities.lidarSupported, isFalse);
    expect(capabilities.cameraSupported, isTrue);
  });

  test('service decodes native capability response', () async {
    const channel = MethodChannel('cadpilot/spatial-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => const {
                  'platform': 'ios',
                  'cameraSupported': true,
                  'arSupported': true,
                  'lidarSupported': true,
                  'sceneDepthSupported': true,
                  'meshReconstructionSupported': true,
                  'planeDetectionSupported': true,
                  'motionTrackingSupported': true,
                  'captureMethod': 'lidar',
                });
    final result =
        await const SpatialCapabilityService(channel: channel).detect();
    expect(result.lidarSupported, isTrue);
    expect(result.methodLabel, 'LiDAR depth scanning');
  });

  test('missing native plugin returns manual fallback', () async {
    const channel = MethodChannel('cadpilot/spatial-missing');
    final result =
        await const SpatialCapabilityService(channel: channel).detect();
    expect(result, same(SpatialCapabilities.unsupported));
    expect(result.methodLabel, 'Manual measurement fallback');
  });

  test('camera permission request decodes explicit native states', () async {
    const channel = MethodChannel('cadpilot/spatial-permission');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestCameraPermission');
      return 'permanently_denied';
    });
    final state = await const SpatialCapabilityService(channel: channel)
        .cameraPermission(request: true);
    expect(state, CameraPermissionState.permanentlyDenied);
    expect(state.label, contains('system settings'));
  });

  test('missing camera permission plugin fails closed', () async {
    const channel = MethodChannel('cadpilot/spatial-permission-missing');
    final state = await const SpatialCapabilityService(channel: channel)
        .cameraPermission(request: true);
    expect(state, CameraPermissionState.unavailable);
  });
}
