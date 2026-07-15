import 'package:cadpilot_tablet/src/spatial_session.dart';
import 'package:cadpilot_tablet/src/spatial_session_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('method channel bridge reports accepted and stale native callbacks',
      () async {
    final states = <ArSessionState>[];
    final bridge = ArSessionMethodChannelBridge(
      coordinator: ArSessionCoordinator(sessionId: 'active'),
      onStateChanged: states.add,
      channel: const MethodChannel('cadpilot/spatial-bridge-test'),
    );
    bridge.start();
    expect(bridge.isListening, isTrue);

    final accepted = await bridge.handle(const MethodCall('arSessionEvent', {
      'sessionId': 'active',
      'sequence': 0,
      'event': 'start',
    })) as Map<Object?, Object?>;
    expect(accepted['accepted'], isTrue);
    expect(accepted['sequence'], 0);
    expect(states.single.phase, ArSessionPhase.initializing);

    final stale = await bridge.handle(const MethodCall('arSessionEvent', {
      'sessionId': 'expired',
      'sequence': 40,
      'event': 'stop',
    })) as Map<Object?, Object?>;
    expect(stale['accepted'], isFalse);
    expect(states, hasLength(1));
    expect(bridge.coordinator.state.phase, ArSessionPhase.initializing);

    bridge.dispose();
    expect(bridge.isListening, isFalse);
  });

  test(
      'method channel bridge rejects unknown callbacks and malformed arguments',
      () async {
    final bridge = ArSessionMethodChannelBridge(
      coordinator: ArSessionCoordinator(sessionId: 'active'),
      onStateChanged: (_) {},
    );
    expect(
      () => bridge.handle(const MethodCall('unexpected')),
      throwsA(isA<MissingPluginException>()),
    );
    expect(
      () => bridge.handle(const MethodCall('arSessionEvent', 'not-a-map')),
      throwsFormatException,
    );
  });
}
