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
