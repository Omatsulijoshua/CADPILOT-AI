import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';

const projectManifestSchemaVersion = 1;
const maxProjectManifestBytes = 2 * 1024 * 1024;

/// A portable, versioned wrapper around a CadPilot project.
///
/// Version 1 is deliberately small and self-contained. Raw project JSON from
/// earlier CadPilot releases remains accepted as a legacy manifest.
class ProjectManifest {
  const ProjectManifest({
    required this.project,
    required this.exportedAt,
    this.schemaVersion = projectManifestSchemaVersion,
  });

  final CadProject project;
  final DateTime exportedAt;
  final int schemaVersion;

  Map<String, Object?> toJson() {
    final projectJson = project.toJson();
    return {
      'schemaVersion': schemaVersion,
      'format': 'cadpilot-project',
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'project': projectJson,
      'integrity': {'algorithm': 'sha256', 'digest': _digest(projectJson)},
    };
  }

  static ProjectManifest parse(String content) {
    if (utf8.encode(content).length > maxProjectManifestBytes) {
      throw const FormatException('Project manifest is larger than 2 MiB.');
    }
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('Project manifest must be a JSON object.');
      }
      return fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Project manifest is invalid or incomplete.');
    }
  }

  static ProjectManifest fromJson(Map<String, Object?> json) {
    // CadPilot exports before schema versioning stored the project at the root.
    if (json.containsKey('id')) {
      return ProjectManifest(
        project: CadProject.fromJson(json),
        exportedAt: DateTime.now().toUtc(),
      );
    }

    final version = json['schemaVersion'];
    if (version is! int) {
      throw const FormatException(
          'Project manifest is missing a schema version.');
    }
    if (version != projectManifestSchemaVersion) {
      throw FormatException(
          'Project manifest version $version is not supported.');
    }
    if (json['format'] != 'cadpilot-project') {
      throw const FormatException(
          'This file is not a CadPilot project manifest.');
    }
    final project = json['project'];
    if (project is! Map) {
      throw const FormatException(
          'Project manifest is missing its project data.');
    }
    final exportedAt = json['exportedAt'];
    if (exportedAt is! String) {
      throw const FormatException(
          'Project manifest is missing its export time.');
    }
    _verifyIntegrity(json['integrity'], Map<String, Object?>.from(project));
    return ProjectManifest(
      project: CadProject.fromJson(Map<String, Object?>.from(project)),
      exportedAt: DateTime.parse(exportedAt).toUtc(),
      schemaVersion: version,
    );
  }

  static void _verifyIntegrity(
      Object? integrity, Map<String, Object?> project) {
    // Integrity metadata was introduced after the first versioned exports.
    // It remains optional for backward compatibility, but must be valid if present.
    if (integrity == null) return;
    if (integrity is! Map ||
        integrity['algorithm'] != 'sha256' ||
        integrity['digest'] is! String) {
      throw const FormatException(
          'Project manifest integrity metadata is invalid.');
    }
    if (integrity['digest'] != _digest(project)) {
      throw const FormatException('Project manifest integrity check failed.');
    }
  }

  static String _digest(Map<String, Object?> project) =>
      sha256.convert(utf8.encode(jsonEncode(project))).toString();
}
