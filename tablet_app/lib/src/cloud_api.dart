import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'models.dart';

class CloudCredentials {
  const CloudCredentials(
      {required this.session,
      required this.accessToken,
      required this.refreshToken});
  final Session session;
  final String accessToken;
  final String refreshToken;
}

class AiCommandResponse {
  const AiCommandResponse({required this.command, required this.totalTokens});
  final Map<String, Object?> command;
  final int totalTokens;
}

class CloudProjectSummary {
  const CloudProjectSummary({
    required this.id,
    required this.name,
    required this.revision,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int revision;
  final DateTime updatedAt;

  factory CloudProjectSummary.fromMap(Map<String, Object?> value) {
    final id = value['id'] as String?;
    final name = value['name'] as String?;
    final revision = value['revision'] as int?;
    final updatedAt = DateTime.tryParse(value['updatedAt'] as String? ?? '');
    if (id == null ||
        id.trim().isEmpty ||
        name == null ||
        name.trim().isEmpty ||
        revision == null ||
        revision < 1 ||
        updatedAt == null) {
      throw const FormatException('Invalid cloud project summary.');
    }
    return CloudProjectSummary(
      id: id,
      name: name,
      revision: revision,
      updatedAt: updatedAt.toUtc(),
    );
  }
}

class ProjectSyncResult {
  const ProjectSyncResult({
    required this.mutationId,
    required this.appliedRevision,
  });

  final String mutationId;
  final int appliedRevision;
}

class CloudApiException implements Exception {
  const CloudApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class CloudApi {
  CloudApi({http.Client? client, String? baseUrl})
      : client = client ?? http.Client(),
        baseUrl = baseUrl ??
            const String.fromEnvironment('CADPILOT_API_URL',
                defaultValue: 'http://10.0.2.2:3000/v1');
  final http.Client client;
  final String baseUrl;

  Future<CloudCredentials> register(
    String displayName,
    String email,
    String password,
  ) async {
    final response = await client.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'displayName': displayName.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      }),
    );
    if (response.statusCode != 201) {
      throw CloudApiException(
        response.statusCode == 409
            ? 'An account already exists for this email.'
            : 'Could not create your account. Check your details and connection.',
        response.statusCode,
      );
    }
    return _credentials(response);
  }

  Future<CloudCredentials> login(String email, String password) async {
    final response = await client.post(Uri.parse('$baseUrl/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}));
    if (response.statusCode != 201) {
      throw CloudApiException(
          'Could not sign in. Check your details and connection.',
          response.statusCode);
    }
    return _credentials(response);
  }

  Future<CloudCredentials> refreshSession(String refreshToken) async {
    final response = await client.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (response.statusCode != 201) {
      throw CloudApiException(
        response.statusCode == 400 || response.statusCode == 401
            ? 'Your cloud session has expired. Sign in again.'
            : 'Could not refresh the cloud session.',
        response.statusCode,
      );
    }
    return _credentials(response);
  }

  Future<void> logout(String refreshToken) async {
    final response = await client.post(
      Uri.parse('$baseUrl/auth/logout'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
        'Could not revoke the cloud session.',
        response.statusCode,
      );
    }
  }

  CloudCredentials _credentials(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, Object?>;
      final user = body['user']! as Map<String, Object?>;
      final displayName = user['displayName'] as String?;
      final email = user['email'] as String?;
      final accessToken = body['accessToken'] as String?;
      final refreshToken = body['refreshToken'] as String?;
      if (displayName == null ||
          displayName.trim().isEmpty ||
          email == null ||
          !email.contains('@') ||
          accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        throw const FormatException('Invalid authentication response.');
      }
      return CloudCredentials(
        session: Session(
          kind: SessionKind.signedIn,
          displayName: displayName,
          email: email,
        ),
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } catch (_) {
      throw const CloudApiException(
        'The authentication response was invalid. Please try again.',
      );
    }
  }

  Future<AiCommandResponse> generateAiCommand({
    required String prompt,
    required CadProject project,
    required String token,
  }) async {
    final response = await client.post(Uri.parse('$baseUrl/ai/commands'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token'
        },
        body: jsonEncode({
          'prompt': prompt,
          'context': {
            'sketch': project.sketch.toJson(),
            'model': project.model.toJson(),
          }
        }));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
          response.statusCode == 503
              ? 'AI commands are not configured or temporarily unavailable.'
              : 'AI command generation failed.',
          response.statusCode);
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final usage = body['usage']! as Map<String, Object?>;
    return AiCommandResponse(
      command: Map<String, Object?>.from(body['command']! as Map),
      totalTokens: usage['totalTokens']! as int,
    );
  }

  Future<void> archiveProject(String projectId, String token) async {
    final response = await client.delete(
      Uri.parse('$baseUrl/projects/$projectId'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
        response.statusCode == 404
            ? 'No active cloud project was found to archive.'
            : 'Could not archive the cloud project.',
        response.statusCode,
      );
    }
  }

  Future<List<CloudProjectSummary>> listProjects(String token) async {
    final response = await client.get(
      Uri.parse('$baseUrl/projects'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
        'Could not load cloud projects.',
        response.statusCode,
      );
    }
    try {
      final values = jsonDecode(response.body) as List<Object?>;
      return values
          .map((value) => CloudProjectSummary.fromMap(
                Map<String, Object?>.from(value! as Map),
              ))
          .toList(growable: false);
    } catch (_) {
      throw const CloudApiException(
        'Cloud project list is invalid and could not be displayed.',
      );
    }
  }

  Future<CadProject> pullProject(String projectId, String token) async {
    if (projectId.trim().isEmpty) {
      throw ArgumentError.value(projectId, 'projectId', 'must not be empty');
    }
    final response = await client.get(
      Uri.parse('$baseUrl/projects/$projectId'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
        response.statusCode == 404
            ? 'No cloud backup was found for this project.'
            : 'Could not download the cloud project.',
        response.statusCode,
      );
    }
    try {
      final body = jsonDecode(response.body) as Map<String, Object?>;
      final revision = body['revision'] as int?;
      final manifest = body['manifest'];
      if (revision == null || revision < 1 || manifest is! Map) {
        throw const FormatException('Invalid cloud project envelope.');
      }
      final project = CadProject.fromJson(
        Map<String, Object?>.from(manifest),
      );
      if (project.id != projectId) {
        throw const FormatException('Cloud project identity mismatch.');
      }
      return project.markSynced(revision);
    } on CloudApiException {
      rethrow;
    } catch (_) {
      throw const CloudApiException(
        'Cloud project data is invalid and was not restored.',
      );
    }
  }

  Future<ProjectSyncResult> pushProject(
    CadProject project,
    String token, {
    String? mutationId,
  }) async {
    final requestId = mutationId ??
        const Uuid().v5(
          Namespace.url.value,
          'cadpilot:${project.id}:${project.revision}:${project.lastSyncedRevision ?? 0}',
        );
    final response = await client.post(
        Uri.parse('$baseUrl/projects/${project.id}/sync'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token'
        },
        body: jsonEncode({
          'mutationId': requestId,
          'baseRevision': project.lastSyncedRevision ?? 0,
          'payload': project.toJson()
        }));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
        response.statusCode == 409
            ? 'Project changed in the cloud. Refresh before backing up again.'
            : 'Project sync failed.',
        response.statusCode,
      );
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final appliedRevision = body['appliedRevision'] as int?;
    if (appliedRevision == null || appliedRevision < 1) {
      throw const CloudApiException(
          'Project sync returned an invalid revision.');
    }
    return ProjectSyncResult(
      mutationId: body['mutationId'] as String? ?? requestId,
      appliedRevision: appliedRevision,
    );
  }
}
