import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'ai_commands.dart';
import 'model_3d.dart';
import 'sketch_models.dart';

class AiGeneratedDraft {
  const AiGeneratedDraft(this.command, this.totalTokens);
  final Map<String, Object?> command;
  final int totalTokens;
}

typedef AiCommandGenerator = Future<AiGeneratedDraft> Function(String prompt);

class AiCommandDecision {
  const AiCommandDecision({required this.record, this.model});
  final AiCommandRecord record;
  final ModelDocument? model;
}

Future<AiCommandDecision?> showAiCommandDialog(BuildContext context,
    {required SketchDocument sketch,
    required ModelDocument model,
    AiCommandGenerator? generator}) {
  return showDialog<AiCommandDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          AiCommandDialog(sketch: sketch, model: model, generator: generator));
}

class AiCommandDialog extends StatefulWidget {
  const AiCommandDialog(
      {required this.sketch, required this.model, this.generator, super.key});
  final SketchDocument sketch;
  final ModelDocument model;
  final AiCommandGenerator? generator;

  @override
  State<AiCommandDialog> createState() => _AiCommandDialogState();
}

class _AiCommandDialogState extends State<AiCommandDialog> {
  late final TextEditingController input;
  final prompt = TextEditingController();
  bool generating = false;
  int? totalTokens;
  AiCommandPreview? preview;
  String? error;

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
    super.dispose();
  }

  Future<void> generate() async {
    final generator = widget.generator;
    if (generator == null || prompt.text.trim().isEmpty) return;
    setState(() {
      generating = true;
      error = null;
      preview = null;
    });
    try {
      final draft = await generator(prompt.text.trim());
      input.text = const JsonEncoder.withIndent('  ').convert(draft.command);
      setState(() => totalTokens = draft.totalTokens);
      createPreview();
    } catch (value) {
      setState(() => error = value.toString());
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  void createPreview() {
    try {
      final decoded = jsonDecode(input.text);
      if (decoded is! Map) {
        throw const FormatException('Command must be a JSON object.');
      }
      final command = AiCadCommand.fromJson(Map<String, Object?>.from(decoded));
      final value =
          const AiCommandEngine().preview(command, widget.sketch, widget.model);
      setState(() {
        preview = value;
        error = null;
      });
    } catch (value) {
      setState(() {
        preview = null;
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
                      enabled: widget.generator != null && !generating,
                      decoration: InputDecoration(
                        labelText: 'Describe the change',
                        hintText: widget.generator == null
                            ? 'Sign in to generate commands from natural language.'
                            : 'Extrude the base by 10 mm and cut the centre hole',
                      ),
                    )),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: widget.generator == null || generating
                          ? null
                          : generate,
                      icon: generating
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome),
                      label: Text(generating ? 'Generating' : 'Generate'),
                    ),
                  ]),
                  if (totalTokens != null)
                    Text('Usage: $totalTokens tokens',
                        textAlign: TextAlign.right),
                  const SizedBox(height: 12),
                  Expanded(
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
              onPressed: createPreview,
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
