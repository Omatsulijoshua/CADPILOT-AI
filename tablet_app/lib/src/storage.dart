import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

abstract interface class LocalStore {
  Future<Session?> readSession();
  Future<void> writeSession(Session? session);
  Future<List<CadProject>> readProjects();
  Future<void> writeProjects(List<CadProject> projects);
}

class PreferencesLocalStore implements LocalStore {
  static const _sessionKey = 'cadpilot.session.v1';
  static const _projectsKey = 'cadpilot.projects.v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<Session?> readSession() async {
    final value = (await _prefs).getString(_sessionKey);
    return value == null
        ? null
        : Session.fromJson(jsonDecode(value) as Map<String, Object?>);
  }

  @override
  Future<void> writeSession(Session? session) async {
    final prefs = await _prefs;
    if (session == null) {
      await prefs.remove(_sessionKey);
    } else {
      await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    }
  }

  @override
  Future<List<CadProject>> readProjects() async {
    final value = (await _prefs).getString(_projectsKey);
    if (value == null) return const [];
    final decoded = jsonDecode(value) as List<Object?>;
    return decoded
        .map((item) => CadProject.fromJson(item! as Map<String, Object?>))
        .toList();
  }

  @override
  Future<void> writeProjects(List<CadProject> projects) async {
    await (await _prefs).setString(
      _projectsKey,
      jsonEncode(projects.map((project) => project.toJson()).toList()),
    );
  }
}
