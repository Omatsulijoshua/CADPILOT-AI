import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'ai_commands.dart';
import 'ai_planning.dart';
import 'model_3d.dart';
import 'sketch_models.dart';

class AiGeneratedDraft {
  const AiGeneratedDraft(this.command, this.totalTokens);
  final Map<String, Object?> command;
  final int totalTokens;
}

typedef AiCommandGenerator = Future<AiGeneratedDraft> Function(String prompt);
typedef AiPlanGenerator = Future<AiPlanResponse> Function(String prompt);
typedef AiPlanCommandGenerator = Future<AiGeneratedDraft> Function(String prompt, AiDesignPlan plan, AiPlanOption option, Map<String, String> answers, SketchDocument sketch);

const maxAiPromptCharacters = 2000;

class AiCommandDecision {
  const AiCommandDecision({required this.record, this.model, this.sketch});
  final AiCommandRecord record;
  final ModelDocument? model;
  final SketchDocument? sketch;
}

Future<AiCommandDecision?> showAiCommandDialog(BuildContext context,
    {required SketchDocument sketch,
    required ModelDocument model,
    AiCommandGenerator? generator,
    AiPlanGenerator? planGenerator,
    AiPlanCommandGenerator? planCommandGenerator}) {
  return showDialog<AiCommandDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          AiCommandDialog(sketch: sketch, model: model, generator: generator, planGenerator: planGenerator, planCommandGenerator: planCommandGenerator));
}

class AiCommandDialog extends StatefulWidget {
  const AiCommandDialog(
      {required this.sketch, required this.model, this.generator, this.planGenerator, this.planCommandGenerator, super.key});
  final SketchDocument sketch;
  final ModelDocument model;
  final AiCommandGenerator? generator;
  final AiPlanGenerator? planGenerator;
  final AiPlanCommandGenerator? planCommandGenerator;

  @override
  State<AiCommandDialog> createState() => _AiCommandDialogState();
}

class _AiCommandDialogState extends State<AiCommandDialog> {
  late final TextEditingController input;
  final prompt = TextEditingController();
  bool generating = false;
  int? totalTokens;
  AiCommandPreview? preview;
  SketchDocument? previewSketch;
  String? error;
  AiDesignPlan? plan;
  AiPlanOption? selectedOption;
  final Map<String, TextEditingController> answers = {};
  bool hasGeneratedPlanCommand = false;
  bool showJson = false;

  @override
  void initState() {
    super.initState();
    final rectangle = widget.sketch.entities
        .where((item) => item.kind == SketchEntityKind.rectangle)
        .firstOrNull;
    input = TextEditingController(
        text: const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'commandId': const Uuid().v4(),
      'intent': 'modify_model',
      'target': {'type': 'model', 'ids': <String>[]},
      'operations': [
        {
          'operationId': const Uuid().v4(),
          'type': 'extrude',
          'parameters': {
            'profileId': rectangle?.id ?? 'rectangle-id',
            'depth': 10
          }
        }
      ],
      'assumptions': ['Dimensions are millimetres.'],
      'requiresConfirmation': true
    }));
  }

  @override
  void dispose() {
    input.dispose();
    prompt.dispose();
    for (final controller in answers.values) { controller.dispose(); }
    super.dispose();
  }

  Future<void> createPlan() async {
    final generator = widget.planGenerator;
    if (generator == null || prompt.text.trim().isEmpty) return;
    setState(() { generating = true; error = null; preview = null; previewSketch = null; showJson = false; });
    try {
      final response = await generator(prompt.text.trim());
      for (final controller in answers.values) { controller.dispose(); }
      answers.clear();
      for (final question in response.plan.questions) { answers[question.id] = TextEditingController(); }
      setState(() { plan = response.plan; selectedOption = response.plan.options.first; totalTokens = response.totalTokens; hasGeneratedPlanCommand = false; });
    } catch (value) { setState(() => error = value.toString()); }
    finally { if (mounted) setState(() => generating = false); }
  }

  void useDefaults() {
    final current = plan;
    if (current == null) return;
    for (final question in current.questions) { answers[question.id]?.text = question.suggestedValue; }
    setState(() {});
  }

  Future<void> generateFromPlan() async {
    final currentPlan = plan; final option = selectedOption; final generator = widget.planCommandGenerator;
    if (currentPlan == null || option == null || generator == null) return;
    setState(() { generating = true; error = null; preview = null; previewSketch = null; });
    try {
      final preparedSketch = preparedSketchForPlan();
      final draft = await generator(prompt.text.trim(), currentPlan, option, {for (final entry in answers.entries) entry.key: entry.value.text.trim()}, preparedSketch);
      input.text = const JsonEncoder.withIndent('  ').convert(draft.command); totalTokens = draft.totalTokens; hasGeneratedPlanCommand = true; createPreview(sketch: preparedSketch);
    } catch (value) { setState(() => error = value.toString()); }
    finally { if (mounted) setState(() => generating = false); }
  }

  SketchDocument preparedSketchForPlan() {
    if (widget.sketch.entities.any((item) => item.kind == SketchEntityKind.rectangle)) return widget.sketch;
    final current = plan;
    final option = selectedOption;
    if (current == null || option == null) return widget.sketch;
    final dimensions = <String, double>{};
    for (final question in current.questions) {
      final raw = (answers[question.id]?.text.trim().isNotEmpty ?? false)
          ? answers[question.id]!.text
          : question.suggestedValue;
      final parsed = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
      if (parsed != null) dimensions[question.id.toLowerCase()] = double.parse(parsed.group(1)!);
    }
    final width = dimensions['width'] ?? dimensions['tablewidth'] ?? 1200;
    final depth = dimensions['depth'] ?? dimensions['tabledepth'] ?? 600;
    final chairWidth = dimensions['chairwidth'] ?? 500;
    final chairDepth = dimensions['chairdepth'] ?? 500;
    final entities = <SketchEntity>[
      SketchEntity(id: const Uuid().v4(), kind: SketchEntityKind.rectangle, start: Offset.zero, end: Offset(width, depth), dimensionLocked: true),
    ];
    final text = '${current.summary} ${option.title}'.toLowerCase();
    if (text.contains('chair')) {
      entities.add(SketchEntity(id: const Uuid().v4(), kind: SketchEntityKind.rectangle, start: Offset(width + 160, 0), end: Offset(width + 160 + chairWidth, chairDepth), dimensionLocked: true));
    }
    return widget.sketch.copyWith(entities: [...widget.sketch.entities, ...entities]);
  }

  bool get requiredAnswersComplete {
    final current = plan;
    if (current == null) return true;
    return current.questions.where((question) => question.required).every((question) => answers[question.id]?.text.trim().isNotEmpty ?? false);
  }

  Future<void> generate() async {
    final generator = widget.generator;
    final promptText = prompt.text.trim();
    if (generator == null ||
        promptText.isEmpty ||
        prompt.text.length > maxAiPromptCharacters) {
      return;
    }
    setState(() {
      generating = true;
      error = null;
      preview = null;
      previewSketch = null;
    });
    try {
      final draft = await generator(promptText);
      input.text = const JsonEncoder.withIndent('  ').convert(draft.command);
      setState(() => totalTokens = draft.totalTokens);
      createPreview();
    } catch (value) {
      setState(() => error = value.toString());
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  void createPreview({SketchDocument? sketch}) {
    try {
      final decoded = jsonDecode(input.text);
      if (decoded is! Map) {
        throw const FormatException('Command must be a JSON object.');
      }
      final command = AiCadCommand.fromJson(Map<String, Object?>.from(decoded));
      final activeSketch = sketch ?? previewSketch ?? widget.sketch;
      final value =
          const AiCommandEngine().preview(command, activeSketch, widget.model);
      setState(() {
        preview = value;
        previewSketch = activeSketch;
        error = null;
      });
    } catch (value) {
      setState(() {
        preview = null;
        previewSketch = null;
        error = value is FormatException
            ? value.message
            : 'Command JSON is invalid.';
      });
    }
  }

  void finish(AiCommandStatus status) {
    final value = preview;
    if (value == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(
        context,
        AiCommandDecision(
          model: status == AiCommandStatus.applied ? value.model : null,
          sketch: status == AiCommandStatus.applied ? previewSketch : null,
          record: AiCommandRecord(
              commandId: value.command.commandId,
              summary: value.summary,
              status: status,
              createdAt: DateTime.now().toUtc(),
              previousModel:
                  status == AiCommandStatus.applied ? widget.model : null),
        ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.auto_awesome),
          SizedBox(width: 10),
          Text('AI command preview')
        ]),
        content: SizedBox(
            width: 720,
            height: 520,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'Commands are validated locally and cannot change the model until you apply the preview.'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextField(
                      controller: prompt,
                      enabled: (widget.planGenerator ?? widget.generator) != null && !generating,
                      maxLength: maxAiPromptCharacters,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Describe what you want to design',
                        hintText: (widget.planGenerator ?? widget.generator) == null
                            ? 'Sign in to generate commands from natural language.'
                            : 'Create a moderate table',
                      ),
                    )),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: (widget.planGenerator ?? widget.generator) == null ||
                              generating ||
                              prompt.text.trim().isEmpty ||
                              prompt.text.length > maxAiPromptCharacters
                          ? null
                          : (widget.planGenerator != null ? createPlan : generate),
                      icon: generating
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome),
                      label: Text(generating ? 'Thinking' : (widget.planGenerator != null ? 'Plan' : 'Generate')),
                    ),
                  ]),
                  if (totalTokens != null)
                    Text('Usage: $totalTokens tokens',
                        textAlign: TextAlign.right),
                  const SizedBox(height: 12),
                  if (plan != null) Expanded(child: ListView(children: [
                    Text(plan!.summary, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8), Text('Extracted: ${plan!.objectType}${plan!.style == null ? '' : ' · ${plan!.style}'}'),
                    if (plan!.questions.isNotEmpty) ...[const SizedBox(height: 14), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Critical details', style: TextStyle(fontWeight: FontWeight.bold)), if (plan!.canUseDefaults) TextButton(onPressed: useDefaults, child: const Text('Use sensible defaults'))]),
                      ...plan!.questions.map((question) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: answers[question.id], onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: '${question.label}${question.required ? ' *' : ''}', helperText: question.question, hintText: question.suggestedValue)))),
                    ],
                    const SizedBox(height: 10), const Text('Choose a build approach', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...plan!.options.map((option) => Card(
                      color: selectedOption?.id == option.id ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: ListTile(
                        onTap: () => setState(() {
                          selectedOption = option;
                          error = null;
                          preview = null;
                          previewSketch = null;
                          hasGeneratedPlanCommand = false;
                        }),
                        leading: Icon(selectedOption?.id == option.id ? Icons.radio_button_checked : Icons.radio_button_off),
                        title: Text(option.title),
                        subtitle: Text('${option.description}\n${option.executableNow ? 'Ready for CAD generation' : 'Preparation: ${option.preparation.join(' ')}'}'),
                      ),
                    )),
                    if (selectedOption != null) ...[const SizedBox(height: 10), const Text('Staged CAD plan', style: TextStyle(fontWeight: FontWeight.bold)), ...selectedOption!.stages.asMap().entries.map((entry) => ListTile(dense: true, leading: CircleAvatar(radius: 12, child: Text('${entry.key + 1}', style: const TextStyle(fontSize: 11))), title: Text(entry.value))),
                      FilledButton.icon(onPressed: requiredAnswersComplete && !generating ? generateFromPlan : null, icon: const Icon(Icons.precision_manufacturing), label: Text(selectedOption!.executableNow ? 'Generate next CAD stage' : 'Create starter sketch and CAD stage')),
                      if (hasGeneratedPlanCommand)
                        TextButton.icon(onPressed: () => setState(() => showJson = !showJson), icon: Icon(showJson ? Icons.visibility_off : Icons.code), label: Text(showJson ? 'Hide command JSON' : 'Show command JSON')),
                      if (showJson)
                        SizedBox(height: 220, child: TextField(controller: input, expands: true, maxLines: null, minLines: null, style: const TextStyle(fontFamily: 'monospace', fontSize: 12), decoration: const InputDecoration(labelText: 'Structured command JSON', alignLabelWithHint: true))),
                    ],
                  ])) else Expanded(
                      child: showJson ? TextField(
                          controller: input,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                          decoration: const InputDecoration(
                              labelText: 'Structured command JSON',
                              alignLabelWithHint: true)) : Center(child: TextButton.icon(onPressed: () => setState(() => showJson = true), icon: const Icon(Icons.code), label: const Text('Show command JSON')))),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (preview != null)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(preview!.summary,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  if (preview!.command.assumptions.isNotEmpty)
                                    Text(
                                        'Assumptions: ${preview!.command.assumptions.join('; ')}'),
                                ]))),
                ])),
        actions: [
          TextButton(
              onPressed: () => finish(AiCommandStatus.cancelled),
              child: const Text('Cancel')),
          OutlinedButton.icon(
              onPressed: widget.planGenerator != null && !hasGeneratedPlanCommand ? null : createPreview,
              icon: const Icon(Icons.visibility),
              label: const Text('Preview')),
          FilledButton.icon(
              onPressed: preview == null
                  ? null
                  : () => finish(AiCommandStatus.applied),
              icon: const Icon(Icons.check),
              label: const Text('Apply')),
        ],
      );
}
