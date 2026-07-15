import 'package:cadpilot_tablet/src/spatial.dart';
import 'package:cadpilot_tablet/src/spatial_models.dart';
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
      'arRuntimeInstalled': true,
      'nativeArRendererAvailable': true,
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

  test('AR placement preflight requires tracking planes and camera access', () {
    final capabilities = SpatialCapabilities.fromMap(const {
      'platform': 'android',
      'cameraSupported': true,
      'arSupported': true,
      'planeDetectionSupported': true,
      'motionTrackingSupported': true,
      'captureMethod': 'camera_ar',
      'arRuntimeInstalled': true,
      'nativeArRendererAvailable': true,
    });
    final ready = ArPlacementPreflight(
      capabilities: capabilities,
      cameraPermission: CameraPermissionState.granted,
    );
    expect(ready.ready, isTrue);
    expect(ready.placementSource, 'camera_ar');
    expect(ready.blockers, isEmpty);

    final blocked = ArPlacementPreflight(
      capabilities: capabilities,
      cameraPermission: CameraPermissionState.permanentlyDenied,
    );
    expect(blocked.ready, isFalse);
    expect(blocked.placementSource, 'manual');
    expect(blocked.blockers.single, contains('system settings'));
  });

  test('device AR support without a CadPilot renderer falls back to manual',
      () {
    final capabilities = SpatialCapabilities.fromMap(const {
      'platform': 'android',
      'cameraSupported': true,
      'arSupported': true,
      'planeDetectionSupported': true,
      'motionTrackingSupported': true,
      'captureMethod': 'camera_ar',
      'arRuntimeInstalled': true,
      'nativeArRendererAvailable': false,
    });
    final preflight = ArPlacementPreflight(
      capabilities: capabilities,
      cameraPermission: CameraPermissionState.granted,
    );
    expect(preflight.ready, isFalse);
    expect(preflight.placementSource, 'manual');
    expect(preflight.blockers,
        contains('CadPilot native AR rendering is unavailable'));
  });
  test('supported device without an installed AR runtime is blocked', () {
    final capabilities = SpatialCapabilities.fromMap(const {
      'platform': 'android',
      'cameraSupported': true,
      'arSupported': true,
      'planeDetectionSupported': true,
      'motionTrackingSupported': true,
      'captureMethod': 'camera_ar',
      'arRuntimeInstalled': false,
      'nativeArRendererAvailable': true,
    });
    final preflight = ArPlacementPreflight(
      capabilities: capabilities,
      cameraPermission: CameraPermissionState.granted,
    );
    expect(preflight.ready, isFalse);
    expect(preflight.placementSource, 'manual');
    expect(preflight.blockers,
        contains('AR runtime is not installed or needs an update'));
  });
  test('preflight does not request camera access on unsupported devices',
      () async {
    const channel = MethodChannel('cadpilot/spatial-preflight-unsupported');
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    final result = await const SpatialCapabilityService(channel: channel)
        .placementPreflight(
      knownCapabilities: SpatialCapabilities.unsupported,
      requestPermission: true,
    );
    expect(result.ready, isFalse);
    expect(result.placementSource, 'manual');
    expect(calls, 0);
  });

  test('floor anchor request sends a true-scale native payload', () async {
    const channel = MethodChannel('cadpilot/spatial-anchor-request');
    final now = DateTime.utc(2026, 7, 14);
    final capabilities = SpatialCapabilities.fromMap(const {
      'platform': 'android',
      'cameraSupported': true,
      'arSupported': true,
      'planeDetectionSupported': true,
      'motionTrackingSupported': true,
      'captureMethod': 'camera_ar',
      'arRuntimeInstalled': true,
      'nativeArRendererAvailable': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'createFloorAnchor');
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments['placementId'], 'placement-native');
      expect(arguments['scale'], 1.0);
      expect(arguments['widthMeters'], 1.2);
      expect(arguments['matrixColumnMajor'], hasLength(16));
      return {
        'id': 'anchor-native',
        'platform': 'android',
        'trackingState': 'tracking',
        'updatedAt': now.toIso8601String(),
      };
    });
    final placement = SpatialPlacement(
      id: 'placement-native',
      name: 'Machine',
      createdAt: now,
      source: 'camera_ar',
      plane: 'floor',
      widthMm: 1200,
      heightMm: 800,
      depthMm: 600,
      offsetXMm: 0,
      offsetYMm: 0,
      offsetZMm: 0,
      rotationDegrees: 0,
    );
    final anchor = await const SpatialCapabilityService(channel: channel)
        .createFloorAnchor(
      placement: placement,
      preflight: ArPlacementPreflight(
        capabilities: capabilities,
        cameraPermission: CameraPermissionState.granted,
      ),
    );
    expect(anchor?.id, 'anchor-native');
    expect(anchor?.trackingState, SpatialTrackingState.tracking);
  });

  test('floor anchor request is blocked before successful preflight', () async {
    const channel = MethodChannel('cadpilot/spatial-anchor-blocked');
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    final placement = SpatialPlacement(
      id: 'manual',
      name: 'Manual',
      createdAt: DateTime.utc(2026, 7, 14),
      source: 'manual',
      plane: 'floor',
      widthMm: 100,
      heightMm: 100,
      depthMm: 100,
      offsetXMm: 0,
      offsetYMm: 0,
      offsetZMm: 0,
      rotationDegrees: 0,
    );
    expect(
      () => const SpatialCapabilityService(channel: channel).createFloorAnchor(
        placement: placement,
        preflight: const ArPlacementPreflight(
          capabilities: SpatialCapabilities.unsupported,
          cameraPermission: CameraPermissionState.unavailable,
        ),
      ),
      throwsStateError,
    );
    expect(calls, 0);
  });
}
