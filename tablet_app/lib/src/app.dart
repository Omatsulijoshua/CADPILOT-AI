import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_command_dialog.dart';
import 'ai_commands.dart';
import 'cloud_api.dart';
import 'controllers.dart';
import 'models.dart';
import 'project_file_export.dart';
import 'project_file_import.dart';
import 'project_manifest.dart';
import 'modeling_canvas.dart';
import 'sketch_canvas.dart';
import 'spatial.dart';

class CadPilotApp extends StatelessWidget {
  const CadPilotApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CadPilot',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff29d3b2),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xff0b1118),
          cardTheme: const CardThemeData(color: Color(0xff121b25)),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Color(0xff121b25),
            border: OutlineInputBorder(),
          ),
          useMaterial3: true,
        ),
        home: const TabletGate(),
      );
}

class TabletGate extends StatelessWidget {
  const TabletGate({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tablet_mac, size: 56),
                      SizedBox(height: 20),
                      Text('CadPilot requires a tablet-sized display.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 24)),
                      SizedBox(height: 8),
                      Text(
                          'Use landscape orientation or a window at least 720 dp wide.',
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            );
          }
          return const SessionRouter();
        },
      );
}

class SessionRouter extends ConsumerWidget {
  const SessionRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(sessionProvider)
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, _) => Scaffold(
            body: Center(child: Text('Could not load session: $error'))),
        data: (session) => session == null
            ? const SignInScreen()
            : Dashboard(session: session),
      );
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final displayName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  String? error;
  bool busy = false;
  bool creatingAccount = false;

  @override
  void dispose() {
    displayName.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final controller = ref.read(sessionProvider.notifier);
      if (creatingAccount) {
        await controller.register(
          displayName.text,
          email.text,
          password.text,
        );
      } else {
        await controller.signIn(email.text, password.text);
      }
    } catch (value) {
      setState(() =>
          error = value is FormatException ? value.message : value.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(56),
                color: const Color(0xff0e1821),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset('assets/branding/cadpilot-icon-master.png',
                        width: 96, height: 96),
                    const SizedBox(height: 24),
                    const Text('CADPILOT',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, letterSpacing: 2)),
                    const SizedBox(height: 12),
                    const Text('Design in context.',
                        style: TextStyle(
                            fontSize: 44, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    const Text(
                        'A local-first workspace built for tablet, stylus, and professional CAD workflows.'),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 440,
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        creatingAccount
                            ? 'Create your account'
                            : 'Welcome back',
                        style: const TextStyle(
                            fontSize: 30, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(creatingAccount
                        ? 'Create an account to back up and restore projects across devices.'
                        : 'Sign in for cloud backup, restore, and intelligent commands.'),
                    const SizedBox(height: 28),
                    if (creatingAccount) ...[
                      TextField(
                        controller: displayName,
                        textInputAction: TextInputAction.next,
                        decoration:
                            const InputDecoration(labelText: 'Display name'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: password,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: 'Password')),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: busy ? null : submit,
                        child: Text(busy
                            ? (creatingAccount
                                ? 'Creating account...'
                                : 'Signing in...')
                            : (creatingAccount
                                ? 'Create account'
                                : 'Sign in'))),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                creatingAccount = !creatingAccount;
                                error = null;
                              }),
                      child: Text(creatingAccount
                          ? 'Already have an account? Sign in'
                          : 'New to CadPilot? Create account'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: busy
                            ? null
                            : ref
                                .read(sessionProvider.notifier)
                                .continueAsGuest,
                        child: const Text('Continue as guest')),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({required this.session, super.key});
  final Session session;

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  int selectedIndex = 0;
  String projectQuery = '';
  bool importingManifest = false;

  Future<void> create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Project name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    final project = await ref.read(projectsProvider.notifier).create(name);
    if (mounted) await openProject(project);
  }

  Future<void> importManifest() async {
    if (importingManifest) return;
    setState(() => importingManifest = true);
    try {
      final content = await importProjectFile();
      if (content == null || !mounted) return;
      final manifest = ProjectManifest.parse(content);
      final source = manifest.project;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import project manifest?'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(source.name,
                    style: Theme.of(context).textTheme.titleMedium),
                if (source.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(source.note,
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 16),
                Text(
                  '${source.sketch.entities.length} sketch entities · '
                  '${source.model.operations.length} model operations · '
                  '${source.spatialPlacements.length} spatial placements',
                ),
                const SizedBox(height: 8),
                Text(
                  'Format v${manifest.schemaVersion} · Exported ${manifest.exportedAt.toLocal()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'CadPilot will create an independent local copy. This does not overwrite or upload any existing project.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.file_download_done_outlined),
              label: const Text('Import copy'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final imported =
          await ref.read(projectsProvider.notifier).importPortable(source);
      if (!mounted) return;
      await openProject(imported);
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not import manifest: ${error.message}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => importingManifest = false);
    }
  }

  Future<void> openProject(CadProject project) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectWorkspace(projectId: project.id),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cloudStatus = ref.watch(cloudSessionStatusProvider);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width > 1050,
            selectedIndex: selectedIndex,
            onDestinationSelected: (value) =>
                setState(() => selectedIndex = value),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.grid_view),
                label: Text('Projects'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cloud_outlined),
                label: Text('Cloud'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedIndex == 0
                                  ? 'Good to see you, ${widget.session.displayName}'
                                  : 'Cloud projects',
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(selectedIndex == 0
                                ? 'Your local design workspace'
                                : 'Authenticated backups available to this account'),
                          ],
                        ),
                      ),
                      if (selectedIndex == 0) ...[
                        OutlinedButton.icon(
                          onPressed: importingManifest ? null : importManifest,
                          icon: importingManifest
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.file_upload_outlined),
                          label: Text(importingManifest
                              ? 'Importing...'
                              : 'Import manifest'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: importingManifest ? null : create,
                          icon: const Icon(Icons.add),
                          label: const Text('New project'),
                        ),
                      ],
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Sign out',
                        onPressed: ref.read(sessionProvider.notifier).signOut,
                        icon: const Icon(Icons.logout),
                      ),
                    ],
                  ),
                  if (widget.session.kind == SessionKind.signedIn &&
                      cloudStatus == CloudSessionStatus.offline) ...[
                    const SizedBox(height: 16),
                    CloudSessionBanner(
                      onRetry: ref
                          .read(sessionProvider.notifier)
                          .retryCloudVerification,
                    ),
                  ],
                  if (selectedIndex == 0) ...[
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('project-search'),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: 'Search projects',
                        hintText: 'Filter by project name',
                        suffixIcon: projectQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear project search',
                                onPressed: () =>
                                    setState(() => projectQuery = ''),
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                      onChanged: (value) =>
                          setState(() => projectQuery = value),
                    ),
                  ],
                  const SizedBox(height: 30),
                  Expanded(
                    child: selectedIndex == 0
                        ? ProjectGrid(onOpen: openProject, query: projectQuery)
                        : CloudProjectsPanel(
                            session: widget.session,
                            onOpen: openProject,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CloudSessionBanner extends StatelessWidget {
  const CloudSessionBanner({required this.onRetry, super.key});

  final Future<bool> Function() onRetry;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_outlined),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Working offline',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Local projects remain available. Reconnect to verify your cloud session before backup or restore.',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}

class CloudProjectsPanel extends ConsumerStatefulWidget {
  const CloudProjectsPanel({
    required this.session,
    required this.onOpen,
    super.key,
  });

  final Session session;
  final ValueChanged<CadProject> onOpen;

  @override
  ConsumerState<CloudProjectsPanel> createState() => _CloudProjectsPanelState();
}

class _CloudProjectsPanelState extends ConsumerState<CloudProjectsPanel> {
  late Future<List<CloudProjectSummary>> projects;
  String? importingId;
  String? archivingId;
  String? message;

  @override
  void initState() {
    super.initState();
    projects = load();
  }

  Future<List<CloudProjectSummary>> load() async {
    if (ref.read(cloudSessionStatusProvider) == CloudSessionStatus.offline) {
      throw StateError(
        'Reconnect and verify your cloud session before browsing backups.',
      );
    }
    if (widget.session.kind != SessionKind.signedIn) {
      throw StateError('Sign in to browse and restore cloud projects.');
    }
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Your cloud session is unavailable. Sign in again.');
    }
    return ref.read(cloudApiProvider).listProjects(token);
  }

  void refresh() => setState(() {
        message = null;
        projects = load();
      });

  Future<void> import(CloudProjectSummary summary) async {
    if (importingId != null) return;
    setState(() {
      importingId = summary.id;
      message = null;
    });
    try {
      final project =
          await ref.read(projectsProvider.notifier).importFromCloud(summary.id);
      if (!mounted) return;
      widget.onOpen(project);
    } catch (error) {
      if (mounted) {
        setState(() => message = error is CloudApiException
            ? error.message
            : error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => importingId = null);
    }
  }

  Future<void> archive(CloudProjectSummary summary) async {
    if (importingId != null || archivingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive cloud backup?'),
        content: Text(
          'Archive "${summary.name}" from your cloud backups? The local project on this device will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archive backup'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      archivingId = summary.id;
      message = null;
    });
    try {
      await ref.read(projectsProvider.notifier).archiveCloudCopy(summary.id);
      if (mounted) {
        setState(() {
          message =
              'Cloud backup archived. Your local project remains available.';
          projects = load();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => message = error is CloudApiException
            ? error.message
            : error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => archivingId = null);
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<CloudProjectSummary>>(
        future: projects,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CloudMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Cloud projects unavailable',
              message:
                  snapshot.error.toString().replaceFirst('Bad state: ', ''),
              actionLabel: 'Retry',
              onAction: refresh,
            );
          }
          final values = snapshot.data ?? const <CloudProjectSummary>[];
          if (values.isEmpty) {
            return _CloudMessage(
              icon: Icons.cloud_queue,
              title: 'No cloud backups yet',
              message: message ??
                  'Open a local project and choose Back up now to add it here.',
              actionLabel: 'Refresh',
              onAction: refresh,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '${values.length} cloud project${values.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh cloud projects',
                    onPressed: importingId == null && archivingId == null
                        ? refresh
                        : null,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    message!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: values.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final project = values[index];
                    final downloading = importingId == project.id;
                    final archiving = archivingId == project.id;
                    final processing =
                        importingId != null || archivingId != null;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.view_in_ar_outlined),
                        ),
                        title: Text(project.name),
                        subtitle: Text(
                          'Cloud revision ${project.revision} · Updated ${_date(project.updatedAt)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Archive cloud backup',
                              onPressed:
                                  processing ? null : () => archive(project),
                              icon: archiving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.archive_outlined),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed:
                                  processing ? null : () => import(project),
                              icon: downloading
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.cloud_download_outlined),
                              label: Text(
                                downloading
                                    ? 'Downloading...'
                                    : 'Download & open',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );

  static String _date(DateTime value) =>
      value.toLocal().toIso8601String().split('T').first;
}

class _CloudMessage extends StatelessWidget {
  const _CloudMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
}

class ProjectGrid extends ConsumerStatefulWidget {
  const ProjectGrid({required this.onOpen, this.query = '', super.key});
  final ValueChanged<CadProject> onOpen;
  final String query;

  @override
  ConsumerState<ProjectGrid> createState() => _ProjectGridState();
}

class _ProjectGridState extends ConsumerState<ProjectGrid> {
  String? deletingId;
  String? duplicatingId;
  String? exportingId;

  Future<void> duplicate(CadProject project) async {
    if (deletingId != null || duplicatingId != null) return;
    setState(() => duplicatingId = project.id);
    try {
      final copy = await ref.read(projectsProvider.notifier).duplicate(project);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created ${copy.name} as a local draft.')),
        );
      }
    } finally {
      if (mounted) setState(() => duplicatingId = null);
    }
  }

  Future<void> exportProject(CadProject project) async {
    if (deletingId != null || duplicatingId != null || exportingId != null) {
      return;
    }
    setState(() => exportingId = project.id);
    try {
      final fileName =
          '${project.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.cadpilot.json';
      final message = await exportProjectFile(
        content: const JsonEncoder.withIndent('  ').convert(
          ProjectManifest(project: project, exportedAt: DateTime.now())
              .toJson(),
        ),
        fileName: fileName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not export this project manifest.')),
        );
      }
    } finally {
      if (mounted) setState(() => exportingId = null);
    }
  }

  Future<void> delete(CadProject project) async {
    if (deletingId != null) return;
    final cloudCopyExists = project.lastSyncedRevision != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete local project?'),
        content: Text(
          cloudCopyExists
              ? 'Delete "${project.name}" from this device? Its cloud backup will remain available to download later.'
              : 'Delete "${project.name}" from this device? It has no cloud backup and cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete local project'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => deletingId = project.id);
    try {
      await ref.read(projectsProvider.notifier).delete(project.id);
    } finally {
      if (mounted) setState(() => deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => ref.watch(projectsProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load projects: $error')),
        data: (projects) {
          final normalizedQuery = widget.query.trim().toLowerCase();
          final visibleProjects = projects
              .where((project) =>
                  normalizedQuery.isEmpty ||
                  project.name.toLowerCase().contains(normalizedQuery))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          if (visibleProjects.isEmpty) {
            return Center(
              child: Text(normalizedQuery.isEmpty
                  ? 'No projects yet. Create one to begin.'
                  : 'No projects match your search.'),
            );
          }
          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 330,
                childAspectRatio: 1.35,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16),
            itemCount: visibleProjects.length,
            itemBuilder: (context, index) {
              final project = visibleProjects[index];
              return Card(
                  child: InkWell(
                      onTap: () => widget.onOpen(project),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Container(
                                      decoration: BoxDecoration(
                                          color: const Color(0xff1a2935),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: const Center(
                                          child: Icon(Icons.view_in_ar,
                                              size: 44,
                                              color: Color(0xff29d3b2))))),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(project.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  IconButton(
                                    tooltip: 'Duplicate project',
                                    onPressed: deletingId == null &&
                                            duplicatingId == null &&
                                            exportingId == null
                                        ? () => duplicate(project)
                                        : null,
                                    icon: duplicatingId == project.id
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(Icons.copy_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Export project manifest',
                                    onPressed: deletingId == null &&
                                            duplicatingId == null &&
                                            exportingId == null
                                        ? () => exportProject(project)
                                        : null,
                                    icon: exportingId == project.id
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(
                                            Icons.file_download_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete local project',
                                    onPressed: deletingId == null &&
                                            duplicatingId == null &&
                                            exportingId == null
                                        ? () => delete(project)
                                        : null,
                                    icon: deletingId == project.id
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              Text(
                                  'Revision ${project.revision} - ${project.syncState == SyncState.synced ? 'Synced' : 'Saved locally'}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ]),
                      )));
            },
          );
        },
      );
}

class ProjectWorkspace extends ConsumerStatefulWidget {
  const ProjectWorkspace({required this.projectId, super.key});
  final String projectId;
  @override
  ConsumerState<ProjectWorkspace> createState() => _ProjectWorkspaceState();
}

class _ProjectWorkspaceState extends ConsumerState<ProjectWorkspace> {
  final note = TextEditingController();
  Timer? autosave;
  bool initialized = false;
  String status = 'Saved locally';
  bool modeling = false;
  bool syncing = false;

  @override
  void dispose() {
    autosave?.cancel();
    note.dispose();
    super.dispose();
  }

  void schedule(CadProject project) {
    setState(() => status = 'Saving...');
    autosave?.cancel();
    autosave = Timer(const Duration(milliseconds: 600), () async {
      await ref
          .read(projectsProvider.notifier)
          .save(project.copyWith(note: note.text));
      if (mounted) setState(() => status = 'Saved locally');
    });
  }

  Future<void> syncProject(CadProject project) async {
    if (syncing) return;
    var hasCloudConflict = false;
    setState(() {
      syncing = true;
      status = 'Backing up...';
    });
    try {
      await ref.read(projectsProvider.notifier).sync(project);
      if (mounted) setState(() => status = 'Backed up to cloud');
    } catch (error) {
      hasCloudConflict = error is CloudApiException && error.statusCode == 409;
      if (mounted) {
        setState(() => status = hasCloudConflict
            ? 'Cloud changes detected. Your local edits are still safe.'
            : error is CloudApiException
                ? error.message
                : error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
    if (hasCloudConflict && mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cloud changes detected'),
          content: const Text(
            'This project was updated from another device. Your local edits have not been changed. Use Restore cloud copy only if you want to replace your local edits with the latest cloud version.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep local edits'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> restoreProject(CadProject project) async {
    if (syncing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore cloud copy?'),
        content: const Text(
          'This replaces unsynced local edits with the latest cloud backup. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore cloud copy'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    autosave?.cancel();
    setState(() {
      syncing = true;
      status = 'Downloading cloud copy...';
    });
    try {
      final restored = await ref
          .read(projectsProvider.notifier)
          .restoreFromCloud(project.id);
      if (!mounted) return;
      note.text = restored.note;
      setState(() => status = 'Cloud copy restored');
    } catch (error) {
      if (mounted) {
        setState(() => status = error is CloudApiException
            ? error.message
            : error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> renameProject(CadProject project) async {
    var draftName = project.name;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rename project'),
          content: TextFormField(
            initialValue: project.name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Project name'),
            onChanged: (value) => setDialogState(() => draftName = value),
            onFieldSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draftName),
              child: const Text('Save name'),
            ),
          ],
        ),
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        trimmed == project.name ||
        !mounted) {
      return;
    }
    await ref
        .read(projectsProvider.notifier)
        .save(project.copyWith(name: trimmed));
    if (mounted) setState(() => status = 'Project renamed locally');
  }

  Future<void> runAiCommand(CadProject project) async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (!mounted) return;
    final decision = await showAiCommandDialog(context,
        sketch: project.sketch,
        model: project.model,
        generator: token == null
            ? null
            : (prompt) async {
                final response = await ref
                    .read(cloudApiProvider)
                    .generateAiCommand(
                        prompt: prompt, project: project, token: token);
                return AiGeneratedDraft(response.command, response.totalTokens);
              });
    if (decision == null || !mounted) return;
    final updated = project.copyWith(
      model: decision.model ?? project.model,
      aiHistory: [...project.aiHistory, decision.record],
    );
    await ref.read(projectsProvider.notifier).save(updated);
    if (mounted) {
      setState(() {
        status = decision.model == null
            ? 'AI command cancelled'
            : 'AI command applied';
        if (decision.model != null) modeling = true;
      });
    }
  }

  bool canUndoAiCommand(CadProject project, AiCommandRecord record) {
    if (record.status != AiCommandStatus.applied ||
        record.previousModel == null) {
      return false;
    }
    final index = project.aiHistory.indexOf(record);
    return index >= 0 &&
        !project.aiHistory
            .skip(index + 1)
            .any((item) => item.status == AiCommandStatus.applied);
  }

  Future<void> undoAiCommand(CadProject project, AiCommandRecord record) async {
    final previous = record.previousModel;
    if (!canUndoAiCommand(project, record) || previous == null) return;
    final history = project.aiHistory
        .map((item) => identical(item, record)
            ? item.copyWith(status: AiCommandStatus.undone)
            : item)
        .toList();
    await ref
        .read(projectsProvider.notifier)
        .save(project.copyWith(model: previous, aiHistory: history));
    if (mounted) {
      setState(() {
        modeling = true;
        status = 'AI command undone';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = ref
        .watch(projectsProvider)
        .valueOrNull
        ?.where((p) => p.id == widget.projectId)
        .firstOrNull;
    if (project == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!initialized) {
      note.text = project.note;
      initialized = true;
    }
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(project.name),
        actions: [
          IconButton(
            tooltip: 'Rename project',
            onPressed: () => renameProject(project),
            icon: const Icon(Icons.drive_file_rename_outline),
          ),
          Tooltip(
            message: status,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.info_outline),
            ),
          ),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SpatialCapabilityPanel(
                        projectName: project.name,
                        placements: project.spatialPlacements,
                        onPlacementsChanged: (placements) async {
                          await ref.read(projectsProvider.notifier).save(
                                project.copyWith(spatialPlacements: placements),
                              );
                          if (mounted) {
                            setState(() => status = 'Spatial placements saved');
                          }
                        },
                      )),
              icon: const Icon(Icons.view_in_ar),
              label: const Text('AR / Scan')),
          const SizedBox(width: 8),
          FilledButton.icon(
              onPressed: () => runAiCommand(project),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI command')),
          const SizedBox(width: 12),
          SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.draw),
                    label: Text('Sketch')),
                ButtonSegment(
                    value: true,
                    icon: Icon(Icons.view_in_ar),
                    label: Text('3D'))
              ],
              selected: {
                modeling
              },
              onSelectionChanged: (value) =>
                  setState(() => modeling = value.first)),
          const SizedBox(width: 16)
        ],
      ),
      body: Row(children: [
        NavigationRail(selectedIndex: 0, destinations: const [
          NavigationRailDestination(
              icon: Icon(Icons.near_me_outlined), label: Text('Select')),
          NavigationRailDestination(
              icon: Icon(Icons.edit_outlined), label: Text('Sketch')),
          NavigationRailDestination(
              icon: Icon(Icons.straighten), label: Text('Measure')),
        ]),
        Expanded(
          child: modeling
              ? ModelingCanvas(
                  projectName: project.name,
                  sketch: project.sketch,
                  model: project.model,
                  onChanged: (model) async {
                    setState(() => status = 'Saving...');
                    await ref.read(projectsProvider.notifier).save(
                          project.copyWith(model: model),
                        );
                    if (mounted) setState(() => status = 'Model saved locally');
                  },
                )
              : SketchCanvas(
                  document: project.sketch,
                  onChanged: (document) async {
                    setState(() => status = 'Saving...');
                    await ref.read(projectsProvider.notifier).save(
                          project.copyWith(sketch: document),
                        );
                    if (mounted) {
                      setState(() => status = 'Sketch saved locally');
                    }
                  },
                ),
        ),
        SizedBox(
            width: 340,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('PROJECT NOTES',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      TextField(
                          controller: note,
                          onChanged: (_) => schedule(project),
                          maxLines: 8,
                          decoration: const InputDecoration(
                              hintText:
                                  'Add design intent, dimensions, or manufacturing notes...')),
                      const SizedBox(height: 20),
                      const Text('SYNC'),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(project.syncState == SyncState.synced
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_upload_outlined),
                        title: Text(project.syncState == SyncState.synced
                            ? 'Cloud backup current'
                            : 'Local changes pending'),
                        subtitle: Text(project.lastSyncedRevision == null
                            ? 'This project has not been backed up yet.'
                            : 'Remote revision ${project.lastSyncedRevision}'),
                        trailing: FilledButton.tonal(
                          onPressed:
                              syncing || project.syncState == SyncState.synced
                                  ? null
                                  : () => syncProject(project),
                          child:
                              Text(syncing ? 'Backing up...' : 'Back up now'),
                        ),
                      ),
                      if (project.lastSyncedRevision != null &&
                          project.syncState != SyncState.synced)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed:
                                syncing ? null : () => restoreProject(project),
                            icon: const Icon(Icons.cloud_download_outlined),
                            label: const Text('Restore cloud copy'),
                          ),
                        ),
                      const Divider(),
                      const Text('AI COMMAND HISTORY'),
                      const SizedBox(height: 8),
                      if (project.aiHistory.isEmpty)
                        const Text('No AI commands yet.')
                      else
                        ...project.aiHistory.reversed
                            .take(4)
                            .map((record) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(record.status.name == 'applied'
                                      ? Icons.check_circle_outline
                                      : Icons.cancel_outlined),
                                  title: Text(record.summary,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(record.status.name),
                                  trailing: canUndoAiCommand(project, record)
                                      ? IconButton(
                                          tooltip: 'Undo AI command',
                                          onPressed: () =>
                                              undoAiCommand(project, record),
                                          icon: const Icon(Icons.undo),
                                        )
                                      : null,
                                )),
                    ]))),
      ]),
    );
  }
}
