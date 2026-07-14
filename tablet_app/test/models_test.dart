import 'package:cadpilot_tablet/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project serialization round-trips without losing revision data', () {
    final now = DateTime.utc(2026, 7, 14);
    final project = CadProject(
        id: 'p1',
        name: 'Bracket',
        note: 'M6 holes',
        createdAt: now,
        updatedAt: now,
        revision: 3,
        syncState: SyncState.pending);
    final decoded = CadProject.fromJson(project.toJson());
    expect(decoded.name, 'Bracket');
    expect(decoded.revision, 3);
    expect(decoded.note, 'M6 holes');
  });
}
