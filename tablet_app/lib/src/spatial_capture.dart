import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'spatial_session.dart';

class ArScreenshot {
  const ArScreenshot({
    required this.path,
    required this.widthPixels,
    required this.heightPixels,
    required this.capturedAt,
    required this.sessionId,
    required this.anchorId,
  });

  final String path;
  final int widthPixels;
  final int heightPixels;
  final DateTime capturedAt;
  final String sessionId;
  final String anchorId;

  Map<String, Object?> toJson() => {
        'path': path,
        'widthPixels': widthPixels,
        'heightPixels': heightPixels,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'sessionId': sessionId,
        'anchorId': anchorId,
      };

  factory ArScreenshot.fromJson(Map<String, Object?> value) =>
      ArScreenshot.fromMap(value);

  factory ArScreenshot.fromMap(Map<Object?, Object?> value) {
    final path = value['path'] as String?;
    final width = value['widthPixels'] as int?;
    final height = value['heightPixels'] as int?;
    final capturedAtText = value['capturedAt'] as String?;
    final sessionId = value['sessionId'] as String?;
    final anchorId = value['anchorId'] as String?;
    final capturedAt = capturedAtText == null
        ? null
        : DateTime.tryParse(capturedAtText)?.toUtc();
    if (path == null || path.trim().isEmpty) {
      throw const FormatException('AR screenshot requires a file path.');
    }
    if (width == null || width <= 0 || height == null || height <= 0) {
      throw const FormatException('AR screenshot dimensions must be positive.');
    }
    if (capturedAt == null) {
      throw const FormatException(
          'AR screenshot requires a valid capture time.');
    }
    if (sessionId == null ||
        sessionId.trim().isEmpty ||
        anchorId == null ||
        anchorId.trim().isEmpty) {
      throw const FormatException(
          'AR screenshot requires session and anchor IDs.');
    }
    return ArScreenshot(
      path: path,
      widthPixels: width,
      heightPixels: height,
      capturedAt: capturedAt,
      sessionId: sessionId,
      anchorId: anchorId,
    );
  }
}

class ArScreenshotService {
  const ArScreenshotService({
    MethodChannel channel = const MethodChannel('cadpilot/spatial'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<ArScreenshot?> capture({
    required String sessionId,
    required ArSessionState state,
  }) async {
    if (kIsWeb) return null;
    if (sessionId.trim().isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    if (!state.hasNativeAnchor) {
      throw StateError(
          'An anchored AR session is required for screenshot capture.');
    }
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'captureArScreenshot',
        {'sessionId': sessionId, 'anchorId': state.anchorId},
      );
      if (value == null) return null;
      final screenshot = ArScreenshot.fromMap(value);
      if (screenshot.sessionId != sessionId ||
          screenshot.anchorId != state.anchorId) {
        throw const FormatException(
          'AR screenshot does not match the active session anchor.',
        );
      }
      return screenshot;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
