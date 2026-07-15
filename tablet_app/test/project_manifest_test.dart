import 'dart:convert';

import 'package:cadpilot_tablet/src/models.dart';
import 'package:cadpilot_tablet/src/project_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final project = CadProject(
    id: 'portable-cabinet',
    name: 'Portable cabinet',
    note: 'Keep the dimensions.',
    createdAt: DateTime.utc(2026, 7, 15),
    updatedAt: DateTime.utc(2026, 7, 15, 1),
    revision: 4,
    syncState: SyncState.localOnly,
  );

  test('round trips a versioned portable project manifest', () {
    final manifest = ProjectManifest(
      project: project,
      exportedAt: DateTime.utc(2026, 7, 15, 2),
    );

    final parsed = ProjectManifest.parse(jsonEncode(manifest.toJson()));

    expect(parsed.schemaVersion, projectManifestSchemaVersion);
    expect(parsed.project.id, project.id);
    expect(parsed.project.name, project.name);
    expect(parsed.exportedAt, DateTime.utc(2026, 7, 15, 2));
    expect(manifest.toJson()['integrity'], isNotNull);
  });

  test('accepts a legacy root-level project export', () {
    final parsed = ProjectManifest.parse(jsonEncode(project.toJson()));

    expect(parsed.project.id, project.id);
    expect(parsed.project.name, project.name);
  });

  test('rejects unsupported or malformed portable manifests', () {
    expect(
      () => ProjectManifest.parse(
        jsonEncode({
          'schemaVersion': 99,
          'format': 'cadpilot-project',
          'exportedAt': '2026-07-15T02:00:00.000Z',
          'project': project.toJson(),
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => ProjectManifest.parse('{"schemaVersion": 1}'),
      throwsFormatException,
    );
  });

  test('rejects a versioned manifest whose project data was altered', () {
    final json = ProjectManifest(
      project: project,
      exportedAt: DateTime.utc(2026, 7, 15, 2),
    ).toJson();
    final alteredProject = Map<String, Object?>.from(json['project']! as Map)
      ..['name'] = 'Altered project';
    final altered = {...json, 'project': alteredProject};

    expect(
      () => ProjectManifest.parse(jsonEncode(altered)),
      throwsFormatException,
    );
  });
}
