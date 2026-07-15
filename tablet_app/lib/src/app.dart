import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_command_dialog.dart';
import 'ai_commands.dart';
import 'cloud_api.dart';
import 'controllers.dart';
import 'models.dart';
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
  final email = TextEditingController();
  final password = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .signIn(email.text, password.text);
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
                    const Text('Welcome back',
                        style: TextStyle(
                            fontSize: 30, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'Phase 1 stores your projects locally on this tablet.'),
                    const SizedBox(height: 28),
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
                        child: Text(busy ? 'Signing in...' : 'Sign in')),
                    const SizedBox(height: 12),
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

class Dashboard extends ConsumerWidget {
  const Dashboard({required this.session, super.key});
  final Session session;

  Future<void> create(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New project'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Project name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    final project = await ref.read(projectsProvider.notifier).create(name);
    if (context.mounted) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProjectWorkspace(projectId: project.id)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width > 1050,
              selectedIndex: 0,
              destinations: const [
                NavigationRailDestination(
                    icon: Icon(Icons.grid_view), label: Text('Projects')),
                NavigationRailDestination(
                    icon: Icon(Icons.cloud_outlined), label: Text('Cloud')),
                NavigationRailDestination(
                    icon: Icon(Icons.star_outline), label: Text('Favorites')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Good to see you, ${session.displayName}',
                                style: const TextStyle(
                                    fontSize: 30, fontWeight: FontWeight.bold)),
                            const Text('Your local design workspace'),
                          ])),
                      FilledButton.icon(
                          onPressed: () => create(context, ref),
                          icon: const Icon(Icons.add),
                          label: const Text('New project')),
                      const SizedBox(width: 8),
                      IconButton(
                          tooltip: 'Sign out',
                          onPressed: ref.read(sessionProvider.notifier).signOut,
                          icon: const Icon(Icons.logout)),
                    ]),
                    const SizedBox(height: 30),
                    Expanded(
                        child: ProjectGrid(
                            onOpen: (project) => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ProjectWorkspace(
                                        projectId: project.id))))),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class ProjectGrid extends ConsumerWidget {
  const ProjectGrid({required this.onOpen, super.key});
  final ValueChanged<CadProject> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(projectsProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load projects: $error')),
        data: (projects) {
          if (projects.isEmpty) {
            return const Center(
                child: Text('No projects yet. Create one to begin.'));
          }
          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 330,
                childAspectRatio: 1.35,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return Card(
                  child: InkWell(
                      onTap: () => onOpen(project),
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
                              Text(project.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
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
    setState(() {
      syncing = true;
      status = 'Backing up...';
    });
    try {
      await ref.read(projectsProvider.notifier).sync(project);
      if (mounted) setState(() => status = 'Backed up to cloud');
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
          Text(status),
          const SizedBox(width: 12),
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
