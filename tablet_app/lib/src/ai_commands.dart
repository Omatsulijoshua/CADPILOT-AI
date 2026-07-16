import 'model_3d.dart';
import 'sketch_models.dart';

enum AiCommandStatus { previewed, applied, cancelled, rejected, undone }

class AiCommandRecord {
  const AiCommandRecord(
      {required this.commandId,
      required this.summary,
      required this.status,
      required this.createdAt,
      this.previousModel});
  final String commandId;
  final String summary;
  final AiCommandStatus status;
  final DateTime createdAt;
  final ModelDocument? previousModel;
  AiCommandRecord copyWith({AiCommandStatus? status}) => AiCommandRecord(
      commandId: commandId,
      summary: summary,
      status: status ?? this.status,
      createdAt: createdAt,
      previousModel: previousModel);
  Map<String, Object?> toJson() => {
        'commandId': commandId,
        'summary': summary,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        if (previousModel != null) 'previousModel': previousModel!.toJson()
      };
  factory AiCommandRecord.fromJson(Map<String, Object?> json) =>
      AiCommandRecord(
          commandId: json['commandId']! as String,
          summary: json['summary']! as String,
          status: AiCommandStatus.values.byName(json['status']! as String),
          createdAt: DateTime.parse(json['createdAt']! as String),
          previousModel: ModelDocument.fromJson(
              json['previousModel'] as Map<String, Object?>?));
}

class AiCadCommand {
  const AiCadCommand(
      {required this.commandId,
      required this.intent,
      required this.operations,
      required this.assumptions,
      required this.requiresConfirmation});
  final String commandId;
  final String intent;
  final List<AiCadOperation> operations;
  final List<String> assumptions;
  final bool requiresConfirmation;

  factory AiCadCommand.fromJson(Map<String, Object?> json) {
    const required = {
      'schemaVersion',
      'commandId',
      'intent',
      'target',
      'operations',
      'assumptions',
      'requiresConfirmation'
    };
    if (json.keys.toSet().difference(required).isNotEmpty ||
        !required.every(json.containsKey)) {
      throw const FormatException(
          'Command does not match the approved schema.');
    }
    if (json['schemaVersion'] != 1 ||
        json['commandId'] is! String ||
        (json['commandId'] as String).isEmpty) {
      throw const FormatException('Command version or ID is invalid.');
    }
    final operations = json['operations'];
    final assumptions = json['assumptions'];
    if (operations is! List ||
        operations.isEmpty ||
        assumptions is! List ||
        json['requiresConfirmation'] is! bool) {
      throw const FormatException(
          'Command operations, assumptions, or confirmation flag is invalid.');
    }
    return AiCadCommand(
      commandId: json['commandId']! as String,
      intent: json['intent']! as String,
      operations: operations
          .map((value) =>
              AiCadOperation.fromJson(value! as Map<String, Object?>))
          .toList(),
      assumptions: assumptions.map((value) => value! as String).toList(),
      requiresConfirmation: json['requiresConfirmation']! as bool,
    );
  }
}

class AiCadOperation {
  const AiCadOperation(
      {required this.operationId,
      required this.type,
      required this.parameters});
  final String operationId;
  final String type;
  final Map<String, Object?> parameters;
  factory AiCadOperation.fromJson(Map<String, Object?> json) {
    if (json['operationId'] is! String ||
        json['type'] is! String ||
        json['parameters'] is! Map) {
      throw const FormatException('An AI operation is malformed.');
    }
    return AiCadOperation(
        operationId: json['operationId']! as String,
        type: json['type']! as String,
        parameters: Map<String, Object?>.from(json['parameters']! as Map));
  }
}

class AiCommandPreview {
  const AiCommandPreview(
      {required this.command, required this.model, required this.summary});
  final AiCadCommand command;
  final ModelDocument model;
  final String summary;
}

class AiCommandEngine {
  const AiCommandEngine();
  static const supported = {'extrude', 'cut', 'revolve', 'rename', 'delete'};

  AiCommandPreview preview(
      AiCadCommand command, SketchDocument sketch, ModelDocument current) {
    var next = current;
    final summaries = <String>[];
    for (final operation in command.operations) {
      if (!supported.contains(operation.type)) {
        throw FormatException(
            'Operation ${operation.type} is not supported safely yet.');
      }
      final p = operation.parameters;
      switch (operation.type) {
        case 'extrude':
          final profile =
              _profile(sketch, p['profileId'], SketchEntityKind.rectangle);
          final depth = _positiveNumber(p['depth'], 'depth');
          next = next.add(ModelOperation(
              id: operation.operationId,
              kind: ModelOperationKind.extrude,
              profileId: profile.id,
              depth: depth,
              createdAt: DateTime.now().toUtc()));
          summaries
              .add('Extrude ${profile.id} by ${depth.toStringAsFixed(1)} mm');
        case 'cut':
          if (const ModelEvaluator().evaluate(sketch, next) == null) {
            throw const FormatException(
                'A cut requires an active extruded solid.');
          }
          final profile =
              _profile(sketch, p['profileId'], SketchEntityKind.circle);
          final depth = _positiveNumber(p['depth'], 'depth');
          next = next.add(ModelOperation(
              id: operation.operationId,
              kind: ModelOperationKind.circularCut,
              profileId: profile.id,
              depth: depth,
              createdAt: DateTime.now().toUtc()));
          summaries.add('Cut circular profile ${profile.id}');
        case 'revolve':
          final profile =
              _profile(sketch, p['profileId'], SketchEntityKind.rectangle);
          final angle = _positiveNumber(p['angle'], 'angle');
          if (angle != 360) {
            throw const FormatException(
              'CadPilot currently supports only a full 360 degree revolve.',
            );
          }
          next = next.add(ModelOperation(
              id: operation.operationId,
              kind: ModelOperationKind.revolve,
              profileId: profile.id,
              depth: angle,
              createdAt: DateTime.now().toUtc()));
          summaries.add('Revolve ${profile.id} through 360 degrees');
        case 'rename':
          final id = p['operationId'];
          final name = p['name'];
          if (id is! String || name is! String || name.trim().isEmpty) {
            throw const FormatException(
                'Rename requires an operationId and name.');
          }
          final target = _operation(next, id);
          next = next.replace(target.copyWith(name: name.trim()));
          summaries.add('Rename ${target.displayName} to ${name.trim()}');
        case 'delete':
          final id = p['operationId'];
          if (id is! String) {
            throw const FormatException('Delete requires an operationId.');
          }
          final target = _operation(next, id);
          next = next.remove(id);
          summaries.add('Delete ${target.displayName}');
      }
    }
    if (next.operations.map((item) => item.id).toSet().length !=
        next.operations.length) {
      throw const FormatException('Operation IDs must be unique.');
    }
    return AiCommandPreview(
        command: command, model: next, summary: summaries.join('; '));
  }

  SketchEntity _profile(
      SketchDocument sketch, Object? id, SketchEntityKind kind) {
    if (id is! String) {
      throw const FormatException('A valid profileId is required.');
    }
    final matches =
        sketch.entities.where((item) => item.id == id && item.kind == kind);
    if (matches.isEmpty) {
      throw FormatException(
          'Profile $id does not exist or has the wrong type.');
    }
    return matches.first;
  }

  ModelOperation _operation(ModelDocument model, String id) {
    final matches = model.operations.where((item) => item.id == id);
    if (matches.isEmpty) {
      throw FormatException('Model operation $id does not exist.');
    }
    return matches.first;
  }

  double _positiveNumber(Object? value, String label) {
    if (value is! num || !value.isFinite || value <= 0 || value > 100000) {
      throw FormatException('$label must be between 0 and 100000 mm.');
    }
    return value.toDouble();
  }
}
