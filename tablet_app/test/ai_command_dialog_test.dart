import 'package:cadpilot_tablet/src/ai_command_dialog.dart';
import 'package:cadpilot_tablet/src/ai_planning.dart';
import 'package:cadpilot_tablet/src/ai_starter_templates.dart';
import 'package:cadpilot_tablet/src/model_3d.dart';
import 'package:cadpilot_tablet/src/sketch_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('unknown AI prompt creates and reuses a learned starter template',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = AiStarterTemplateStore();
    final plan = AiDesignPlan.fromMap({
      'schemaVersion': 1,
      'planId': 'p-custom',
      'summary': 'Create a magnetic seed sorting machine.',
      'extracted': {
        'objectType': 'magnetic seed sorting machine',
        'style': null,
        'dimensions': <Object?>[],
        'constraints': <Object?>[]
      },
      'missingInputs': <Object?>[],
      'options': [
        {
          'id': 'starter',
          'title': 'Machine starter',
          'description':
              'Frame, hopper, magnetic separation path, output tray.',
          'stages': ['Plan modules', 'Create starter geometry'],
          'assumptions': <Object?>[],
          'executableNow': false,
          'preparation': <Object?>[]
        },
        {
          'id': 'compact',
          'title': 'Compact machine',
          'description': 'Compact alternative.',
          'stages': ['Plan modules', 'Create starter geometry'],
          'assumptions': <Object?>[],
          'executableNow': false,
          'preparation': <Object?>[]
        },
      ],
      'canUseDefaults': true,
    });
    final first = await store.findOrCreate(
        prompt: 'create a magnetic seed sorting machine',
        plan: plan,
        option: plan.options.first);
    final second = await store.findOrCreate(
        prompt: 'build magnetic seed sorting machine',
        plan: plan,
        option: plan.options.first);
    final prepared = store.createSketch(
        template: second, base: const SketchDocument(), width: 500, depth: 300);

    expect(first.components, hasLength(greaterThanOrEqualTo(5)));
    expect(second.key, first.key);
    expect(second.uses, 2);
    expect(prepared.profiles, hasLength(first.components.length));
    expect(prepared.sketch.entities, hasLength(first.components.length));
    expect(first.components.map((item) => item.label).join(' '),
        contains('magnetic'));
  });

  testWidgets(
      'AI prompt input shares the server character limit and enables generation when valid',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiCommandDialog(
          sketch: const SketchDocument(),
          model: const ModelDocument(),
          generator: (_) async => throw UnimplementedError(),
        ),
      ),
    ));

    final prompt = find.byType(TextField).first;
    expect(tester.widget<TextField>(prompt).maxLength, maxAiPromptCharacters);
    final generate = find.widgetWithText(FilledButton, 'Generate');
    expect(tester.widget<FilledButton>(generate).onPressed, isNull);

    await tester.enterText(prompt, 'Extrude the base by 10 mm');
    await tester.pump();
    expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);
  });

  testWidgets('broad prompt shows planning questions, options, and staged plan',
      (tester) async {
    final raw = <String, Object?>{
      'schemaVersion': 1,
      'planId': 'p1',
      'summary': 'I can create this as a table.',
      'extracted': {
        'objectType': 'table',
        'style': null,
        'dimensions': <Object?>[],
        'constraints': <Object?>[]
      },
      'missingInputs': [
        {
          'id': 'width',
          'label': 'Width',
          'question': 'How wide?',
          'required': true,
          'suggestedValue': '1200 mm'
        }
      ],
      'options': [
        {
          'id': 'four-leg',
          'title': 'Rectangular tabletop with four legs',
          'description': 'Practical table',
          'stages': ['Confirm dimensions', 'Create profiles', 'Show preview'],
          'assumptions': <Object?>[],
          'executableNow': false,
          'preparation': ['Create profiles']
        },
        {
          'id': 'pedestal',
          'title': 'Round tabletop with pedestal base',
          'description': 'Round table',
          'stages': ['Confirm dimensions', 'Create profiles'],
          'assumptions': <Object?>[],
          'executableNow': false,
          'preparation': ['Create profiles']
        },
      ],
      'canUseDefaults': true,
    };
    final parsed = AiDesignPlan.fromMap(raw);
    expect(parsed.options.first.title, 'Rectangular tabletop with four legs');
    expect(parsed.options.first.stages, contains('Show preview'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AiCommandDialog(
                sketch: const SketchDocument(),
                model: const ModelDocument(),
                planGenerator: (_) async => AiPlanResponse(parsed, 12)))));
    await tester.enterText(
        find.byType(TextField).first, 'Create a moderate table');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Plan'));
    await tester.pumpAndSettle();
    expect(find.text('I can create this as a table.'), findsOneWidget);
    expect(find.text('Use sensible defaults'), findsOneWidget);
    expect(find.text('Critical details'), findsOneWidget);
  });
}
