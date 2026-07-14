enum ArSessionPhase {
  idle,
  initializing,
  searchingForPlane,
  planeReady,
  placing,
  anchored,
  interrupted,
  failed,
  stopped,
}

enum ArSessionEvent {
  start,
  sessionReady,
  planeFound,
  planeLost,
  beginPlacement,
  anchorCreated,
  trackingInterrupted,
  resumed,
  fail,
  stop,
}

class ArSessionState {
  const ArSessionState({
    required this.phase,
    this.planeId,
    this.anchorId,
    this.message,
  });

  static const idle = ArSessionState(phase: ArSessionPhase.idle);

  final ArSessionPhase phase;
  final String? planeId;
  final String? anchorId;
  final String? message;

  bool get canPlace => phase == ArSessionPhase.planeReady;
  bool get hasNativeAnchor =>
      phase == ArSessionPhase.anchored && anchorId != null;
  bool get isTerminal =>
      phase == ArSessionPhase.failed || phase == ArSessionPhase.stopped;

  ArSessionState transition(
    ArSessionEvent event, {
    String? planeId,
    String? anchorId,
    String? message,
  }) {
    if (event == ArSessionEvent.stop) {
      return const ArSessionState(phase: ArSessionPhase.stopped);
    }
    if (event == ArSessionEvent.fail) {
      return ArSessionState(
        phase: ArSessionPhase.failed,
        message: message ?? 'Native AR session failed.',
      );
    }
    if (event == ArSessionEvent.trackingInterrupted &&
        phase != ArSessionPhase.idle &&
        !isTerminal) {
      return ArSessionState(
        phase: ArSessionPhase.interrupted,
        planeId: this.planeId,
        anchorId: this.anchorId,
        message: message ?? 'Tracking interrupted.',
      );
    }

    return switch ((phase, event)) {
      (ArSessionPhase.idle, ArSessionEvent.start) ||
      (ArSessionPhase.failed, ArSessionEvent.start) ||
      (ArSessionPhase.stopped, ArSessionEvent.start) =>
        const ArSessionState(phase: ArSessionPhase.initializing),
      (ArSessionPhase.initializing, ArSessionEvent.sessionReady) ||
      (ArSessionPhase.interrupted, ArSessionEvent.resumed) =>
        const ArSessionState(phase: ArSessionPhase.searchingForPlane),
      (ArSessionPhase.searchingForPlane, ArSessionEvent.planeFound) =>
        ArSessionState(
          phase: ArSessionPhase.planeReady,
          planeId: _required(planeId, 'planeId', event),
        ),
      (ArSessionPhase.planeReady, ArSessionEvent.beginPlacement) =>
        ArSessionState(
          phase: ArSessionPhase.placing,
          planeId: this.planeId,
        ),
      (ArSessionPhase.placing, ArSessionEvent.anchorCreated) => ArSessionState(
          phase: ArSessionPhase.anchored,
          planeId: this.planeId,
          anchorId: _required(anchorId, 'anchorId', event),
        ),
      (ArSessionPhase.planeReady, ArSessionEvent.planeLost) ||
      (ArSessionPhase.placing, ArSessionEvent.planeLost) =>
        const ArSessionState(phase: ArSessionPhase.searchingForPlane),
      _ => throw StateError(
          'Invalid AR session transition: ${phase.name} -> ${event.name}.'),
    };
  }

  static String _required(String? value, String field, ArSessionEvent event) {
    if (value == null || value.trim().isEmpty) {
      throw ArgumentError('$field is required for ${event.name}.');
    }
    return value;
  }
}
