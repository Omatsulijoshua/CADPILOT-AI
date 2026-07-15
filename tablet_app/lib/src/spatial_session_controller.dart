import 'package:flutter/services.dart';

import 'spatial.dart';
import 'spatial_session.dart';
import 'spatial_session_channel.dart';
import 'spatial_session_control.dart';

class ArSessionController {
  ArSessionController({
    required this.sessionId,
    required this.onStateChanged,
    MethodChannel channel = const MethodChannel('cadpilot/spatial'),
  })  : _control = ArSessionControlService(channel: channel),
        _bridge = ArSessionMethodChannelBridge(
          coordinator: ArSessionCoordinator(sessionId: sessionId),
          onStateChanged: onStateChanged,
          channel: channel,
        );

  final String sessionId;
  final void Function(ArSessionState state) onStateChanged;
  final ArSessionControlService _control;
  final ArSessionMethodChannelBridge _bridge;
  bool _active = false;

  bool get isActive => _active;
  bool get isListening => _bridge.isListening;
  ArSessionState get state => _bridge.coordinator.state;

  Future<bool> start({required ArPlacementPreflight preflight}) async {
    if (_active) return true;
    _bridge.start();
    final started = await _control.start(
      sessionId: sessionId,
      preflight: preflight,
    );
    if (!started) {
      _bridge.dispose();
      return false;
    }
    _active = true;
    return true;
  }

  Future<bool> stop() async {
    if (!_active) {
      _bridge.dispose();
      return false;
    }
    try {
      return await _control.stop(sessionId: sessionId);
    } finally {
      _active = false;
      _bridge.dispose();
    }
  }

  void dispose() {
    _active = false;
    _bridge.dispose();
  }
}
