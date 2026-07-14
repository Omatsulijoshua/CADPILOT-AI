import 'package:cadpilot_tablet/src/spatial_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AR session follows startup plane placement and anchor lifecycle', () {
    final initializing = ArSessionState.idle.transition(ArSessionEvent.start);
    final searching = initializing.transition(ArSessionEvent.sessionReady);
    final ready = searching.transition(
      ArSessionEvent.planeFound,
      planeId: 'floor-1',
    );
    final placing = ready.transition(ArSessionEvent.beginPlacement);
    final anchored = placing.transition(
      ArSessionEvent.anchorCreated,
      anchorId: 'anchor-1',
    );

    expect(initializing.phase, ArSessionPhase.initializing);
    expect(searching.phase, ArSessionPhase.searchingForPlane);
    expect(ready.canPlace, isTrue);
    expect(placing.planeId, 'floor-1');
    expect(anchored.hasNativeAnchor, isTrue);
    expect(anchored.anchorId, 'anchor-1');
  });

  test('lost plane and interrupted tracking recover through explicit states',
      () {
    final ready = ArSessionState.idle
        .transition(ArSessionEvent.start)
        .transition(ArSessionEvent.sessionReady)
        .transition(ArSessionEvent.planeFound, planeId: 'floor-2');
    final searching = ready.transition(ArSessionEvent.planeLost);
    final interrupted = searching.transition(
      ArSessionEvent.trackingInterrupted,
      message: 'Camera obscured.',
    );
    final resumed = interrupted.transition(ArSessionEvent.resumed);

    expect(searching.phase, ArSessionPhase.searchingForPlane);
    expect(interrupted.phase, ArSessionPhase.interrupted);
    expect(interrupted.message, 'Camera obscured.');
    expect(resumed.phase, ArSessionPhase.searchingForPlane);
  });

  test('invalid ordering and missing native identifiers fail closed', () {
    expect(
      () => ArSessionState.idle.transition(ArSessionEvent.anchorCreated),
      throwsStateError,
    );
    final searching = ArSessionState.idle
        .transition(ArSessionEvent.start)
        .transition(ArSessionEvent.sessionReady);
    expect(
      () => searching.transition(ArSessionEvent.planeFound),
      throwsArgumentError,
    );
    final failed = searching.transition(
      ArSessionEvent.fail,
      message: 'Native session unavailable.',
    );
    expect(failed.isTerminal, isTrue);
    expect(failed.transition(ArSessionEvent.start).phase,
        ArSessionPhase.initializing);
    expect(searching.transition(ArSessionEvent.stop).phase,
        ArSessionPhase.stopped);
  });
}
