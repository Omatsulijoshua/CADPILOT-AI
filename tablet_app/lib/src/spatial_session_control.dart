import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'spatial.dart';

class ArSessionControlService {
  const ArSessionControlService({
    MethodChannel channel = const MethodChannel('cadpilot/spatial'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> start({
    required String sessionId,
    required ArPlacementPreflight preflight,
  }) async {
    _validateSessionId(sessionId);
    if (!preflight.ready) {
      throw StateError(
        'AR placement preflight must pass before starting a native session.',
      );
    }
    if (kIsWeb) return false;
    try {
      final started = await _channel.invokeMethod<bool>('startArSession', {
        'sessionId': sessionId,
        'planeDetection': 'horizontal',
        'scale': 1.0,
      });
      return started == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stop({required String sessionId}) async {
    _validateSessionId(sessionId);
    if (kIsWeb) return false;
    try {
      final stopped = await _channel.invokeMethod<bool>(
        'stopArSession',
        {'sessionId': sessionId},
      );
      return stopped == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static void _validateSessionId(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'sessionId', 'must not be empty');
    }
  }
}
