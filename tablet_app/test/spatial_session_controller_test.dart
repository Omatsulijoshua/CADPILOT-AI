import 'package:cadpilot_tablet/src/spatial.dart';
import 'package:cadpilot_tablet/src/spatial_session.dart';
import 'package:cadpilot_tablet/src/spatial_session_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cadpilot/spatial-session-controller-test');
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
      arRuntimeInstalled: true,
      nativeArRendererAvailable: true,
    ),
    cameraPermission: CameraPermissionState.granted,
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('controller listens before start and becomes active on acknowledgement',
      () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    final controller = ArSessionController(
      sessionId: 'session-11',
      onStateChanged: (_) {},
      channel: channel,
    );
    expect(await controller.start(preflight: ready), isTrue);
    expect(controller.isActive, isTrue);
    expect(controller.isListening, isTrue);
    expect(calls, ['startArSession']);
    expect(await controller.start(preflight: ready), isTrue);
    expect(calls, ['startArSession']);
    controller.dispose();
  });

  test('failed native start rolls back event listening', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    final controller = ArSessionController(
      sessionId: 'session-11',
      onStateChanged: (_) {},
      channel: channel,
    );
    expect(await controller.start(preflight: ready), isFalse);
    expect(controller.isActive, isFalse);
    expect(controller.isListening, isFalse);
  });

  test('stop targets active session and always detaches callbacks', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'startArSession';
    });
    final controller = ArSessionController(
      sessionId: 'session-11',
      onStateChanged: (_) {},
      channel: channel,
    );
    expect(await controller.start(preflight: ready), isTrue);
    expect(await controller.stop(), isFalse);
    expect(
        calls.map((call) => call.method), ['startArSession', 'stopArSession']);
    expect(calls.last.arguments, {'sessionId': 'session-11'});
    expect(controller.isActive, isFalse);
    expect(controller.isListening, isFalse);
  });

  test('inactive stop is a no-op and dispose is idempotent', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return true;
    });
    final states = <ArSessionState>[];
    final controller = ArSessionController(
      sessionId: 'session-11',
      onStateChanged: states.add,
      channel: channel,
    );
    expect(await controller.stop(), isFalse);
    controller.dispose();
    controller.dispose();
    expect(calls, 0);
    expect(states, isEmpty);
  });
}
