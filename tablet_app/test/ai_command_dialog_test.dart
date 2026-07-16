import 'package:cadpilot_tablet/src/ai_command_dialog.dart';
import 'package:cadpilot_tablet/src/model_3d.dart';
import 'package:cadpilot_tablet/src/sketch_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI prompt input shares the server character limit and enables generation when valid',
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
}
