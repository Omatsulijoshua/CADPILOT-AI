import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'ai_commands.dart';
import 'ai_planning.dart';
import 'ai_starter_templates.dart';
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
typedef AiStarterTemplatePublisher = Future<void> Function(
    LearnedStarterTemplate template);
typedef AiStarterTemplateFinder = Future<List<LearnedStarterTemplate>> Function(
    String prompt, String objectType);

const maxAiPromptCharacters = 2000;

enum _StarterFamily {
  rectangular,
  round,
  boredRound,
  gear,
  coil,
  motor,
  engine,
  solarGenerator,
  generatorSet,
  hardwareSystem,
  furniture
}

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
    AiPlanCommandGenerator? planCommandGenerator,
    AiStarterTemplatePublisher? starterTemplatePublisher,
    AiStarterTemplateFinder? starterTemplateFinder}) {
  return showDialog<AiCommandDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AiCommandDialog(
          sketch: sketch,
          model: model,
          generator: generator,
          planGenerator: planGenerator,
          planCommandGenerator: planCommandGenerator,
          starterTemplatePublisher: starterTemplatePublisher,
          starterTemplateFinder: starterTemplateFinder));
}

class AiCommandDialog extends StatefulWidget {
  const AiCommandDialog(
      {required this.sketch,
      required this.model,
      this.generator,
      this.planGenerator,
      this.planCommandGenerator,
      this.starterTemplatePublisher,
      this.starterTemplateFinder,
      super.key});
  final SketchDocument sketch;
  final ModelDocument model;
  final AiCommandGenerator? generator;
  final AiPlanGenerator? planGenerator;
  final AiPlanCommandGenerator? planCommandGenerator;
  final AiStarterTemplatePublisher? starterTemplatePublisher;
  final AiStarterTemplateFinder? starterTemplateFinder;

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
  LearnedStarterTemplate? activeStarterTemplate;
  List<SketchEntity> activeStarterProfiles = const [];
  String? error;
  AiDesignPlan? plan;
  AiPlanOption? selectedOption;
  final Map<String, TextEditingController> answers = {};
  bool hasGeneratedPlanCommand = false;
  bool showJson = false;
  Timer? buildStatusTimer;
  int buildStatusIndex = 0;
  String? buildStatusText;

  static const buildStatusMessages = [
    'Searching online references...',
    'Studying sample components...',
    'Crafting the CAD plan...',
    'Building starter geometry...',
    'Almost done...',
    'Refining and adding finishing touches...',
  ];

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
    buildStatusTimer?.cancel();
    input.dispose();
    prompt.dispose();
    for (final controller in answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void startBuildStatus() {
    buildStatusTimer?.cancel();
    buildStatusIndex = 0;
    buildStatusText = buildStatusMessages.first;
    buildStatusTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (!mounted || !generating) return;
      setState(() {
        buildStatusIndex = buildStatusIndex + 1 >= buildStatusMessages.length
            ? buildStatusMessages.length - 1
            : buildStatusIndex + 1;
        buildStatusText = buildStatusMessages[buildStatusIndex];
      });
    });
  }

  void finishBuildStatus({required bool success}) {
    buildStatusTimer?.cancel();
    buildStatusTimer = null;
    if (!mounted) return;
    setState(() {
      buildStatusText = success ? 'Done.' : null;
    });
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
    startBuildStatus();
    var success = false;
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
      success = true;
    } catch (value) {
      setState(() => error = value.toString());
    } finally {
      if (mounted) setState(() => generating = false);
      finishBuildStatus(success: success);
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
    startBuildStatus();
    var success = false;
    try {
      final preparedSketch = await preparedSketchForPlan();
      final answerValues = {
        for (final entry in answers.entries) entry.key: entry.value.text.trim()
      };
      final family = _starterFamily(_planText(currentPlan, option));
      final forceLocalStarter = family == _StarterFamily.generatorSet ||
          family == _StarterFamily.hardwareSystem ||
          family == _StarterFamily.solarGenerator ||
          family == _StarterFamily.motor ||
          family == _StarterFamily.engine ||
          family == _StarterFamily.coil ||
          activeStarterTemplate != null;
      final localDraft = AiGeneratedDraft(
          starterCommandForPlan(
              preparedSketch, currentPlan, option, answerValues),
          0);
      AiGeneratedDraft draft;
      if (option.executableNow && !forceLocalStarter) {
        try {
          draft = await generator(prompt.text.trim(), currentPlan, option,
              answerValues, preparedSketch);
        } catch (_) {
          draft = localDraft;
        }
      } else {
        draft = localDraft;
      }
      input.text = const JsonEncoder.withIndent('  ').convert(draft.command);
      totalTokens = draft.totalTokens;
      hasGeneratedPlanCommand = true;
      createPreview(sketch: preparedSketch);
      success = true;
    } catch (value) {
      setState(() => error = value.toString());
    } finally {
      if (mounted) setState(() => generating = false);
      finishBuildStatus(success: success);
    }
  }

  Future<SketchDocument> preparedSketchForPlan() async {
    final current = plan;
    final option = selectedOption;
    if (current == null || option == null) return widget.sketch;
    activeStarterTemplate = null;
    activeStarterProfiles = const [];
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
    final needsSystem = family == _StarterFamily.solarGenerator ||
        family == _StarterFamily.generatorSet ||
        family == _StarterFamily.motor ||
        family == _StarterFamily.engine ||
        family == _StarterFamily.coil ||
        family == _StarterFamily.hardwareSystem;
    final shouldLearnStarter = family == _StarterFamily.rectangular &&
        !needsTable &&
        !needsChair &&
        !needsGear &&
        !needsRound;
    if (shouldLearnStarter) {
      final store = AiStarterTemplateStore();
      var sharedTemplates = const <LearnedStarterTemplate>[];
      try {
        sharedTemplates = await (widget.starterTemplateFinder
                ?.call(prompt.text.trim(), current.objectType) ??
            Future<List<LearnedStarterTemplate>>.value(const []));
      } catch (_) {
        sharedTemplates = const [];
      }
      final template = await store.findOrCreate(
          prompt: prompt.text.trim(),
          plan: current,
          option: option,
          sharedTemplates: sharedTemplates);
      unawaited(widget.starterTemplatePublisher?.call(template) ??
          Future<void>.value());
      final prepared = store.createSketch(
          template: template, base: widget.sketch, width: width, depth: depth);
      activeStarterTemplate = template;
      activeStarterProfiles = prepared.profiles;
      return prepared.sketch;
    }
    if (needsSystem) {
      final prepared = _preparedHardwareSystemSketch(
          family: family,
          width: width,
          depth: depth,
          height: height,
          existingRectangles: widget.sketch.entities
              .where((item) => item.kind == SketchEntityKind.rectangle)
              .toList(),
          hasCircle: widget.sketch.entities
              .any((item) => item.kind == SketchEntityKind.circle));
      if (prepared.isEmpty) return widget.sketch;
      return widget.sketch
          .copyWith(entities: [...widget.sketch.entities, ...prepared]);
    }
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

  List<SketchEntity> _preparedHardwareSystemSketch({
    required _StarterFamily family,
    required double width,
    required double depth,
    required double height,
    required List<SketchEntity> existingRectangles,
    required bool hasCircle,
  }) {
    final requiredRectangles = family == _StarterFamily.generatorSet
        ? 6
        : family == _StarterFamily.engine
            ? 5
            : family == _StarterFamily.hardwareSystem
                ? 5
                : 3;
    if (existingRectangles.length >= requiredRectangles && hasCircle) {
      return const [];
    }
    final entities = <SketchEntity>[];
    var cursorX = existingRectangles.isEmpty
        ? 0.0
        : existingRectangles
                .map((item) =>
                    item.end.dx > item.start.dx ? item.end.dx : item.start.dx)
                .reduce((a, b) => a > b ? a : b) +
            140;
    void addRect(double w, double d) {
      entities.add(SketchEntity(
          id: const Uuid().v4(),
          kind: SketchEntityKind.rectangle,
          start: Offset(cursorX, 0),
          end: Offset(cursorX + w, d),
          dimensionLocked: true));
      cursorX += w + 120;
    }

    switch (family) {
      case _StarterFamily.solarGenerator:
        addRect(width.clamp(300, 1600).toDouble(),
            depth.clamp(180, 900).toDouble());
        addRect((width * 0.32).clamp(120, 500).toDouble(),
            (depth * 0.62).clamp(100, 500).toDouble());
        addRect((width * 0.24).clamp(100, 420).toDouble(),
            (depth * 0.46).clamp(80, 420).toDouble());
        break;
      case _StarterFamily.generatorSet:
        addRect(width.clamp(600, 2200).toDouble(),
            (depth * 0.18).clamp(80, 220).toDouble());
        addRect((width * 0.28).clamp(180, 620).toDouble(),
            (depth * 0.48).clamp(160, 520).toDouble());
        addRect((width * 0.22).clamp(150, 520).toDouble(),
            (depth * 0.22).clamp(70, 220).toDouble());
        addRect((width * 0.36).clamp(240, 760).toDouble(),
            (depth * 0.24).clamp(90, 260).toDouble());
        addRect((width * 0.14).clamp(90, 260).toDouble(),
            (depth * 0.36).clamp(120, 360).toDouble());
        addRect((width * 0.18).clamp(90, 360).toDouble(),
            (height * 0.18).clamp(20, 120).toDouble());
        if (!hasCircle) {
          final radius = (depth * 0.08).clamp(18, 70).toDouble();
          entities.add(SketchEntity(
              id: const Uuid().v4(),
              kind: SketchEntityKind.circle,
              start: Offset(cursorX + radius, radius),
              end: Offset(cursorX + radius * 2, radius),
              dimensionLocked: true));
        }
        break;
      case _StarterFamily.engine:
        addRect((width * 0.45).clamp(180, 700).toDouble(),
            (depth * 0.45).clamp(140, 500).toDouble());
        addRect((width * 0.38).clamp(160, 620).toDouble(),
            (depth * 0.18).clamp(60, 200).toDouble());
        addRect((width * 0.22).clamp(80, 260).toDouble(),
            (height * 0.16).clamp(20, 100).toDouble());
        addRect((width * 0.18).clamp(70, 240).toDouble(),
            (height * 0.2).clamp(24, 120).toDouble());
        addRect((width * 0.24).clamp(100, 340).toDouble(),
            (depth * 0.16).clamp(40, 160).toDouble());
        break;
      case _StarterFamily.motor:
        addRect(
            width.clamp(180, 800).toDouble(), depth.clamp(120, 500).toDouble());
        if (!hasCircle) {
          final radius = (width * 0.18).clamp(40, 180).toDouble();
          entities.add(SketchEntity(
              id: const Uuid().v4(),
              kind: SketchEntityKind.circle,
              start: Offset(cursorX + radius, radius),
              end: Offset(cursorX + radius * 2, radius),
              dimensionLocked: true));
        }
        break;
      case _StarterFamily.coil:
        addRect((width * 0.45).clamp(80, 600).toDouble(),
            height.clamp(20, 240).toDouble());
        if (!hasCircle) {
          final radius = (width * 0.12).clamp(12, 120).toDouble();
          entities.add(SketchEntity(
              id: const Uuid().v4(),
              kind: SketchEntityKind.circle,
              start: Offset(cursorX, radius * 2),
              end: Offset(cursorX + radius, radius * 2),
              dimensionLocked: true));
        }
        break;
      case _StarterFamily.hardwareSystem:
        addRect(width.clamp(160, 1200).toDouble(),
            depth.clamp(120, 800).toDouble());
        addRect((width * 0.38).clamp(80, 500).toDouble(),
            (depth * 0.55).clamp(80, 400).toDouble());
        addRect((width * 0.26).clamp(60, 360).toDouble(),
            (depth * 0.38).clamp(60, 300).toDouble());
        addRect((width * 0.18).clamp(50, 260).toDouble(),
            (depth * 0.28).clamp(50, 220).toDouble());
        addRect((width * 0.22).clamp(60, 320).toDouble(),
            (depth * 0.18).clamp(40, 180).toDouble());
        break;
      case _:
        break;
    }
    return entities;
  }

  Map<String, Object?> starterCommandForPlan(
      SketchDocument sketch,
      AiDesignPlan current,
      AiPlanOption option,
      Map<String, String> answerValues) {
    final allRectangles = sketch.entities
        .where((item) => item.kind == SketchEntityKind.rectangle)
        .toList();
    final circles =
        sketch.entities.where((item) => item.kind == SketchEntityKind.circle);
    final text = _planText(current, option);
    final family = _starterFamily(text);
    final needsGear = family == _StarterFamily.gear;
    final needsRound =
        family == _StarterFamily.round || family == _StarterFamily.boredRound;
    final isHardwareSystem = family == _StarterFamily.solarGenerator ||
        family == _StarterFamily.generatorSet ||
        family == _StarterFamily.engine ||
        family == _StarterFamily.hardwareSystem;
    final isGeneratorSet = family == _StarterFamily.generatorSet;
    final isEngine = family == _StarterFamily.engine;
    final isMotorOrCoil =
        family == _StarterFamily.motor || family == _StarterFamily.coil;
    if (activeStarterTemplate != null && activeStarterProfiles.isNotEmpty) {
      return _starterCommandFromTemplate(
          activeStarterTemplate!, activeStarterProfiles, current, option);
    }
    final neededRectangles = isGeneratorSet
        ? 6
        : isEngine || family == _StarterFamily.hardwareSystem
            ? 5
            : isMotorOrCoil ||
                    family == _StarterFamily.solarGenerator ||
                    needsRound
                ? 3
                : 6;
    final rectangles = allRectangles.length > neededRectangles
        ? allRectangles.sublist(allRectangles.length - neededRectangles)
        : allRectangles;
    if (rectangles.isEmpty && (!needsGear || circles.isEmpty)) {
      throw const FormatException('Create or approve a starter profile first.');
    }
    final thickness =
        _dimensionValue(answerValues, ['tabletopthickness', 'thickness']) ?? 30;
    final operations = <Map<String, Object?>>[];
    for (var index = 0; index < rectangles.length; index += 1) {
      if (isGeneratorSet && (index == 2 || index == 5)) {
        operations.add({
          'operationId': const Uuid().v4(),
          'type': 'revolve',
          'parameters': {
            'profileId': rectangles[index].id,
            'angle': 360,
            'name': _generatorSetComponentLabel(index)
          }
        });
        continue;
      }
      if (isEngine && (index == 2 || index == 3)) {
        operations.add({
          'operationId': const Uuid().v4(),
          'type': 'revolve',
          'parameters': {
            'profileId': rectangles[index].id,
            'angle': 360,
            'name': _engineComponentLabel(index)
          }
        });
        continue;
      }
      final profile = rectangles[index];
      if ((needsRound || isMotorOrCoil) && index == rectangles.length - 1) {
        operations.add({
          'operationId': const Uuid().v4(),
          'type': 'revolve',
          'parameters': {'profileId': profile.id, 'angle': 360}
        });
        if ((family == _StarterFamily.boredRound || isMotorOrCoil) &&
            circles.isNotEmpty) {
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
      final label = isGeneratorSet
          ? _generatorSetComponentLabel(index)
          : isEngine
              ? _engineComponentLabel(index)
              : index == 0
                  ? isHardwareSystem
                      ? 'system enclosure starter'
                      : 'table starter solid'
                  : index == 1
                      ? isHardwareSystem
                          ? 'energy/control module starter'
                          : 'chair starter solid'
                      : index == 2
                          ? isHardwareSystem
                              ? 'interface/subsystem starter'
                              : 'gear-system starter solid'
                          : index == 3 && isHardwareSystem
                              ? 'mounting / safety module starter'
                              : index == 4 && isHardwareSystem
                                  ? 'future expansion module starter'
                                  : 'starter solid';
      final depth = isGeneratorSet
          ? _generatorSetComponentDepth(index)
          : isEngine
              ? _engineComponentDepth(index)
              : index == 0
                  ? isHardwareSystem
                      ? (family == _StarterFamily.solarGenerator ? 90.0 : 45.0)
                      : thickness
                  : index == 1
                      ? isHardwareSystem
                          ? 55.0
                          : 45.0
                      : index == 2
                          ? isHardwareSystem
                              ? 35.0
                              : 60.0
                          : index == 3 && isHardwareSystem
                              ? 30.0
                              : index == 4 && isHardwareSystem
                                  ? 24.0
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
        family == _StarterFamily.generatorSet
            ? 'The generator set is created as an open internal assembly with mixed starter geometry: skid/base and panels use editable solids, while the alternator/generator head and exhaust use revolved cylindrical parts instead of square blocks.'
            : family == _StarterFamily.engine
                ? 'The engine is created as a visible simplified assembly with separate starter parts: engine block, cylinder head, crankshaft, flywheel, and intake/exhaust manifold. Cylindrical rotating parts are revolved instead of square blocks.'
                : family == _StarterFamily.solarGenerator ||
                        family == _StarterFamily.hardwareSystem
                    ? 'Complex hardware systems start as subsystem CAD blocks before detailed parts are generated.'
                    : 'Separate starter profiles are used so table, chair, and gear-system requests do not collapse into one cube.',
        if (current.canUseDefaults)
          'Sensible default dimensions are used where the prompt did not provide exact measurements.',
        ...option.assumptions,
      ],
      'requiresConfirmation': true
    };
  }

  Map<String, Object?> _starterCommandFromTemplate(
      LearnedStarterTemplate template,
      List<SketchEntity> profiles,
      AiDesignPlan current,
      AiPlanOption option) {
    final operations = <Map<String, Object?>>[];
    for (var index = 0;
        index < profiles.length && index < template.components.length;
        index += 1) {
      final component = template.components[index];
      operations.add({
        'operationId': const Uuid().v4(),
        'type': component.revolved ? 'revolve' : 'extrude',
        'parameters': {
          'profileId': profiles[index].id,
          if (component.revolved)
            'angle': 360
          else
            'depth': component.extrudeDepth,
          'name': component.label,
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
        'CadPilot did not have a built-in local starter for this prompt, so it created and saved a reusable starter template named "${template.title}".',
        'Future similar prompts can reuse this local starter instead of collapsing into one cube.',
        'The starter separates the design into named editable modules: body/frame, functional core, input, output/motion, and control/mounting.',
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

  String _generatorSetComponentLabel(int index) {
    const labels = [
      'open skid frame / base starter',
      'engine block starter',
      'alternator / generator head starter',
      'fuel tank starter',
      'control panel starter',
      'muffler / exhaust starter',
    ];
    return labels[index.clamp(0, labels.length - 1)];
  }

  double _generatorSetComponentDepth(int index) {
    const depths = [40.0, 180.0, 150.0, 120.0, 35.0, 60.0];
    return depths[index.clamp(0, depths.length - 1)];
  }

  String _engineComponentLabel(int index) {
    const labels = [
      'engine block starter',
      'cylinder head starter',
      'crankshaft starter',
      'flywheel starter',
      'intake / exhaust manifold starter',
    ];
    return labels[index.clamp(0, labels.length - 1)];
  }

  double _engineComponentDepth(int index) {
    const depths = [180.0, 70.0, 45.0, 65.0, 35.0];
    return depths[index.clamp(0, depths.length - 1)];
  }

  String _planText(AiDesignPlan current, AiPlanOption option) =>
      '${prompt.text} ${current.summary} ${current.objectType} ${current.style ?? ''} ${option.title} ${option.description}'
          .toLowerCase();

  _StarterFamily _starterFamily(String text) {
    final solarLikeGenerator = text.contains('solar generator') ||
        text.contains('solar gen') ||
        text.contains('power station') ||
        text.contains('solar power') ||
        text.contains('battery generator');
    if (text.contains('generator set') ||
        text.contains('genset') ||
        text.contains('gen set') ||
        text.contains('petrol generator') ||
        text.contains('diesel generator') ||
        text.contains('gas generator') ||
        text.contains('generator without cover') ||
        text.contains('without outside cover') ||
        text.contains('no outside cover') ||
        (text.contains('generator') && !solarLikeGenerator)) {
      return _StarterFamily.generatorSet;
    }
    if (solarLikeGenerator) {
      return _StarterFamily.solarGenerator;
    }
    if (text.contains('engine') ||
        text.contains('piston') ||
        text.contains('crankshaft') ||
        text.contains('cylinder head') ||
        text.contains('combustion')) {
      return _StarterFamily.engine;
    }
    if (text.contains('electric motor') ||
        text.contains('electric moto') ||
        text.contains('generator motor') ||
        text.contains('alternator') ||
        text.contains('rotor') ||
        text.contains('stator')) {
      return _StarterFamily.motor;
    }
    if (text.contains('coil') ||
        text.contains('solenoid') ||
        text.contains('winding') ||
        text.contains('inductor') ||
        text.contains('electromagnet')) {
      return _StarterFamily.coil;
    }
    if (text.contains('hardware system') ||
        text.contains('new hardware') ||
        text.contains('custom hardware') ||
        text.contains('new system') ||
        text.contains('from scratch') ||
        text.contains('scratch') ||
        text.contains('invent') ||
        text.contains('invention') ||
        text.contains('prototype') ||
        text.contains('vibe') ||
        text.contains('correct') ||
        text.contains('refine') ||
        text.contains('improve') ||
        text.contains('keep adding') ||
        text.contains('brainstorm') ||
        text.contains('machine') ||
        text.contains('device') ||
        text.contains('mechanism')) {
      return _StarterFamily.hardwareSystem;
    }
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
    startBuildStatus();
    var success = false;
    try {
      final draft = await generator(promptText);
      input.text = const JsonEncoder.withIndent('  ').convert(draft.command);
      setState(() => totalTokens = draft.totalTokens);
      createPreview();
      success = true;
    } catch (value) {
      setState(() => error = value.toString());
    } finally {
      if (mounted) setState(() => generating = false);
      finishBuildStatus(success: success);
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
          Text('AI command / vibe CAD')
        ]),
        content: SizedBox(
            width: 720,
            height: 520,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'Create from scratch, correct, add modules, and keep building through prompts. Commands are validated locally and apply only after preview approval.'),
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
                            : 'Invent a portable seed-sorting machine from scratch, then I will keep adding and correcting it',
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
                  if (buildStatusText != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      if (generating) ...[
                        const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                          child: Text(buildStatusText!,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.primary))),
                    ]),
                  ],
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
