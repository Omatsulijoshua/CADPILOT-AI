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
typedef AiPlanCommandGenerator = Future<AiGeneratedDraft> Function(
    String prompt,
    AiDesignPlan plan,
    AiPlanOption option,
    Map<String, String> answers,
    SketchDocument sketch);

const maxAiPromptCharacters = 2000;

enum _StarterFamily { rectangular, round, boredRound, gear, furniture }

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
      builder: (_) => AiCommandDialog(
          sketch: sketch,
          model: model,
          generator: generator,
          planGenerator: planGenerator,
          planCommandGenerator: planCommandGenerator));
}

class AiCommandDialog extends StatefulWidget {
  const AiCommandDialog(
      {required this.sketch,
      required this.model,
      this.generator,
      this.planGenerator,
      this.planCommandGenerator,
      super.key});
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
    for (final controller in answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> createPlan() async {
    final generator = widget.planGenerator;
    if (generator == null || prompt.text.trim().isEmpty) return;
    setState(() {
      generating = true;
      error = null;
      preview = null;
      previewSketch = null;
      showJson = false;
    });
    try {
      final response = await generator(prompt.text.trim());
      for (final controller in answers.values) {
        controller.dispose();
      }
      answers.clear();
      for (final question in response.plan.questions) {
        answers[question.id] = TextEditingController();
      }
      setState(() {
        plan = response.plan;
        selectedOption = response.plan.options.first;
        totalTokens = response.totalTokens;
        hasGeneratedPlanCommand = false;
      });
    } catch (value) {
      setState(() => error = value.toString());
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  void useDefaults() {
    final current = plan;
    if (current == null) return;
    for (final question in current.questions) {
      answers[question.id]?.text = question.suggestedValue;
    }
    setState(() {});
  }

  Future<void> generateFromPlan() async {
    final currentPlan = plan;
    final option = selectedOption;
    final generator = widget.planCommandGenerator;
    if (currentPlan == null || option == null || generator == null) return;
    setState(() {
      generating = true;
      error = null;
      preview = null;
      previewSketch = null;
    });
    try {
      final preparedSketch = preparedSketchForPlan();
      final answerValues = {
        for (final entry in answers.entries) entry.key: entry.value.text.trim()
      };
      final draft = option.executableNow
          ? await generator(prompt.text.trim(), currentPlan, option,
              answerValues, preparedSketch)
          : AiGeneratedDraft(
              starterCommandForPlan(
                  preparedSketch, currentPlan, option, answerValues),
              0);
      input.text = const JsonEncoder.withIndent('  ').convert(draft.command);
      totalTokens = draft.totalTokens;
      hasGeneratedPlanCommand = true;
      createPreview(sketch: preparedSketch);
    } catch (value) {
      setState(() => error = value.toString());
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  SketchDocument preparedSketchForPlan() {
    final current = plan;
    final option = selectedOption;
    if (current == null || option == null) return widget.sketch;
    final dimensions = <String, double>{};
    for (final question in current.questions) {
      final raw = (answers[question.id]?.text.trim().isNotEmpty ?? false)
          ? answers[question.id]!.text
          : question.suggestedValue;
      final parsed = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
      if (parsed != null) {
        dimensions[question.id.toLowerCase()] = double.parse(parsed.group(1)!);
      }
    }
    final width = dimensions['width'] ??
        dimensions['tablewidth'] ??
        dimensions['size'] ??
        1200;
    final depth = dimensions['depth'] ?? dimensions['tabledepth'] ?? 600;
    final height = dimensions['height'] ??
        dimensions['thickness'] ??
        dimensions['length'] ??
        80;
    final chairWidth = dimensions['chairwidth'] ?? 500;
    final chairDepth = dimensions['chairdepth'] ?? 500;
    final text = _planText(current, option);
    final family = _starterFamily(text);
    final needsTable = text.contains('table') || text.contains('desk');
    final needsChair = text.contains('chair') || text.contains('seat');
    final needsGear = family == _StarterFamily.gear;
    final needsRound =
        family == _StarterFamily.round || family == _StarterFamily.boredRound;
    final targetRectangles = [
      if (needsTable || (!needsChair && !needsGear && !needsRound)) 'table',
      if (needsChair) 'chair',
      if (needsRound) 'round',
    ];
    final existingRectangles = widget.sketch.entities
        .where((item) => item.kind == SketchEntityKind.rectangle)
        .toList();
    final hasGearProfile = widget.sketch.entities
        .any((item) => item.kind == SketchEntityKind.circle);
    if (existingRectangles.length >= targetRectangles.length &&
        (!needsGear || hasGearProfile)) {
      return widget.sketch;
    }
    final entities = <SketchEntity>[];
    var cursorX = existingRectangles.isEmpty
        ? 0.0
        : existingRectangles
                .map((item) =>
                    item.end.dx > item.start.dx ? item.end.dx : item.start.dx)
                .reduce((a, b) => a > b ? a : b) +
            160;
    for (var index = existingRectangles.length;
        index < targetRectangles.length;
        index += 1) {
      final target = targetRectangles[index];
      final rectWidth = target == 'chair'
          ? chairWidth
          : target == 'round'
              ? (width / 2).clamp(20, 2000).toDouble()
              : width;
      final rectDepth = target == 'chair'
          ? chairDepth
          : target == 'round'
              ? height.clamp(5, 1000).toDouble()
              : depth;
      entities.add(SketchEntity(
          id: const Uuid().v4(),
          kind: SketchEntityKind.rectangle,
          start: Offset(cursorX, 0),
          end: Offset(cursorX + rectWidth, rectDepth),
          dimensionLocked: true));
      if (target == 'round' && family == _StarterFamily.boredRound) {
        final boreRadius =
            (rectWidth * 0.22).clamp(2, rectWidth * 0.7).toDouble();
        entities.add(SketchEntity(
            id: const Uuid().v4(),
            kind: SketchEntityKind.circle,
            start: Offset(cursorX, rectWidth),
            end: Offset(cursorX + boreRadius, rectWidth),
            dimensionLocked: true));
      }
      cursorX += rectWidth + 160;
    }
    if (needsGear && !hasGearProfile) {
      final gearRadius = (width / 2).clamp(50, 500).toDouble();
      entities.add(SketchEntity(
          id: const Uuid().v4(),
          kind: SketchEntityKind.circle,
          start: Offset(cursorX + gearRadius, gearRadius),
          end: Offset(cursorX + gearRadius * 2, gearRadius),
          dimensionLocked: true));
    }
    return widget.sketch
        .copyWith(entities: [...widget.sketch.entities, ...entities]);
  }

  Map<String, Object?> starterCommandForPlan(
      SketchDocument sketch,
      AiDesignPlan current,
      AiPlanOption option,
      Map<String, String> answerValues) {
    final rectangles = sketch.entities
        .where((item) => item.kind == SketchEntityKind.rectangle)
        .take(6)
        .toList();
    final circles =
        sketch.entities.where((item) => item.kind == SketchEntityKind.circle);
    final text = _planText(current, option);
    final family = _starterFamily(text);
    final needsGear = family == _StarterFamily.gear;
    final needsRound =
        family == _StarterFamily.round || family == _StarterFamily.boredRound;
    if (rectangles.isEmpty && (!needsGear || circles.isEmpty)) {
      throw const FormatException('Create or approve a starter profile first.');
    }
    final thickness =
        _dimensionValue(answerValues, ['tabletopthickness', 'thickness']) ?? 30;
    final operations = <Map<String, Object?>>[];
    for (var index = 0; index < rectangles.length; index += 1) {
      final profile = rectangles[index];
      if (needsRound && index == rectangles.length - 1) {
        operations.add({
          'operationId': const Uuid().v4(),
          'type': 'revolve',
          'parameters': {'profileId': profile.id, 'angle': 360}
        });
        if (family == _StarterFamily.boredRound && circles.isNotEmpty) {
          operations.add({
            'operationId': const Uuid().v4(),
            'type': 'cut',
            'parameters': {
              'profileId': circles.last.id,
              'depth': profile.secondaryDimension ?? profile.primaryDimension
            }
          });
        }
        continue;
      }
      final label = index == 0
          ? 'table starter solid'
          : index == 1
              ? 'chair starter solid'
              : index == 2
                  ? 'gear-system starter solid'
                  : 'starter solid';
      final depth = index == 0
          ? thickness
          : index == 1
              ? 45.0
              : index == 2
                  ? 60.0
                  : 25.0;
      operations.add({
        'operationId': const Uuid().v4(),
        'type': 'extrude',
        'parameters': {'profileId': profile.id, 'depth': depth, 'name': label}
      });
    }
    if (needsGear && circles.isNotEmpty) {
      operations.add({
        'operationId': const Uuid().v4(),
        'type': 'gear',
        'parameters': {
          'profileId': circles.last.id,
          'depth': 18,
          'teeth': 18,
          'boreRadius': 35
        }
      });
    }
    return {
      'schemaVersion': 1,
      'commandId': const Uuid().v4(),
      'intent': 'modify_model',
      'target': {'type': 'model', 'ids': <String>[]},
      'operations': operations,
      'assumptions': [
        'This is a multi-object starter CAD stage generated from the approved plan.',
        'Separate starter profiles are used so table, chair, and gear-system requests do not collapse into one cube.',
        if (current.canUseDefaults)
          'Sensible default dimensions are used where the prompt did not provide exact measurements.',
        ...option.assumptions,
      ],
      'requiresConfirmation': true
    };
  }

  double? _dimensionValue(Map<String, String> answerValues, List<String> keys) {
    for (final entry in answerValues.entries) {
      final normalized =
          entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (!keys.any(normalized.contains)) continue;
      final parsed = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(entry.value);
      if (parsed != null) return double.parse(parsed.group(1)!);
    }
    return null;
  }

  String _planText(AiDesignPlan current, AiPlanOption option) =>
      '${prompt.text} ${current.summary} ${current.objectType} ${current.style ?? ''} ${option.title} ${option.description}'
          .toLowerCase();

  _StarterFamily _starterFamily(String text) {
    if (text.contains('gear') || text.contains('sprocket')) {
      return _StarterFamily.gear;
    }
    if (text.contains('pipe') ||
        text.contains('tube') ||
        text.contains('wheel') ||
        text.contains('pulley') ||
        text.contains('bearing') ||
        text.contains('donut')) {
      return _StarterFamily.boredRound;
    }
    if (text.contains('cylinder') ||
        text.contains('shaft') ||
        text.contains('rod') ||
        text.contains('disc') ||
        text.contains('disk') ||
        text.contains('round')) {
      return _StarterFamily.round;
    }
    if (text.contains('table') ||
        text.contains('desk') ||
        text.contains('chair') ||
        text.contains('seat')) {
      return _StarterFamily.furniture;
    }
    return _StarterFamily.rectangular;
  }

  bool get requiredAnswersComplete {
    final current = plan;
    if (current == null) return true;
    return current.questions.where((question) => question.required).every(
        (question) => answers[question.id]?.text.trim().isNotEmpty ?? false);
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
                      enabled:
                          (widget.planGenerator ?? widget.generator) != null &&
                              !generating,
                      maxLength: maxAiPromptCharacters,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Describe what you want to design',
                        hintText: (widget.planGenerator ?? widget.generator) ==
                                null
                            ? 'Sign in to generate commands from natural language.'
                            : 'Create a moderate table',
                      ),
                    )),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed:
                          (widget.planGenerator ?? widget.generator) == null ||
                                  generating ||
                                  prompt.text.trim().isEmpty ||
                                  prompt.text.length > maxAiPromptCharacters
                              ? null
                              : (widget.planGenerator != null
                                  ? createPlan
                                  : generate),
                      icon: generating
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome),
                      label: Text(generating
                          ? 'Thinking'
                          : (widget.planGenerator != null
                              ? 'Plan'
                              : 'Generate')),
                    ),
                  ]),
                  if (totalTokens != null)
                    Text('Usage: $totalTokens tokens',
                        textAlign: TextAlign.right),
                  const SizedBox(height: 12),
                  if (plan != null)
                    Expanded(
                        child: ListView(children: [
                      Text(plan!.summary,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(
                          'Extracted: ${plan!.objectType}${plan!.style == null ? '' : ' · ${plan!.style}'}'),
                      if (plan!.questions.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Critical details',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              if (plan!.canUseDefaults)
                                TextButton(
                                    onPressed: useDefaults,
                                    child: const Text('Use sensible defaults'))
                            ]),
                        ...plan!.questions.map((question) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TextField(
                                controller: answers[question.id],
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                    labelText:
                                        '${question.label}${question.required ? ' *' : ''}',
                                    helperText: question.question,
                                    hintText: question.suggestedValue)))),
                      ],
                      const SizedBox(height: 10),
                      const Text('Choose a build approach',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ...plan!.options.map((option) => Card(
                            color: selectedOption?.id == option.id
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            child: ListTile(
                              onTap: () => setState(() {
                                selectedOption = option;
                                error = null;
                                preview = null;
                                previewSketch = null;
                                hasGeneratedPlanCommand = false;
                              }),
                              leading: Icon(selectedOption?.id == option.id
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off),
                              title: Text(option.title),
                              subtitle: Text(
                                  '${option.description}\n${option.executableNow ? 'Ready for CAD generation' : 'Preparation: ${option.preparation.join(' ')}'}'),
                            ),
                          )),
                      if (selectedOption != null) ...[
                        const SizedBox(height: 10),
                        const Text('Staged CAD plan',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        ...selectedOption!.stages.asMap().entries.map((entry) =>
                            ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                    radius: 12,
                                    child: Text('${entry.key + 1}',
                                        style: const TextStyle(fontSize: 11))),
                                title: Text(entry.value))),
                        FilledButton.icon(
                            onPressed: requiredAnswersComplete && !generating
                                ? generateFromPlan
                                : null,
                            icon: const Icon(Icons.precision_manufacturing),
                            label: Text(selectedOption!.executableNow
                                ? 'Generate next CAD stage'
                                : 'Create starter sketch and CAD stage')),
                        if (hasGeneratedPlanCommand)
                          TextButton.icon(
                              onPressed: () =>
                                  setState(() => showJson = !showJson),
                              icon: Icon(
                                  showJson ? Icons.visibility_off : Icons.code),
                              label: Text(showJson
                                  ? 'Hide command JSON'
                                  : 'Show command JSON')),
                        if (showJson)
                          SizedBox(
                              height: 220,
                              child: TextField(
                                  controller: input,
                                  expands: true,
                                  maxLines: null,
                                  minLines: null,
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 12),
                                  decoration: const InputDecoration(
                                      labelText: 'Structured command JSON',
                                      alignLabelWithHint: true))),
                      ],
                    ]))
                  else
                    Expanded(
                        child: showJson
                            ? TextField(
                                controller: input,
                                expands: true,
                                maxLines: null,
                                minLines: null,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                                decoration: const InputDecoration(
                                    labelText: 'Structured command JSON',
                                    alignLabelWithHint: true))
                            : Center(
                                child: TextButton.icon(
                                    onPressed: () =>
                                        setState(() => showJson = true),
                                    icon: const Icon(Icons.code),
                                    label: const Text('Show command JSON')))),
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
              onPressed:
                  widget.planGenerator != null && !hasGeneratedPlanCommand
                      ? null
                      : createPreview,
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
