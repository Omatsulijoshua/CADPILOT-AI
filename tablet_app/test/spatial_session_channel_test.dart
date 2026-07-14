import 'package:cadpilot_tablet/src/spatial_session.dart';
import 'package:cadpilot_tablet/src/spatial_session_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native AR envelopes decode and advance only the active session', () {
    final coordinator = ArSessionCoordinator(sessionId: 'session-a');
    expect(
      coordinator.consume(ArSessionEventEnvelope.fromMap(const {
        'sessionId': 'session-a',
        'sequence': 0,
        'event': 'start',
      })),
      isTrue,
    );
    expect(
      coordinator.consume(ArSessionEventEnvelope.fromMap(const {
        'sessionId': 'session-a',
        'sequence': 1,
        'event': 'sessionReady',
      })),
      isTrue,
    );
    expect(
      coordinator.consume(ArSessionEventEnvelope.fromMap(const {
        'sessionId': 'session-a',
        'sequence': 2,
        'event': 'planeFound',
        'planeId': 'floor-7',
      })),
      isTrue,
    );
    expect(coordinator.state.phase, ArSessionPhase.planeReady);
    expect(coordinator.state.planeId, 'floor-7');
    expect(coordinator.lastSequence, 2);
  });

  test('stale sessions are ignored and out-of-order events fail closed', () {
    final coordinator = ArSessionCoordinator(sessionId: 'current');
    final stale = ArSessionEventEnvelope.fromMap(const {
      'sessionId': 'previous',
      'sequence': 99,
      'event': 'stop',
    });
    expect(coordinator.consume(stale), isFalse);
    expect(coordinator.state.phase, ArSessionPhase.idle);
    expect(coordinator.lastSequence, -1);

    coordinator.consume(ArSessionEventEnvelope.fromMap(const {
      'sessionId': 'current',
      'sequence': 4,
      'event': 'start',
    }));
    expect(
      () => coordinator.consume(ArSessionEventEnvelope.fromMap(const {
        'sessionId': 'current',
        'sequence': 4,
        'event': 'sessionReady',
      })),
      throwsStateError,
    );
    expect(coordinator.state.phase, ArSessionPhase.initializing);
    expect(coordinator.lastSequence, 4);
  });

  test('malformed native AR envelopes are rejected before state mutation', () {
    expect(
      () => ArSessionEventEnvelope.fromMap(const {
        'sessionId': '',
        'sequence': 0,
        'event': 'start',
      }),
      throwsFormatException,
    );
    expect(
      () => ArSessionEventEnvelope.fromMap(const {
        'sessionId': 'session-a',
        'sequence': -1,
        'event': 'start',
      }),
      throwsFormatException,
    );
    expect(
      () => ArSessionEventEnvelope.fromMap(const {
        'sessionId': 'session-a',
        'sequence': 0,
        'event': 'mystery',
      }),
      throwsFormatException,
    );
  });
}
