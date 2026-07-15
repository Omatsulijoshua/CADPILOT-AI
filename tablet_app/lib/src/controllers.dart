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

enum CloudSessionStatus { notApplicable, verified, offline }

final cloudSessionStatusProvider = StateProvider<CloudSessionStatus>(
  (ref) => CloudSessionStatus.notApplicable,
);
final sessionProvider = AsyncNotifierProvider<SessionController, Session?>(
  SessionController.new,
);
final projectsProvider =
    AsyncNotifierProvider<ProjectsController, List<CadProject>>(
  ProjectsController.new,
);

class SessionController extends AsyncNotifier<Session?> {
  LocalStore get _store => ref.read(localStoreProvider);

  void _setCloudStatus(CloudSessionStatus status) =>
      ref.read(cloudSessionStatusProvider.notifier).state = status;

  @override
  Future<Session?> build() async {
    final storedSession = await _store.readSession();
    if (storedSession == null || storedSession.kind == SessionKind.guest) {
      _setCloudStatus(CloudSessionStatus.notApplicable);
      return storedSession;
    }
    return _refresh(storedSession, updateState: false);
  }

  Future<Session?> _refresh(
    Session storedSession, {
    required bool updateState,
  }) async {
    final tokens = ref.read(tokenStoreProvider);
    try {
      final refreshToken = await tokens.readRefreshToken();
      if (refreshToken == null || refreshToken.trim().isEmpty) {
        await _clearSession(tokens, updateState: updateState);
        return null;
      }
      final credentials =
          await ref.read(cloudApiProvider).refreshSession(refreshToken);
      await tokens.write(
        accessToken: credentials.accessToken,
        refreshToken: credentials.refreshToken,
      );
      await _store.writeSession(credentials.session);
      _setCloudStatus(CloudSessionStatus.verified);
      if (updateState) state = AsyncData(credentials.session);
      return credentials.session;
    } on CloudApiException catch (error) {
      if (error.statusCode == 400 || error.statusCode == 401) {
        await _clearSession(tokens, updateState: updateState);
        return null;
      }
      _setCloudStatus(CloudSessionStatus.offline);
      return storedSession;
    } catch (_) {
      _setCloudStatus(CloudSessionStatus.offline);
      return storedSession;
    }
  }

  Future<void> _clearSession(
    TokenStore tokens, {
    required bool updateState,
  }) async {
    await tokens.clear();
    await _store.writeSession(null);
    _setCloudStatus(CloudSessionStatus.notApplicable);
    if (updateState) state = const AsyncData(null);
  }

  Future<bool> retryCloudVerification() async {
    final current = state.valueOrNull;
    if (current == null || current.kind != SessionKind.signedIn) return false;
    final refreshed = await _refresh(current, updateState: true);
    return refreshed != null &&
        ref.read(cloudSessionStatusProvider) == CloudSessionStatus.verified;
  }

  Future<void> register(
    String displayName,
    String email,
    String password,
  ) async {
    if (displayName.trim().length < 2) {
      throw const FormatException(
          'Enter a display name of at least 2 characters.');
    }
    if (!email.contains('@') || password.length < 8) {
      throw const FormatException(
          'Use a valid email and at least 8 password characters.');
    }
    final credentials =
        await ref.read(cloudApiProvider).register(displayName, email, password);
    await ref.read(tokenStoreProvider).write(
          accessToken: credentials.accessToken,
          refreshToken: credentials.refreshToken,
        );
    await _store.writeSession(credentials.session);
    _setCloudStatus(CloudSessionStatus.verified);
    state = AsyncData(credentials.session);
  }

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
    _setCloudStatus(CloudSessionStatus.verified);
    state = AsyncData(credentials.session);
  }

  Future<void> continueAsGuest() async {
    const session =
        Session(kind: SessionKind.guest, displayName: 'Guest designer');
    await _store.writeSession(session);
    _setCloudStatus(CloudSessionStatus.notApplicable);
    state = const AsyncData(session);
  }

  Future<void> signOut() async {
    final tokens = ref.read(tokenStoreProvider);
    try {
      final refreshToken = await tokens.readRefreshToken();
      if (refreshToken != null) {
        await ref.read(cloudApiProvider).logout(refreshToken);
      }
    } catch (_) {
      // Local sign-out must succeed even when revocation cannot reach the API.
    } finally {
      await _clearSession(tokens, updateState: true);
    }
  }
}

class ProjectsController extends AsyncNotifier<List<CadProject>> {
  LocalStore get _store => ref.read(localStoreProvider);

  @override
  Future<List<CadProject>> build() => _store.readProjects();

  Future<String> _requireCloudToken(String signedOutMessage) async {
    if (ref.read(cloudSessionStatusProvider) == CloudSessionStatus.offline) {
      throw StateError(
        'Reconnect and verify your cloud session before using cloud projects.',
      );
    }
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError(signedOutMessage);
    }
    return token;
  }

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

  Future<CadProject> duplicate(CadProject source) async {
    final now = DateTime.now().toUtc();
    final existingNames = (state.valueOrNull ?? const <CadProject>[])
        .map((project) => project.name.trim().toLowerCase())
        .toSet();
    var copyNumber = 1;
    var name = '${source.name} copy';
    while (existingNames.contains(name.toLowerCase())) {
      copyNumber++;
      name = '${source.name} copy $copyNumber';
    }
    final duplicate = CadProject(
      id: const Uuid().v4(),
      name: name,
      note: source.note,
      createdAt: now,
      updatedAt: now,
      revision: 1,
      syncState: SyncState.localOnly,
      sketch: source.sketch,
      model: source.model,
      aiHistory: source.aiHistory,
      spatialPlacements: source.spatialPlacements,
      arScreenshots: source.arScreenshots,
    );
    final next = [duplicate, ...state.valueOrNull ?? const <CadProject>[]];
    await _store.writeProjects(next);
    state = AsyncData(next);
    return duplicate;
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
    final token = await _requireCloudToken(
      'Sign in to back up this project to the cloud.',
    );
    final result = await ref.read(cloudApiProvider).pushProject(project, token);
    final synced = project.markSynced(result.appliedRevision);
    await save(synced);
    return synced;
  }

  Future<void> archiveCloudCopy(String projectId) async {
    final token = await _requireCloudToken(
      'Sign in to archive this cloud project.',
    );
    await ref.read(cloudApiProvider).archiveProject(projectId, token);
  }

  Future<CadProject> importFromCloud(String projectId) async {
    final token = await _requireCloudToken(
      'Sign in to download cloud projects.',
    );
    final restored =
        await ref.read(cloudApiProvider).pullProject(projectId, token);
    final projects = [...state.valueOrNull ?? const <CadProject>[]];
    final index = projects.indexWhere((project) => project.id == projectId);
    if (index >= 0 && projects[index].syncState == SyncState.pending) {
      throw StateError(
        'This project has pending local changes. Open it locally and use Restore cloud copy.',
      );
    }
    if (index < 0) {
      projects.insert(0, restored);
    } else {
      projects[index] = restored;
    }
    await _store.writeProjects(projects);
    state = AsyncData(projects);
    return restored;
  }

  Future<CadProject> restoreFromCloud(String projectId) async {
    final token = await _requireCloudToken(
      'Sign in to restore this project from the cloud.',
    );
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
