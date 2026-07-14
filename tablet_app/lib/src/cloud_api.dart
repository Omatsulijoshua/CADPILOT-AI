import 'dart:convert';
import 'package:http/http.dart' as http;
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

  Future<CloudCredentials> login(String email, String password) async {
    final response = await client.post(Uri.parse('$baseUrl/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}));
    if (response.statusCode != 201) {
      throw CloudApiException(
          'Could not sign in. Check your details and connection.',
          response.statusCode);
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final user = body['user']! as Map<String, Object?>;
    return CloudCredentials(
      session: Session(
          kind: SessionKind.signedIn,
          displayName: user['displayName']! as String,
          email: user['email']! as String),
      accessToken: body['accessToken']! as String,
      refreshToken: body['refreshToken']! as String,
    );
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

  Future<void> pushProject(CadProject project, String token) async {
    final response = await client.post(
        Uri.parse('$baseUrl/projects/${project.id}/sync'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token'
        },
        body: jsonEncode({
          'mutationId': project.id,
          'baseRevision': project.revision,
          'payload': project.toJson()
        }));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException('Project sync failed', response.statusCode);
    }
  }
}
