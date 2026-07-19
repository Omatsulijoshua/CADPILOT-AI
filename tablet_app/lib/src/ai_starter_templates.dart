import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'ai_planning.dart';
import 'sketch_models.dart';

class StarterTemplateComponent {
  const StarterTemplateComponent({
    required this.label,
    required this.widthRatio,
    required this.depthRatio,
    required this.extrudeDepth,
    this.revolved = false,
  });

  final String label;
  final double widthRatio;
  final double depthRatio;
  final double extrudeDepth;
  final bool revolved;

  Map<String, Object?> toJson() => {
        'label': label,
        'widthRatio': widthRatio,
        'depthRatio': depthRatio,
        'extrudeDepth': extrudeDepth,
        'revolved': revolved,
      };

  factory StarterTemplateComponent.fromJson(Map<String, Object?> json) =>
      StarterTemplateComponent(
        label: (json['label'] as String?) ?? 'starter component',
        widthRatio: ((json['widthRatio'] as num?) ?? 0.3).toDouble(),
        depthRatio: ((json['depthRatio'] as num?) ?? 0.3).toDouble(),
        extrudeDepth: ((json['extrudeDepth'] as num?) ?? 40).toDouble(),
        revolved: (json['revolved'] as bool?) ?? false,
      );
}

class LearnedStarterTemplate {
  const LearnedStarterTemplate({
    required this.key,
    required this.title,
    required this.components,
    required this.createdAt,
    this.uses = 1,
  });

  final String key;
  final String title;
  final List<StarterTemplateComponent> components;
  final DateTime createdAt;
  final int uses;

  Map<String, Object?> toJson() => {
        'key': key,
        'title': title,
        'components': components.map((item) => item.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'uses': uses,
      };

  factory LearnedStarterTemplate.fromJson(Map<String, Object?> json) =>
      LearnedStarterTemplate(
        key: (json['key'] as String?) ?? '',
        title: (json['title'] as String?) ?? 'custom starter',
        components: (json['components'] as List<Object?>? ?? const [])
            .map((item) => StarterTemplateComponent.fromJson(
                Map<String, Object?>.from(item! as Map)))
            .toList(growable: false),
        createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
            DateTime.now(),
        uses: (json['uses'] as int?) ?? 1,
      );

  LearnedStarterTemplate copyWith({int? uses}) => LearnedStarterTemplate(
        key: key,
        title: title,
        components: components,
        createdAt: createdAt,
        uses: uses ?? this.uses,
      );
}

class StarterTemplateSketch {
  const StarterTemplateSketch(this.sketch, this.profiles);
  final SketchDocument sketch;
  final List<SketchEntity> profiles;
}

class AiStarterTemplateStore {
  static const _storageKey = 'cadpilot.ai.starter.templates.v1';
  static const _uuid = Uuid();

  Future<LearnedStarterTemplate> findOrCreate({
    required String prompt,
    required AiDesignPlan plan,
    required AiPlanOption option,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final templates = _readTemplates(prefs);
    final key = normalizeKey(prompt, plan.objectType);
    final exact = templates[key];
    if (exact != null && exact.components.isNotEmpty) {
      templates[key] = exact.copyWith(uses: exact.uses + 1);
      await _writeTemplates(prefs, templates);
      return templates[key]!;
    }

    final similar = _findSimilar(templates, key);
    if (similar != null && similar.components.isNotEmpty) {
      templates[key] = similar.copyWith(uses: similar.uses + 1);
      await _writeTemplates(prefs, templates);
      return templates[key]!;
    }

    final created = _createTemplate(prompt: prompt, plan: plan, option: option);
    templates[key] = created;
    await _writeTemplates(prefs, templates);
    return created;
  }

  static String normalizeKey(String prompt, String objectType) {
    final text = '$prompt $objectType'.toLowerCase();
    final normalized = text
        .replaceAll(RegExp(r'\b\d+(?:\.\d+)?\s*(mm|cm|m|inch|in|kw|w)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) =>
            word.length > 2 &&
            !{
              'create',
              'make',
              'build',
              'simple',
              'moderate',
              'detailed',
              'with',
              'from',
              'the',
              'and',
              'for',
              'starter',
              'custom',
              'cad',
              'part',
              'object',
            }.contains(word))
        .take(6)
        .join('-');
    return normalized.isEmpty ? 'learned-starter' : normalized;
  }

  StarterTemplateSketch createSketch({
    required LearnedStarterTemplate template,
    required SketchDocument base,
    required double width,
    required double depth,
  }) {
    final existingRectangles =
        base.entities.where((item) => item.kind == SketchEntityKind.rectangle);
    var cursorX = existingRectangles.isEmpty
        ? 0.0
        : existingRectangles
                .map((item) =>
                    item.end.dx > item.start.dx ? item.end.dx : item.start.dx)
                .reduce((a, b) => a > b ? a : b) +
            140;
    final profiles = <SketchEntity>[];
    for (final component in template.components) {
      final profileWidth =
          (width * component.widthRatio).clamp(50.0, 900.0).toDouble();
      final profileDepth =
          (depth * component.depthRatio).clamp(35.0, 650.0).toDouble();
      final entity = SketchEntity(
        id: _uuid.v4(),
        kind: SketchEntityKind.rectangle,
        start: Offset(cursorX, 0),
        end: Offset(cursorX + profileWidth, profileDepth),
        dimensionLocked: true,
      );
      profiles.add(entity);
      cursorX += profileWidth + 120;
    }
    return StarterTemplateSketch(
      base.copyWith(entities: [...base.entities, ...profiles]),
      profiles,
    );
  }

  Map<String, LearnedStarterTemplate> _readTemplates(SharedPreferences prefs) {
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      return {
        for (final item in decoded)
          if (item is Map)
            LearnedStarterTemplate.fromJson(Map<String, Object?>.from(item))
                    .key:
                LearnedStarterTemplate.fromJson(Map<String, Object?>.from(item))
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeTemplates(SharedPreferences prefs,
      Map<String, LearnedStarterTemplate> templates) async {
    final values = templates.values.toList()
      ..sort((a, b) => b.uses.compareTo(a.uses));
    await prefs.setString(
      _storageKey,
      jsonEncode(values.take(80).map((item) => item.toJson()).toList()),
    );
  }

  LearnedStarterTemplate? _findSimilar(
      Map<String, LearnedStarterTemplate> templates, String key) {
    final parts = key.split('-').toSet();
    LearnedStarterTemplate? best;
    var bestScore = 0;
    for (final template in templates.values) {
      final score =
          template.key.split('-').where((word) => parts.contains(word)).length;
      if (score > bestScore) {
        bestScore = score;
        best = template;
      }
    }
    return bestScore >= 2 ? best : null;
  }

  LearnedStarterTemplate _createTemplate({
    required String prompt,
    required AiDesignPlan plan,
    required AiPlanOption option,
  }) {
    final title = _titleFrom(plan.objectType, option.title, prompt);
    final nouns = _keywords('$prompt ${plan.objectType} ${option.title}');
    final base = nouns.isEmpty ? title : nouns.take(3).join(' ');
    final components = <StarterTemplateComponent>[
      StarterTemplateComponent(
          label: '$base main body / frame',
          widthRatio: 0.5,
          depthRatio: 0.42,
          extrudeDepth: 80),
      StarterTemplateComponent(
          label: '$base functional core',
          widthRatio: 0.34,
          depthRatio: 0.32,
          extrudeDepth: 95),
      StarterTemplateComponent(
          label: '$base input module',
          widthRatio: 0.24,
          depthRatio: 0.22,
          extrudeDepth: 45),
      StarterTemplateComponent(
          label: '$base output / motion module',
          widthRatio: 0.22,
          depthRatio: 0.2,
          extrudeDepth: 55,
          revolved: _looksRotational('$prompt ${option.description}')),
      StarterTemplateComponent(
          label: '$base control / mounting module',
          widthRatio: 0.2,
          depthRatio: 0.26,
          extrudeDepth: 35),
    ];
    return LearnedStarterTemplate(
      key: normalizeKey(prompt, plan.objectType),
      title: title,
      components: components,
      createdAt: DateTime.now(),
    );
  }

  static String _titleFrom(
      String objectType, String optionTitle, String prompt) {
    final raw = objectType.trim().isNotEmpty
        ? objectType
        : optionTitle.trim().isNotEmpty
            ? optionTitle
            : prompt;
    return raw.length > 60 ? raw.substring(0, 60) : raw;
  }

  static List<String> _keywords(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) =>
          word.length > 2 &&
          !{
            'create',
            'make',
            'build',
            'simple',
            'moderate',
            'detailed',
            'starter',
            'layout',
            'option',
            'system',
            'custom',
            'with',
            'from',
            'and',
            'the',
          }.contains(word))
      .toList(growable: false);

  static bool _looksRotational(String text) {
    final lower = text.toLowerCase();
    return lower.contains('motor') ||
        lower.contains('wheel') ||
        lower.contains('shaft') ||
        lower.contains('rotor') ||
        lower.contains('pulley') ||
        lower.contains('fan') ||
        lower.contains('turbine') ||
        lower.contains('spin') ||
        lower.contains('rotate');
  }
}
