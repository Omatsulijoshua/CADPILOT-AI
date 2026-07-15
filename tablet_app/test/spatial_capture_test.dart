import 'package:cadpilot_tablet/src/spatial_capture.dart';
import 'package:cadpilot_tablet/src/spatial_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cadpilot/spatial-capture-test');
  const anchored = ArSessionState(
    phase: ArSessionPhase.anchored,
    planeId: 'floor-1',
    anchorId: 'anchor-1',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('anchored session requests and validates a native AR screenshot',
      () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return {
        'path': '/captures/ar-1.png',
        'widthPixels': 2048,
        'heightPixels': 1536,
        'capturedAt': '2026-07-15T12:30:00Z',
        'sessionId': 'session-1',
        'anchorId': 'anchor-1',
      };
    });
    final screenshot = await const ArScreenshotService(channel: channel)
        .capture(sessionId: 'session-1', state: anchored);
    expect(received?.method, 'captureArScreenshot');
    expect(received?.arguments, {
      'sessionId': 'session-1',
      'anchorId': 'anchor-1',
    });
    expect(screenshot?.path, '/captures/ar-1.png');
    expect(screenshot?.widthPixels, 2048);
    expect(screenshot?.capturedAt, DateTime.utc(2026, 7, 15, 12, 30));
  });

  test('capture is blocked before a native anchor exists', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    expect(
      () => const ArScreenshotService(channel: channel).capture(
        sessionId: 'session-1',
        state: const ArSessionState(phase: ArSessionPhase.planeReady),
      ),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test('mismatched or malformed native screenshots are rejected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => {
                  'path': '/captures/wrong.png',
                  'widthPixels': 100,
                  'heightPixels': 100,
                  'capturedAt': '2026-07-15T12:30:00Z',
                  'sessionId': 'another-session',
                  'anchorId': 'anchor-1',
                });
    expect(
      () => const ArScreenshotService(channel: channel)
          .capture(sessionId: 'session-1', state: anchored),
      throwsFormatException,
    );
    expect(
      () => ArScreenshot.fromMap(const {
        'path': '',
        'widthPixels': 0,
        'heightPixels': 100,
        'capturedAt': 'invalid',
        'sessionId': '',
        'anchorId': '',
      }),
      throwsFormatException,
    );
  });

  test('missing native capture implementation fails closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });
    final screenshot = await const ArScreenshotService(channel: channel)
        .capture(sessionId: 'session-1', state: anchored);
    expect(screenshot, isNull);
  });
}
