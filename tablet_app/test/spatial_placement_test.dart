import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/spatial_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spatial placement round-trips through project storage', () {
    final now = DateTime.utc(2026, 7, 14);
    final placement = SpatialPlacement(
      id: 'placement-1',
      name: 'Lobby wall',
      createdAt: now,
      source: 'manual',
      plane: 'wall',
      widthMm: 2400,
      heightMm: 1800,
      depthMm: 400,
      offsetXMm: 25,
      offsetYMm: 50,
      offsetZMm: 1200,
      rotationDegrees: 90,
    );
    final project = CadProject(
      id: 'project-1',
      name: 'Lobby',
      note: '',
      createdAt: now,
      updatedAt: now,
      revision: 1,
      syncState: SyncState.localOnly,
      spatialPlacements: [placement],
    );

    final restored = CadProject.fromJson(project.toJson());
    expect(restored.spatialPlacements, hasLength(1));
    expect(restored.spatialPlacements.single.name, 'Lobby wall');
    expect(restored.spatialPlacements.single.plane, 'wall');
    expect(restored.spatialPlacements.single.rotationDegrees, 90);
  });

  test('older projects default to no spatial placements', () {
    final now = DateTime.utc(2026, 7, 14).toIso8601String();
    final restored = CadProject.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'note': '',
      'createdAt': now,
      'updatedAt': now,
      'revision': 1,
      'syncState': 'localOnly',
    });
    expect(restored.spatialPlacements, isEmpty);
  });

  test('copyWith preserves identity while updating placement transforms', () {
    final original = SpatialPlacement(
      id: 'placement-1',
      name: 'Original',
      createdAt: DateTime.utc(2026, 7, 14),
      source: 'manual',
      plane: 'floor',
      widthMm: 100,
      heightMm: 200,
      depthMm: 300,
      offsetXMm: 0,
      offsetYMm: 0,
      offsetZMm: 0,
      rotationDegrees: 0,
    );
    final edited = original.copyWith(
      name: 'Edited',
      plane: 'wall',
      offsetZMm: 500,
      rotationDegrees: 90,
    );
    expect(edited.id, original.id);
    expect(edited.createdAt, original.createdAt);
    expect(edited.name, 'Edited');
    expect(edited.plane, 'wall');
    expect(edited.offsetZMm, 500);
    expect(edited.widthMm, 100);
  });

  test('placement lock and true scale persist safely', () {
    final placement = SpatialPlacement(
      id: 'locked-1',
      name: 'Installed unit',
      createdAt: DateTime.utc(2026, 7, 14),
      source: 'camera_ar',
      plane: 'floor',
      widthMm: 500,
      heightMm: 900,
      depthMm: 400,
      offsetXMm: 10,
      offsetYMm: 20,
      offsetZMm: 0,
      rotationDegrees: 15,
      isLocked: true,
    );
    final restored = SpatialPlacement.fromJson(placement.toJson());
    expect(restored.isLocked, isTrue);
    expect(restored.toJson()['scale'], SpatialPlacement.trueScale);
    expect(restored.copyWith(isLocked: false).isLocked, isFalse);
    expect(restored.copyWith(isLocked: false).id, placement.id);
  });

  test('native anchor lifecycle persists and duplication can detach safely',
      () {
    final now = DateTime.utc(2026, 7, 14);
    final placement = SpatialPlacement(
      id: 'placement-anchor',
      name: 'Pump',
      createdAt: now,
      source: 'camera_ar',
      plane: 'floor',
      widthMm: 500,
      heightMm: 700,
      depthMm: 400,
      offsetXMm: 0,
      offsetYMm: 0,
      offsetZMm: 0,
      rotationDegrees: 0,
    );
    final anchored = placement.attachAnchor(SpatialAnchor(
      id: 'native-anchor-42',
      platform: 'android',
      trackingState: SpatialTrackingState.tracking,
      updatedAt: now,
    ));
    final restored = SpatialPlacement.fromJson(anchored.toJson());
    expect(restored.anchor?.id, 'native-anchor-42');
    expect(restored.anchor?.trackingState, SpatialTrackingState.tracking);

    final limited = restored.anchor!.copyWith(
      trackingState: SpatialTrackingState.limited,
      updatedAt: now.add(const Duration(seconds: 1)),
    );
    expect(restored.attachAnchor(limited).anchor?.trackingState,
        SpatialTrackingState.limited);
    expect(restored.detachAnchor().anchor, isNull);
    expect(restored.detachAnchor().isLocked, isFalse);
  });

  test('floor placement converts millimetres to shared native AR transform',
      () {
    final placement = SpatialPlacement(
      id: 'transform-1',
      name: 'Floor unit',
      createdAt: DateTime.utc(2026, 7, 14),
      source: 'camera_ar',
      plane: 'floor',
      widthMm: 1200,
      heightMm: 800,
      depthMm: 600,
      offsetXMm: 1500,
      offsetYMm: 2000,
      offsetZMm: 250,
      rotationDegrees: 90,
    );
    final native = placement.toFloorAnchorTransform();
    expect(native.widthMeters, 1.2);
    expect(native.heightMeters, 0.8);
    expect(native.depthMeters, 0.6);
    expect(native.matrixColumnMajor[12], 1.5);
    expect(native.matrixColumnMajor[13], 0.25);
    expect(native.matrixColumnMajor[14], -2.0);
    expect(native.matrixColumnMajor[0], closeTo(0, 1e-12));
    expect(native.matrixColumnMajor[2], closeTo(-1, 1e-12));
    expect(native.matrixColumnMajor[8], closeTo(1, 1e-12));
    expect(native.matrixColumnMajor[15], 1);
  });

  test('floor transform rejects a mismatched anchor plane', () {
    final placement = SpatialPlacement(
      id: 'transform-wall',
      name: 'Wall unit',
      createdAt: DateTime.utc(2026, 7, 14),
      source: 'manual',
      plane: 'wall',
      widthMm: 100,
      heightMm: 100,
      depthMm: 100,
      offsetXMm: 0,
      offsetYMm: 0,
      offsetZMm: 0,
      rotationDegrees: 0,
    );
    expect(placement.toFloorAnchorTransform, throwsArgumentError);
  });
}
