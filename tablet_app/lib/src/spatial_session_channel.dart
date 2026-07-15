import 'package:flutter/services.dart';

import 'spatial_session.dart';

class ArSessionEventEnvelope {
  const ArSessionEventEnvelope({
    required this.sessionId,
    required this.sequence,
    required this.event,
    this.planeId,
    this.anchorId,
    this.message,
  });

  final String sessionId;
  final int sequence;
  final ArSessionEvent event;
  final String? planeId;
  final String? anchorId;
  final String? message;

  factory ArSessionEventEnvelope.fromMap(Map<Object?, Object?> value) {
    final sessionId = value['sessionId'] as String?;
    final sequence = value['sequence'] as int?;
    final eventName = value['event'] as String?;
    if (sessionId == null || sessionId.trim().isEmpty) {
      throw const FormatException('Native AR event requires a sessionId.');
    }
    if (sequence == null || sequence < 0) {
      throw const FormatException(
          'Native AR event requires a non-negative sequence.');
    }
    final event = ArSessionEvent.values.where(
      (candidate) => candidate.name == eventName,
    );
    if (event.length != 1) {
      throw FormatException('Unknown native AR event: $eventName.');
    }
    return ArSessionEventEnvelope(
      sessionId: sessionId,
      sequence: sequence,
      event: event.single,
      planeId: value['planeId'] as String?,
      anchorId: value['anchorId'] as String?,
      message: value['message'] as String?,
    );
  }
}

class ArSessionCoordinator {
  ArSessionCoordinator({required this.sessionId});

  final String sessionId;
  ArSessionState state = ArSessionState.idle;
  int _lastSequence = -1;

  int get lastSequence => _lastSequence;

  bool consume(ArSessionEventEnvelope envelope) {
    if (envelope.sessionId != sessionId) return false;
    if (envelope.sequence <= _lastSequence) {
      throw StateError(
        'Out-of-order AR event ${envelope.sequence}; '
        'last accepted sequence is $_lastSequence.',
      );
    }
    final next = state.transition(
      envelope.event,
      planeId: envelope.planeId,
      anchorId: envelope.anchorId,
      message: envelope.message,
    );
    state = next;
    _lastSequence = envelope.sequence;
    return true;
  }
}

class ArSessionMethodChannelBridge {
  ArSessionMethodChannelBridge({
    required this.coordinator,
    required this.onStateChanged,
    MethodChannel channel = const MethodChannel('cadpilot/spatial'),
  }) : _channel = channel;

  final ArSessionCoordinator coordinator;
  final void Function(ArSessionState state) onStateChanged;
  final MethodChannel _channel;
  bool _listening = false;

  bool get isListening => _listening;

  void start() {
    if (_listening) return;
    _channel.setMethodCallHandler(handle);
    _listening = true;
  }

  void dispose() {
    if (!_listening) return;
    _channel.setMethodCallHandler(null);
    _listening = false;
  }

  Future<Object?> handle(MethodCall call) async {
    if (call.method != 'arSessionEvent') {
      throw MissingPluginException(
          'Unsupported native spatial callback: ${call.method}.');
    }
    final arguments = call.arguments;
    if (arguments is! Map<Object?, Object?>) {
      throw const FormatException(
          'Native AR session event arguments must be a map.');
    }
    final accepted = coordinator.consume(
      ArSessionEventEnvelope.fromMap(arguments),
    );
    if (accepted) onStateChanged(coordinator.state);
    return {'accepted': accepted, 'sequence': coordinator.lastSequence};
  }
}
