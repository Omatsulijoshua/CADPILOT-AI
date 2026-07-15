import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'cloud_api.dart';
import 'models.dart';
import 'storage.dart';
import 'token_store.dart';

final localStoreProvider =
    Provider<LocalStore>((ref) => PreferencesLocalStore());
final cloudApiProvider = Provider<CloudApi>((ref) => CloudApi());
final tokenStoreProvider =
    Provider<TokenStore>((ref) => const SecureTokenStore());
final sessionProvider = AsyncNotifierProvider<SessionController, Session?>(
  SessionController.new,
);
final projectsProvider =
    AsyncNotifierProvider<ProjectsController, List<CadProject>>(
  ProjectsController.new,
);

class SessionController extends AsyncNotifier<Session?> {
  LocalStore get _store => ref.read(localStoreProvider);

  @override
  Future<Session?> build() => _store.readSession();

  Future<void> signIn(String email, String password) async {
    if (!email.contains('@') || password.length < 8) {
      throw const FormatException(
          'Use a valid email and at least 8 characters.');
    }
    final credentials = await ref.read(cloudApiProvider).login(email, password);
    await ref.read(tokenStoreProvider).write(
          accessToken: credentials.accessToken,
          refreshToken: credentials.refreshToken,
        );
    await _store.writeSession(credentials.session);
    state = AsyncData(credentials.session);
  }

  Future<void> continueAsGuest() async {
    const session =
        Session(kind: SessionKind.guest, displayName: 'Guest designer');
    await _store.writeSession(session);
    state = const AsyncData(session);
  }

  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clear();
    await _store.writeSession(null);
    state = const AsyncData(null);
  }
}

class ProjectsController extends AsyncNotifier<List<CadProject>> {
  LocalStore get _store => ref.read(localStoreProvider);

  @override
  Future<List<CadProject>> build() => _store.readProjects();

  Future<CadProject> create(String name) async {
    final now = DateTime.now().toUtc();
    final project = CadProject(
      id: const Uuid().v4(),
      name: name.trim().isEmpty ? 'Untitled design' : name.trim(),
      note: '',
      createdAt: now,
      updatedAt: now,
      revision: 1,
      syncState: SyncState.pending,
    );
    final next = [project, ...state.valueOrNull ?? const <CadProject>[]];
    await _store.writeProjects(next);
    state = AsyncData(next);
    return project;
  }

  Future<void> save(CadProject project) async {
    final projects = [...state.valueOrNull ?? const <CadProject>[]];
    final index = projects.indexWhere((item) => item.id == project.id);
    if (index < 0) throw StateError('Project no longer exists.');
    projects[index] = project;
    await _store.writeProjects(projects);
    state = AsyncData(projects);
  }

  Future<CadProject> sync(CadProject project) async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Sign in to back up this project to the cloud.');
    }
    final result = await ref.read(cloudApiProvider).pushProject(project, token);
    final synced = project.markSynced(result.appliedRevision);
    await save(synced);
    return synced;
  }

  Future<CadProject> restoreFromCloud(String projectId) async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Sign in to restore this project from the cloud.');
    }
    final restored =
        await ref.read(cloudApiProvider).pullProject(projectId, token);
    await save(restored);
    return restored;
  }

  Future<void> delete(String id) async {
    final next = (state.valueOrNull ?? const <CadProject>[])
        .where((project) => project.id != id)
        .toList();
    await _store.writeProjects(next);
    state = AsyncData(next);
  }
}
