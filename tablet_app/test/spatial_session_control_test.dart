import 'package:cadpilot_tablet/src/spatial.dart';
import 'package:cadpilot_tablet/src/spatial_session_control.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cadpilot/spatial-session-control-test');
  const ready = ArPlacementPreflight(
    capabilities: SpatialCapabilities(
      platform: 'test',
      cameraSupported: true,
      arSupported: true,
      lidarSupported: false,
      sceneDepthSupported: false,
      meshReconstructionSupported: false,
      planeDetectionSupported: true,
      motionTrackingSupported: true,
      captureMethod: 'camera_ar',
    ),
    cameraPermission: CameraPermissionState.granted,
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('ready preflight starts a horizontal true-scale AR session', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    final started = await const ArSessionControlService(channel: channel)
        .start(sessionId: 'session-7', preflight: ready);
    expect(started, isTrue);
    expect(received?.method, 'startArSession');
    expect(received?.arguments, {
      'sessionId': 'session-7',
      'planeDetection': 'horizontal',
      'scale': 1.0,
    });
  });

  test('failed preflight blocks start before invoking native code', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return true;
    });
    expect(
      () => const ArSessionControlService(channel: channel).start(
        sessionId: 'session-7',
        preflight: const ArPlacementPreflight(
          capabilities: SpatialCapabilities.unsupported,
          cameraPermission: CameraPermissionState.unavailable,
        ),
      ),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test('stop targets only the named native session', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    final stopped = await const ArSessionControlService(channel: channel)
        .stop(sessionId: 'session-7');
    expect(stopped, isTrue);
    expect(received?.method, 'stopArSession');
    expect(received?.arguments, {'sessionId': 'session-7'});
  });

  test('invalid IDs and missing native hosts fail closed', () async {
    expect(
      () => const ArSessionControlService(channel: channel)
          .stop(sessionId: '   '),
      throwsArgumentError,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });
    const service = ArSessionControlService(channel: channel);
    expect(
        await service.start(sessionId: 'session-7', preflight: ready), isFalse);
    expect(await service.stop(sessionId: 'session-7'), isFalse);
  });
}
