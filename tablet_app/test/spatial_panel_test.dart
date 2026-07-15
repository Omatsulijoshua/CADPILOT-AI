import 'package:cadpilot_tablet/src/spatial.dart';
import 'package:cadpilot_tablet/src/spatial_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('spatial workspace remains scrollable with many placements',
      (tester) async {
    const channel = MethodChannel('cadpilot/spatial-panel-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => const {
                  'platform': 'test',
                  'cameraSupported': false,
                  'arSupported': false,
                  'lidarSupported': false,
                  'sceneDepthSupported': false,
                  'meshReconstructionSupported': false,
                  'planeDetectionSupported': false,
                  'motionTrackingSupported': false,
                  'captureMethod': 'manual',
                });
    final createdAt = DateTime.utc(2026, 7, 15);
    final placements = List.generate(
      30,
      (index) => SpatialPlacement(
        id: 'placement-$index',
        name: 'Placement $index',
        createdAt: createdAt,
        source: 'manual',
        plane: 'floor',
        widthMm: 100,
        heightMm: 100,
        depthMm: 100,
        offsetXMm: 0,
        offsetYMm: 0,
        offsetZMm: 0,
        rotationDegrees: 0,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SpatialCapabilityPanel(
          projectName: 'Large project',
          service: const SpatialCapabilityService(channel: channel),
          placements: placements,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Saved placements (30)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Placement 29'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
