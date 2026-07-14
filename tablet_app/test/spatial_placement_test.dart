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
}
