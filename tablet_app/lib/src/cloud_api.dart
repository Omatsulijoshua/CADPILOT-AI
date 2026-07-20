import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'ai_planning.dart';
import 'ai_starter_templates.dart';

const maxAiCommandRequestBytes = 64 * 1024;

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

class AiUsageMonth {
  const AiUsageMonth({
    required this.start,
    required this.end,
    required this.limitTokens,
    required this.totalTokens,
    required this.inputTokens,
    required this.outputTokens,
    required this.requestCount,
    required this.remainingTokens,
  });

  final DateTime start;
  final DateTime end;
  final int? limitTokens;
  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final int requestCount;
  final int? remainingTokens;

  factory AiUsageMonth.fromMap(Map<String, Object?> value) => AiUsageMonth(
        start: DateTime.parse(value['start']! as String).toUtc(),
        end: DateTime.parse(value['end']! as String).toUtc(),
        limitTokens: value['limitTokens'] as int?,
        totalTokens: value['totalTokens']! as int,
        inputTokens: value['inputTokens']! as int,
        outputTokens: value['outputTokens']! as int,
        requestCount: value['requestCount']! as int,
        remainingTokens: value['remainingTokens'] as int?,
      );
}

class AiProjectUsage {
  const AiProjectUsage({
    required this.projectId,
    required this.projectName,
    required this.totalTokens,
    required this.inputTokens,
    required this.outputTokens,
    required this.requestCount,
    required this.lastUsedAt,
  });

  final String? projectId;
  final String? projectName;
  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final int requestCount;
  final DateTime? lastUsedAt;

  factory AiProjectUsage.fromMap(Map<String, Object?> value) => AiProjectUsage(
        projectId: value['projectId'] as String?,
        projectName: value['projectName'] as String?,
        totalTokens: value['totalTokens']! as int,
        inputTokens: value['inputTokens']! as int,
        outputTokens: value['outputTokens']! as int,
        requestCount: value['requestCount']! as int,
        lastUsedAt: value['lastUsedAt'] == null
            ? null
            : DateTime.parse(value['lastUsedAt']! as String).toUtc(),
      );
}

class AiUsageSummary {
  const AiUsageSummary({required this.month, required this.projects});
  final AiUsageMonth month;
  final List<AiProjectUsage> projects;

  factory AiUsageSummary.fromMap(Map<String, Object?> value) => AiUsageSummary(
        month: AiUsageMonth.fromMap(
            Map<String, Object?>.from(value['month']! as Map)),
        projects: (value['projects']! as List<Object?>)
            .map((item) =>
                AiProjectUsage.fromMap(Map<String, Object?>.from(item! as Map)))
            .toList(growable: false),
      );
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

class CloudProjectChange {
  const CloudProjectChange({
    required this.mutationId,
    required this.baseRevision,
    required this.appliedRevision,
    required this.status,
    required this.createdAt,
    required this.actorName,
    required this.actorEmail,
  });

  final String mutationId;
  final int baseRevision;
  final int? appliedRevision;
  final String status;
  final DateTime createdAt;
  final String? actorName;
  final String? actorEmail;

  factory CloudProjectChange.fromMap(Map<String, Object?> value) {
    final mutationId = value['mutationId'] as String?;
    final baseRevision = value['baseRevision'] as int?;
    final appliedRevision = value['appliedRevision'] as int?;
    final status = value['status'] as String?;
    final createdAt = DateTime.tryParse(value['createdAt'] as String? ?? '');
    final actor = value['actor'] is Map
        ? Map<String, Object?>.from(value['actor']! as Map)
        : null;
    if (mutationId == null ||
        mutationId.trim().isEmpty ||
        baseRevision == null ||
        baseRevision < 0 ||
        (appliedRevision != null && appliedRevision < 1) ||
        status == null ||
        status.trim().isEmpty ||
        createdAt == null) {
      throw const FormatException('Invalid cloud project change.');
    }
    return CloudProjectChange(
      mutationId: mutationId,
      baseRevision: baseRevision,
      appliedRevision: appliedRevision,
      status: status,
      createdAt: createdAt.toUtc(),
      actorName: actor?['displayName'] as String?,
      actorEmail: actor?['email'] as String?,
    );
  }
}

class CloudProjectMember {
  const CloudProjectMember({
    required this.displayName,
    required this.email,
    required this.role,
  });

  final String displayName;
  final String email;
  final String role;

  factory CloudProjectMember.fromMap(Map<String, Object?> value) {
    final role = value['role'] as String?;
    final user = value['user'] is Map
        ? Map<String, Object?>.from(value['user']! as Map)
        : null;
    final email = user?['email'] as String?;
    final displayName = user?['displayName'] as String?;
    if (role == null ||
        role.trim().isEmpty ||
        email == null ||
        !email.contains('@') ||
        displayName == null ||
        displayName.trim().isEmpty) {
      throw const FormatException('Invalid project member.');
    }
    return CloudProjectMember(
        displayName: displayName, email: email, role: role);
  }
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
    final requestBody = jsonEncode({
      'prompt': prompt,
      'projectId': project.id,
      'context': {
        'sketch': project.sketch.toJson(),
        'model': project.model.toJson(),
      }
    });
    if (utf8.encode(requestBody).length > maxAiCommandRequestBytes) {
      throw const CloudApiException(
          'This project is too large for an AI command. Simplify the sketch or model and try again.',
          413);
    }
    final response = await client.post(Uri.parse('$baseUrl/ai/commands'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token'
        },
        body: requestBody);
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

  Future<AiPlanResponse> generateAiPlan(
      {required String prompt,
      required CadProject project,
      required String token}) async {
    final requestBody = jsonEncode({
      'prompt': prompt,
      'projectId': project.id,
      'context': {
        'sketch': project.sketch.toJson(),
        'model': project.model.toJson()
      }
    });
    if (utf8.encode(requestBody).length > maxAiCommandRequestBytes) {
      throw const CloudApiException(
          'This project is too large for AI planning.', 413);
    }
    final response = await client.post(Uri.parse('$baseUrl/ai/plans'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token'
        },
        body: requestBody);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
          response.statusCode == 503
              ? 'AI planning is temporarily unavailable.'
              : 'AI planning failed.',
          response.statusCode);
    }
    try {
      final body = Map<String, Object?>.from(jsonDecode(response.body) as Map);
      final usage = Map<String, Object?>.from(body['usage']! as Map);
      return AiPlanResponse(
          AiDesignPlan.fromMap(Map<String, Object?>.from(body['plan']! as Map)),
          usage['totalTokens']! as int);
    } catch (_) {
      throw const CloudApiException('The AI plan response was invalid.');
    }
  }

  Future<AiCommandResponse> generateAiCommandFromPlan(
      {required String prompt,
      required AiDesignPlan plan,
      required AiPlanOption option,
      required Map<String, String> answers,
      required CadProject project,
      required String token}) async {
    final response = await client.post(Uri.parse('$baseUrl/ai/plans/command'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token'
        },
        body: jsonEncode({
          'prompt': prompt,
          'projectId': project.id,
          'plan': plan.raw,
          'selectedOptionId': option.id,
          'answers': answers,
          'context': {
            'sketch': project.sketch.toJson(),
            'model': project.model.toJson()
          }
        }));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = response.statusCode == 400
          ? 'This plan needs the listed preparation before CAD generation.'
          : 'AI command generation failed.';
      try {
        final body = jsonDecode(response.body) as Map;
        if (body['message'] is String) message = body['message'] as String;
      } catch (_) {}
      throw CloudApiException(message, response.statusCode);
    }
    final body = Map<String, Object?>.from(jsonDecode(response.body) as Map);
    final usage = Map<String, Object?>.from(body['usage']! as Map);
    return AiCommandResponse(
        command: Map<String, Object?>.from(body['command']! as Map),
        totalTokens: usage['totalTokens']! as int);
  }

  Future<AiUsageSummary> getAiUsage(String token) async {
    final response = await client.get(Uri.parse('$baseUrl/ai/usage'),
        headers: {'authorization': 'Bearer $token'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException('Could not load AI usage.', response.statusCode);
    }
    try {
      return AiUsageSummary.fromMap(
          Map<String, Object?>.from(jsonDecode(response.body) as Map));
    } catch (_) {
      throw const CloudApiException('AI usage response is invalid.');
    }
  }

  Future<void> saveAiStarterTemplate(
      LearnedStarterTemplate template, String token) async {
    final response = await client.post(
      Uri.parse('$baseUrl/ai/starter-templates'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token'
      },
      body: jsonEncode({
        'key': template.key,
        'title': template.title,
        'objectType': template.title,
        'promptHint': template.key,
        'components':
            template.components.map((component) => component.toJson()).toList(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
          'Could not save the AI starter template.', response.statusCode);
    }
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

  Future<List<CloudProjectChange>> listProjectChanges(
      String projectId, String token) async {
    if (projectId.trim().isEmpty) {
      throw ArgumentError.value(projectId, 'projectId', 'must not be empty');
    }
    final response = await client.get(
      Uri.parse('$baseUrl/projects/$projectId/changes'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
        response.statusCode == 404
            ? 'No cloud history was found for this project.'
            : 'Could not load cloud project history.',
        response.statusCode,
      );
    }
    try {
      final values = jsonDecode(response.body) as List<Object?>;
      return values
          .map((value) => CloudProjectChange.fromMap(
                Map<String, Object?>.from(value! as Map),
              ))
          .toList(growable: false);
    } catch (_) {
      throw const CloudApiException(
        'Cloud project history is invalid and could not be displayed.',
      );
    }
  }

  Future<List<CloudProjectMember>> listProjectMembers(
      String projectId, String token) async {
    final response = await client.get(
      Uri.parse('$baseUrl/projects/$projectId/members'),
      headers: {'authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
          'Could not load project collaborators.', response.statusCode);
    }
    try {
      final values = jsonDecode(response.body) as List<Object?>;
      return values
          .map((value) => CloudProjectMember.fromMap(
              Map<String, Object?>.from(value! as Map)))
          .toList(growable: false);
    } catch (_) {
      throw const CloudApiException('Project collaborators are invalid.');
    }
  }

  Future<List<CloudProjectMember>> addProjectMember(
      String projectId, String email, String role, String token) async {
    final response = await client.post(
      Uri.parse('$baseUrl/projects/$projectId/members'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token'
      },
      body: jsonEncode({'email': email.trim().toLowerCase(), 'role': role}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(
          response.statusCode == 404
              ? 'No user was found for that email, or you do not own this project.'
              : 'Could not update project collaborator.',
          response.statusCode);
    }
    try {
      final values = jsonDecode(response.body) as List<Object?>;
      return values
          .map((value) => CloudProjectMember.fromMap(
              Map<String, Object?>.from(value! as Map)))
          .toList(growable: false);
    } catch (_) {
      throw const CloudApiException('Project collaborators are invalid.');
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
