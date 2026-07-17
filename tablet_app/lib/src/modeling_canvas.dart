import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'model_3d.dart';
import 'sketch_models.dart';
import 'stl_file_export.dart';

enum AssemblyViewMode { cad, assembled, exploded, render, labels }

class AssemblyPart {
  const AssemblyPart({
    required this.operation,
    required this.solid,
    required this.offset,
    required this.color,
  });
  final ModelOperation operation;
  final EvaluatedSolid solid;
  final Offset offset;
  final Color color;
}

class ModelingCanvas extends StatefulWidget {
  const ModelingCanvas(
      {required this.projectName,
      required this.sketch,
      required this.model,
      required this.onChanged,
      super.key});
  final String projectName;
  final SketchDocument sketch;
  final ModelDocument model;
  final ValueChanged<ModelDocument> onChanged;
  @override
  State<ModelingCanvas> createState() => _ModelingCanvasState();
}

class _ModelingCanvasState extends State<ModelingCanvas> {
  late ModelHistory history;
  ModelDocument get model => history.document;
  double yaw = -0.65;
  double pitch = 0.45;
  double zoom = 1;
  Offset pan = Offset.zero;
  Offset? lastFocal;
  final viewportKey = GlobalKey();
  int? selectedFace;
  int? selectedEdge;
  AssemblyViewMode assemblyMode = AssemblyViewMode.cad;
  final evaluator = const ModelEvaluator();
  @override
  void initState() {
    super.initState();
    history = ModelHistory(widget.model);
  }

  @override
  void didUpdateWidget(covariant ModelingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.model, oldWidget.model) &&
        !identical(widget.model, history.document)) {
      history = ModelHistory(widget.model);
      selectedFace = null;
      selectedEdge = null;
    }
  }

  EvaluatedSolid? get solid => evaluator.evaluate(widget.sketch, model);
  SolidMeasurements? get measurements =>
      solid == null ? null : SolidMeasurements.from(solid!, model.material);

  List<AssemblyPart> get assemblyParts {
    final parts = <AssemblyPart>[];
    for (final operation in model.operations) {
      if (operation.suppressed ||
          !{
            ModelOperationKind.extrude,
            ModelOperationKind.revolve,
            ModelOperationKind.gear,
          }.contains(operation.kind)) {
        continue;
      }
      final solid = evaluator.evaluate(
          widget.sketch, ModelDocument(operations: [operation]));
      if (solid == null) continue;
      parts.add(AssemblyPart(
          operation: operation,
          solid: solid,
          offset: _assemblyOffset(operation, parts.length),
          color: _partColor(operation.displayName)));
    }
    return parts;
  }

  Offset _assemblyOffset(ModelOperation operation, int index) {
    final name = operation.displayName.toLowerCase();
    if (name.contains('skid') || name.contains('base')) {
      return const Offset(0, 95);
    }
    if (name.contains('engine')) return const Offset(-150, 15);
    if (name.contains('alternator') || name.contains('generator head')) {
      return const Offset(105, 18);
    }
    if (name.contains('fuel')) return const Offset(-50, -120);
    if (name.contains('control')) return const Offset(260, -70);
    if (name.contains('muffler') || name.contains('exhaust')) {
      return const Offset(35, -178);
    }
    if (name.contains('battery')) return const Offset(-260, 55);
    return Offset((index - 2) * 120.0, index.isEven ? -40 : 60);
  }

  Color _partColor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('skid') || lower.contains('base')) {
      return const Color(0xff2f3d48);
    }
    if (lower.contains('engine')) return const Color(0xff4b5563);
    if (lower.contains('alternator') || lower.contains('generator head')) {
      return const Color(0xff2563eb);
    }
    if (lower.contains('fuel')) return const Color(0xffd97706);
    if (lower.contains('control')) return const Color(0xff111827);
    if (lower.contains('muffler') || lower.contains('exhaust')) {
      return const Color(0xffa3a3a3);
    }
    if (lower.contains('gear')) return const Color(0xff38bdf8);
    return const Color(0xff29d3b2);
  }

  void selectAt(TapUpDetails details) {
    if (assemblyMode != AssemblyViewMode.cad) return;
    final current = solid;
    final box = viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (current == null || box == null) return;
    final hit = SolidProjection(current,
            yaw: yaw, pitch: pitch, zoom: zoom, pan: pan, size: box.size)
        .hitTest(details.localPosition);
    setState(() {
      selectedFace = hit.face;
      selectedEdge = hit.edge;
    });
  }

  Future<double?> depthDialog(String title, double initial,
      {String label = 'Depth (mm)'}) async {
    final controller = TextEditingController(text: initial.toStringAsFixed(1));
    return showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: label)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        final value = double.tryParse(controller.text);
                        if (value != null && value > 0) {
                          Navigator.pop(context, value);
                        }
                      },
                      child: const Text('Apply'))
                ]));
  }

  void revolve() {
    final rectangles = widget.sketch.entities
        .where((item) => item.kind == SketchEntityKind.rectangle)
        .toList();
    if (rectangles.isEmpty) {
      message('Draw a rectangle in Sketch mode as the radial section first.');
      return;
    }
    final validation =
        const RevolveValidator().validate(rectangles.first, model);
    if (validation != null) {
      message(validation);
      return;
    }
    setState(() => history.add(ModelOperation(
        id: const Uuid().v4(),
        kind: ModelOperationKind.revolve,
        profileId: rectangles.first.id,
        depth: 360,
        createdAt: DateTime.now().toUtc())));
    widget.onChanged(history.document);
  }

  Future<void> extrude() async {
    final rectangles = widget.sketch.entities
        .where((item) => item.kind == SketchEntityKind.rectangle)
        .toList();
    if (rectangles.isEmpty) {
      message('Draw a rectangle in Sketch mode first.');
      return;
    }
    final depth = await depthDialog('Extrude rectangle', 20);
    if (depth == null) return;
    setState(() => history.add(ModelOperation(
        id: const Uuid().v4(),
        kind: ModelOperationKind.extrude,
        profileId: rectangles.first.id,
        depth: depth,
        createdAt: DateTime.now().toUtc())));
    widget.onChanged(history.document);
  }

  Future<void> cut() async {
    if (solid == null) {
      message('Create an extrusion first.');
      return;
    }
    if (solid!.shellThickness > 0) {
      message('Suppress or delete the shell before adding a through cut.');
      return;
    }
    final circles = widget.sketch.entities
        .where((item) => item.kind == SketchEntityKind.circle)
        .toList();
    if (circles.isEmpty) {
      message('Draw a circle in Sketch mode for the cut profile.');
      return;
    }
    if (solid!.revolved) {
      final validation = const RevolvedBoreValidator().validate(
        solid!,
        circles.first,
      );
      if (validation != null) {
        message(validation);
        return;
      }
    }
    setState(() => history.add(ModelOperation(
        id: const Uuid().v4(),
        kind: ModelOperationKind.circularCut,
        profileId: circles.first.id,
        depth: solid!.depth,
        createdAt: DateTime.now().toUtc())));
    widget.onChanged(history.document);
  }

  void booleanSubtract() {
    final current = solid;
    final baseProfileId = model.operations
        .where((item) => item.kind == ModelOperationKind.extrude)
        .firstOrNull
        ?.profileId;
    if (current == null || baseProfileId == null) {
      message('Create a rectangular extrusion first.');
      return;
    }
    final profiles = widget.sketch.entities
        .where((item) =>
            item.kind == SketchEntityKind.rectangle && item.id != baseProfileId)
        .toList();
    if (profiles.isEmpty) {
      message('Draw a second rectangle in Sketch mode for subtraction.');
      return;
    }
    final profile = profiles.firstWhere(
        (item) => !model.operations.any((operation) =>
            operation.kind == ModelOperationKind.booleanSubtract &&
            operation.profileId == item.id &&
            !operation.suppressed),
        orElse: () => profiles.first);
    final validation =
        const BooleanSubtractValidator().validate(current, profile);
    if (validation != null) {
      message(validation);
      return;
    }
    setState(() => history.add(ModelOperation(
        id: const Uuid().v4(),
        kind: ModelOperationKind.booleanSubtract,
        profileId: profile.id,
        depth: current.depth,
        createdAt: DateTime.now().toUtc())));
    widget.onChanged(history.document);
  }

  Future<void> shell() async {
    final current = solid;
    final baseOperation = model.operations
        .where((item) => item.kind == ModelOperationKind.extrude)
        .firstOrNull;
    if (current == null || baseOperation == null) {
      message('Create an extrusion first.');
      return;
    }
    final existing = model.operations
        .where((item) => item.kind == ModelOperationKind.shell)
        .firstOrNull;
    final thickness = await depthDialog(
        existing == null ? 'Shell solid' : 'Edit shell',
        existing?.depth ??
            math.min(math.min(current.width, current.height) / 2,
                    current.depth) *
                0.2,
        label: 'Wall thickness (mm)');
    if (thickness == null) return;
    final validation = const ShellValidator().validate(current, thickness);
    if (validation != null) {
      message(validation);
      return;
    }
    final operation = ModelOperation(
        id: existing?.id ?? const Uuid().v4(),
        kind: ModelOperationKind.shell,
        profileId: baseOperation.profileId,
        depth: thickness,
        createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
        name: existing?.name,
        suppressed: existing?.suppressed ?? false);
    setState(() =>
        existing == null ? history.add(operation) : history.replace(operation));
    widget.onChanged(history.document);
  }

  Future<void> fillet() async {
    final current = solid;
    final baseOperation = model.operations
        .where((item) => item.kind == ModelOperationKind.extrude)
        .firstOrNull;
    if (current == null || baseOperation == null) {
      message('Create an extrusion first.');
      return;
    }
    final existing = model.operations
        .where((item) => item.kind == ModelOperationKind.fillet)
        .firstOrNull;
    final radius = await depthDialog(
        existing == null ? 'Fillet solid corners' : 'Edit fillet',
        existing?.depth ?? math.min(current.width, current.height) * 0.1,
        label: 'Radius (mm)');
    if (radius == null) return;
    final validation = const FilletValidator().validate(current, radius);
    if (validation != null) {
      message(validation);
      return;
    }
    final operation = ModelOperation(
        id: existing?.id ?? const Uuid().v4(),
        kind: ModelOperationKind.fillet,
        profileId: baseOperation.profileId,
        depth: radius,
        createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
        name: existing?.name,
        suppressed: existing?.suppressed ?? false);
    setState(() =>
        existing == null ? history.add(operation) : history.replace(operation));
    widget.onChanged(history.document);
  }

  Future<void> chamfer() async {
    final current = solid;
    final baseOperation = model.operations
        .where((item) => item.kind == ModelOperationKind.extrude)
        .firstOrNull;
    if (current == null || baseOperation == null) {
      message('Create an extrusion first.');
      return;
    }
    final existing = model.operations
        .where((item) => item.kind == ModelOperationKind.chamfer)
        .firstOrNull;
    final distance = await depthDialog(
        existing == null ? 'Chamfer solid corners' : 'Edit chamfer',
        existing?.depth ?? math.min(current.width, current.height) * 0.08,
        label: 'Distance (mm)');
    if (distance == null) return;
    final validation = const ChamferValidator().validate(current, distance);
    if (validation != null) {
      message(validation);
      return;
    }
    final operation = ModelOperation(
        id: existing?.id ?? const Uuid().v4(),
        kind: ModelOperationKind.chamfer,
        profileId: baseOperation.profileId,
        depth: distance,
        createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
        name: existing?.name,
        suppressed: existing?.suppressed ?? false);
    setState(() =>
        existing == null ? history.add(operation) : history.replace(operation));
    widget.onChanged(history.document);
  }

  Future<({int count, double spacing})?> patternDialog(
      {int count = 3, double spacing = 20}) async {
    final countController = TextEditingController(text: count.toString());
    final spacingController =
        TextEditingController(text: spacing.toStringAsFixed(1));
    return showDialog<({int count, double spacing})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Linear cut pattern'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: countController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total instances')),
          const SizedBox(height: 12),
          TextField(
              controller: spacingController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'X spacing (mm)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                final parsedCount = int.tryParse(countController.text);
                final parsedSpacing = double.tryParse(spacingController.text);
                if (parsedCount != null &&
                    parsedCount >= 2 &&
                    parsedCount <= 50 &&
                    parsedSpacing != null &&
                    parsedSpacing > 0) {
                  Navigator.pop(
                      context, (count: parsedCount, spacing: parsedSpacing));
                }
              },
              child: const Text('Apply')),
        ],
      ),
    );
  }

  Future<void> patternCut(ModelOperation source,
      {ModelOperation? existing}) async {
    final current = solid;
    final profile = widget.sketch.entities
        .where((item) => item.id == source.profileId)
        .firstOrNull;
    if (current == null ||
        profile == null ||
        profile.kind != SketchEntityKind.circle) {
      message('The source circular cut is no longer valid.');
      return;
    }
    final parameters = await patternDialog(
        count: existing?.instanceCount ?? 3,
        spacing: existing?.spacing ?? profile.primaryDimension * 3);
    if (parameters == null) return;
    final validation = const LinearPatternValidator().validate(current, profile,
        count: parameters.count, spacing: parameters.spacing);
    if (validation != null) {
      message(validation);
      return;
    }
    final operation = ModelOperation(
        id: existing?.id ?? const Uuid().v4(),
        kind: ModelOperationKind.linearPattern,
        profileId: source.profileId,
        depth: current.depth,
        createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
        name: existing?.name,
        suppressed: existing?.suppressed ?? false,
        sourceOperationId: source.id,
        instanceCount: parameters.count,
        spacing: parameters.spacing);
    setState(() =>
        existing == null ? history.add(operation) : history.replace(operation));
    widget.onChanged(history.document);
  }

  Future<int?> circularPatternDialog({int count = 4}) async {
    final controller = TextEditingController(text: count.toString());
    return showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Circular cut pattern'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Total instances')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        final value = int.tryParse(controller.text);
                        if (value != null && value >= 2 && value <= 50) {
                          Navigator.pop(context, value);
                        }
                      },
                      child: const Text('Apply'))
                ]));
  }

  Future<void> circularPatternCut(ModelOperation source,
      {ModelOperation? existing}) async {
    final current = solid;
    final profile = widget.sketch.entities
        .where((item) => item.id == source.profileId)
        .firstOrNull;
    if (current == null ||
        profile == null ||
        profile.kind != SketchEntityKind.circle) {
      message('The source circular cut is no longer valid.');
      return;
    }
    final count =
        await circularPatternDialog(count: existing?.instanceCount ?? 4);
    if (count == null) return;
    final validation = const CircularPatternValidator()
        .validate(current, profile, count: count);
    if (validation != null) {
      message(validation);
      return;
    }
    final operation = ModelOperation(
        id: existing?.id ?? const Uuid().v4(),
        kind: ModelOperationKind.circularPattern,
        profileId: source.profileId,
        depth: current.depth,
        createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
        name: existing?.name,
        suppressed: existing?.suppressed ?? false,
        sourceOperationId: source.id,
        instanceCount: count,
        spacing: 360 / count);
    setState(() =>
        existing == null ? history.add(operation) : history.replace(operation));
    widget.onChanged(history.document);
  }

  void mirrorCut(ModelOperation source) {
    final current = solid;
    final profile = widget.sketch.entities
        .where((item) => item.id == source.profileId)
        .firstOrNull;
    if (current == null || profile == null) {
      message('The source circular cut is no longer valid.');
      return;
    }
    final validation = const MirrorCutValidator().validate(current, profile);
    if (validation != null) {
      message(validation);
      return;
    }
    history.add(ModelOperation(
        id: const Uuid().v4(),
        kind: ModelOperationKind.mirrorCut,
        profileId: source.profileId,
        depth: current.depth,
        createdAt: DateTime.now().toUtc(),
        sourceOperationId: source.id));
    setState(() {});
    widget.onChanged(history.document);
  }

  void assignMaterial(CadMaterial material) {
    setState(() => history.commit(model.copyWith(material: material)));
    widget.onChanged(history.document);
  }

  void undo() {
    setState(history.undo);
    widget.onChanged(history.document);
  }

  void redo() {
    setState(history.redo);
    widget.onChanged(history.document);
  }

  Future<void> editOperation(ModelOperation operation) async {
    if (operation.kind == ModelOperationKind.shell) {
      await shell();
      return;
    }
    if (operation.kind == ModelOperationKind.fillet) {
      await fillet();
      return;
    }
    if (operation.kind == ModelOperationKind.chamfer) {
      await chamfer();
      return;
    }
    if (operation.kind == ModelOperationKind.circularPattern) {
      final source = model.operations
          .where((item) => item.id == operation.sourceOperationId)
          .firstOrNull;
      if (source == null) {
        message('The pattern source no longer exists.');
        return;
      }
      await circularPatternCut(source, existing: operation);
      return;
    }
    if (operation.kind == ModelOperationKind.linearPattern) {
      final source = model.operations
          .where((item) => item.id == operation.sourceOperationId)
          .firstOrNull;
      if (source == null) {
        message('The pattern source no longer exists.');
        return;
      }
      await patternCut(source, existing: operation);
      return;
    }
    final depth =
        await depthDialog('Edit ${operation.displayName}', operation.depth);
    if (depth == null) return;
    setState(() => history.replace(operation.copyWith(depth: depth)));
    widget.onChanged(history.document);
  }

  Future<void> renameOperation(ModelOperation operation) async {
    final controller = TextEditingController(text: operation.displayName);
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Rename feature'),
              content: TextField(controller: controller, autofocus: true),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Rename'))
              ],
            ));
    if (value == null || value.isEmpty) return;
    setState(() => history.replace(operation.copyWith(name: value)));
    widget.onChanged(history.document);
  }

  void suppressOperation(ModelOperation operation) {
    setState(() =>
        history.replace(operation.copyWith(suppressed: !operation.suppressed)));
    widget.onChanged(history.document);
  }

  void deleteOperation(ModelOperation operation) {
    setState(() => history.remove(operation.id));
    widget.onChanged(history.document);
  }

  Future<int?> exportQuality() async {
    var targetCells = 56;
    return showDialog<int>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('STL export quality'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                selected: targetCells == 32,
                leading: Icon(targetCells == 32
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: const Text('Draft'),
                subtitle: const Text('Fast export for previewing'),
                onTap: () => setDialogState(() => targetCells = 32),
              ),
              ListTile(
                selected: targetCells == 56,
                leading: Icon(targetCells == 56
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: const Text('Standard'),
                subtitle: const Text('Balanced detail and file size'),
                onTap: () => setDialogState(() => targetCells = 56),
              ),
              ListTile(
                selected: targetCells == 96,
                leading: Icon(targetCells == 96
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: const Text('Fine'),
                subtitle: const Text('Higher detail for manufacturing'),
                onTap: () => setDialogState(() => targetCells = 96),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, targetCells),
              child: const Text('Export STL'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> exportStl() async {
    final current = solid;
    if (current == null) {
      message('Nothing to export yet.');
      return;
    }
    final targetCells = await exportQuality();
    if (targetCells == null || !mounted) return;
    try {
      final mesher = SolidMesher(targetCells: targetCells);
      final mesh = mesher.tessellate(current);
      final content = StlExporter(mesher: mesher).export(current,
          name: widget.projectName.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_'));
      final fileName =
          '${widget.projectName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.stl';
      final exportMessage = await exportStlFile(
        content: content,
        fileName: fileName,
      );
      message(
        '$exportMessage (mesh tolerance ${mesh.tolerance.toStringAsFixed(2)} mm)',
      );
    } on StateError catch (error) {
      message(error.message);
    }
  }

  void message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: ColoredBox(
                color: const Color(0xff071017),
                child: Stack(children: [
                  Positioned.fill(
                      child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: selectAt,
                    onScaleStart: (details) => lastFocal = details.focalPoint,
                    onScaleUpdate: (details) {
                      final delta = details.focalPoint -
                          (lastFocal ?? details.focalPoint);
                      setState(() {
                        zoom = (zoom * details.scale).clamp(0.35, 5.0);
                        if (details.pointerCount == 1) {
                          yaw += delta.dx * 0.01;
                          pitch = (pitch - delta.dy * 0.01).clamp(-1.2, 1.2);
                        } else {
                          pan += delta;
                        }
                        lastFocal = details.focalPoint;
                      });
                    },
                    onScaleEnd: (_) => lastFocal = null,
                    child: CustomPaint(
                        painter: SolidPainter(
                            solid: solid,
                            parts: assemblyParts,
                            assemblyMode: assemblyMode,
                            yaw: yaw,
                            pitch: pitch,
                            zoom: zoom,
                            pan: pan,
                            selectedFace: selectedFace,
                            selectedEdge: selectedEdge)),
                  )),
                  Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            FilledButton.icon(
                                onPressed: extrude,
                                icon: const Icon(Icons.unfold_more),
                                label: const Text('Extrude')),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                                onPressed: revolve,
                                icon: const Icon(Icons.rotate_right),
                                label: const Text('Revolve')),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                                onPressed: cut,
                                icon: const Icon(Icons.remove_circle_outline),
                                label: const Text('Through cut')),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                                onPressed: booleanSubtract,
                                icon: const Icon(Icons.indeterminate_check_box),
                                label: const Text('Boolean cut')),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                                onPressed: shell,
                                icon: const Icon(Icons.crop_square),
                                label: const Text('Shell')),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                                onPressed: fillet,
                                icon: const Icon(Icons.rounded_corner),
                                label: const Text('Fillet')),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                                onPressed: chamfer,
                                icon: const Icon(Icons.architecture),
                                label: const Text('Chamfer')),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                                tooltip: 'Undo 3D operation',
                                onPressed: history.canUndo ? undo : null,
                                icon: const Icon(Icons.undo)),
                            const SizedBox(width: 6),
                            IconButton.filledTonal(
                                tooltip: 'Redo 3D operation',
                                onPressed: history.canRedo ? redo : null,
                                icon: const Icon(Icons.redo)),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                                onPressed: exportStl,
                                icon: const Icon(Icons.download),
                                label: const Text('Export STL')),
                            const SizedBox(width: 8),
                            SegmentedButton<AssemblyViewMode>(
                                segments: const [
                                  ButtonSegment(
                                      value: AssemblyViewMode.cad,
                                      icon: Icon(Icons.view_in_ar),
                                      label: Text('CAD')),
                                  ButtonSegment(
                                      value: AssemblyViewMode.assembled,
                                      icon: Icon(Icons.all_inbox),
                                      label: Text('Assemble')),
                                  ButtonSegment(
                                      value: AssemblyViewMode.exploded,
                                      icon: Icon(Icons.open_in_full),
                                      label: Text('Take apart')),
                                  ButtonSegment(
                                      value: AssemblyViewMode.render,
                                      icon: Icon(Icons.photo_camera),
                                      label: Text('Render')),
                                  ButtonSegment(
                                      value: AssemblyViewMode.labels,
                                      icon: Icon(Icons.label_outline),
                                      label: Text('Labels')),
                                ],
                                selected: {
                                  assemblyMode
                                },
                                onSelectionChanged: (value) =>
                                    setState(() => assemblyMode = value.first))
                          ]))),
                  Positioned(
                      left: 18,
                      bottom: 16,
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: const Color(0xdd121b25),
                              borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(solid == null
                                  ? 'No solid | Extrude a rectangle profile'
                                  : assemblyMode == AssemblyViewMode.cad
                                      ? '${solid!.width.toStringAsFixed(1)} x ${solid!.height.toStringAsFixed(1)} x ${solid!.depth.toStringAsFixed(1)} mm^3'
                                      : '${assemblyParts.length} assembly parts | ${assemblyMode.name} view')))),
                ]))),
        SizedBox(
            width: 250,
            child: ColoredBox(
                color: const Color(0xff0e1821),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('MATERIAL',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<CadMaterial>(
                            key: ValueKey(model.material),
                            initialValue: model.material,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                isDense: true, prefixIcon: Icon(Icons.layers)),
                            items: CadMaterial.values
                                .map((material) => DropdownMenuItem(
                                    value: material,
                                    child: Text(material.label)))
                                .toList(),
                            onChanged: (material) {
                              if (material != null &&
                                  material != model.material) {
                                assignMaterial(material);
                              }
                            },
                          ),
                          const SizedBox(height: 18),
                          const Text('MODEL TREE',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          if (model.operations.isEmpty)
                            const Text('No 3D operations')
                          else
                            Expanded(
                                child: ListView.builder(
                                    itemCount: model.operations.length,
                                    itemBuilder: (context, index) {
                                      final operation = model.operations[index];
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                            switch (operation.kind) {
                                              ModelOperationKind.extrude =>
                                                Icons.view_in_ar,
                                              ModelOperationKind.circularCut =>
                                                Icons.remove_circle_outline,
                                              ModelOperationKind
                                                    .booleanSubtract =>
                                                Icons.indeterminate_check_box,
                                              ModelOperationKind
                                                    .linearPattern =>
                                                Icons.grid_view,
                                              ModelOperationKind
                                                    .circularPattern =>
                                                Icons.blur_circular,
                                              ModelOperationKind.mirrorCut =>
                                                Icons.flip,
                                              ModelOperationKind.chamfer =>
                                                Icons.architecture,
                                              ModelOperationKind.fillet =>
                                                Icons.rounded_corner,
                                              ModelOperationKind.shell =>
                                                Icons.crop_square,
                                              ModelOperationKind.revolve =>
                                                Icons.rotate_right,
                                              ModelOperationKind.gear =>
                                                Icons.settings,
                                            },
                                            color: operation.suppressed
                                                ? Colors.grey
                                                : const Color(0xff29d3b2)),
                                        title: Text(operation.displayName),
                                        subtitle: Text(operation.suppressed
                                            ? 'Suppressed'
                                            : switch (operation.kind) {
                                                ModelOperationKind
                                                      .linearPattern =>
                                                  '${operation.instanceCount} x ${operation.spacing.toStringAsFixed(1)} mm',
                                                ModelOperationKind
                                                      .circularPattern =>
                                                  '${operation.instanceCount} around 360 deg',
                                                ModelOperationKind.mirrorCut =>
                                                  'Vertical center plane',
                                                ModelOperationKind.revolve =>
                                                  '360 deg full revolution',
                                                ModelOperationKind.gear =>
                                                  '${operation.instanceCount} teeth · bore ${operation.spacing.toStringAsFixed(1)} mm',
                                                _ =>
                                                  '${operation.depth.toStringAsFixed(1)} mm',
                                              }),
                                        enabled: !operation.suppressed,
                                        trailing: PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              editOperation(operation);
                                            }
                                            if (value == 'pattern') {
                                              patternCut(operation);
                                            }
                                            if (value == 'circularPattern') {
                                              circularPatternCut(operation);
                                            }
                                            if (value == 'mirror') {
                                              mirrorCut(operation);
                                            }
                                            if (value == 'rename') {
                                              renameOperation(operation);
                                            }
                                            if (value == 'suppress') {
                                              suppressOperation(operation);
                                            }
                                            if (value == 'delete') {
                                              deleteOperation(operation);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            if (operation.kind !=
                                                    ModelOperationKind
                                                        .mirrorCut &&
                                                operation.kind !=
                                                    ModelOperationKind
                                                        .revolve &&
                                                operation.kind !=
                                                    ModelOperationKind
                                                        .booleanSubtract)
                                              PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text(operation.kind ==
                                                          ModelOperationKind
                                                              .linearPattern
                                                      ? 'Edit pattern'
                                                      : operation.kind ==
                                                              ModelOperationKind
                                                                  .circularPattern
                                                          ? 'Edit circular pattern'
                                                          : operation.kind ==
                                                                  ModelOperationKind
                                                                      .chamfer
                                                              ? 'Edit chamfer'
                                                              : operation.kind ==
                                                                      ModelOperationKind
                                                                          .fillet
                                                                  ? 'Edit fillet'
                                                                  : operation.kind ==
                                                                          ModelOperationKind
                                                                              .shell
                                                                      ? 'Edit shell'
                                                                      : 'Edit depth')),
                                            if (operation.kind ==
                                                ModelOperationKind
                                                    .circularCut) ...[
                                              const PopupMenuItem(
                                                  value: 'pattern',
                                                  child:
                                                      Text('Linear pattern')),
                                              const PopupMenuItem(
                                                  value: 'circularPattern',
                                                  child:
                                                      Text('Circular pattern')),
                                              const PopupMenuItem(
                                                  value: 'mirror',
                                                  child: Text('Mirror cut')),
                                            ],
                                            const PopupMenuItem(
                                                value: 'rename',
                                                child: Text('Rename')),
                                            PopupMenuItem(
                                                value: 'suppress',
                                                child: Text(operation.suppressed
                                                    ? 'Unsuppress'
                                                    : 'Suppress')),
                                            const PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete')),
                                          ],
                                        ),
                                        dense: true,
                                      );
                                    })),
                          const Divider(),
                          const Text('MEASUREMENTS',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 8),
                          if (measurements == null)
                            const Text(
                                'Create a solid to inspect its properties.')
                          else ...[
                            Text(
                                'Size  ${solid!.width.toStringAsFixed(1)} x ${solid!.height.toStringAsFixed(1)} x ${solid!.depth.toStringAsFixed(1)} mm'),
                            Text(
                                'Volume  ${measurements!.volumeMm3.toStringAsFixed(1)} mm^3'),
                            Text(
                                'Surface  ${measurements!.surfaceAreaMm2.toStringAsFixed(1)} mm^2'),
                            Text(measurements!.massGrams == null
                                ? 'Mass  Assign a physical material'
                                : 'Mass  ${measurements!.massGrams!.toStringAsFixed(2)} g'),
                          ]
                        ])))),
      ]);
}

class SolidPainter extends CustomPainter {
  SolidPainter(
      {required this.solid,
      required this.parts,
      required this.assemblyMode,
      required this.yaw,
      required this.pitch,
      required this.zoom,
      required this.pan,
      required this.selectedFace,
      required this.selectedEdge});
  final EvaluatedSolid? solid;
  final List<AssemblyPart> parts;
  final AssemblyViewMode assemblyMode;
  final double yaw, pitch, zoom;
  final Offset pan;
  final int? selectedFace;
  final int? selectedEdge;
  Offset project(List<double> point, Size size, double scale) {
    final x = point[0], y = point[1], z = point[2];
    final x1 = x * math.cos(yaw) - y * math.sin(yaw),
        y1 = x * math.sin(yaw) + y * math.cos(yaw);
    final y2 = y1 * math.cos(pitch) - z * math.sin(pitch),
        z2 = y1 * math.sin(pitch) + z * math.cos(pitch);
    return Offset(size.width / 2 + x1 * scale + pan.dx,
        size.height / 2 + (y2 - z2 * 0.18) * scale + pan.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final current = solid;
    if (assemblyMode != AssemblyViewMode.cad && parts.isNotEmpty) {
      _paintAssembly(canvas, size);
      return;
    }
    if (current == null) {
      final text = TextPainter(
          text: const TextSpan(
              text: '3D MODELING',
              style: TextStyle(
                  color: Color(0xff506a78),
                  fontSize: 30,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr)
        ..layout();
      text.paint(
          canvas,
          Offset(
              (size.width - text.width) / 2, (size.height - text.height) / 2));
      return;
    }
    final scale = (math.min(size.width / (current.width + current.depth),
                size.height / (current.height + current.depth)) *
            0.55 *
            zoom)
        .clamp(0.2, 20.0);
    final w = current.width / 2, h = current.height / 2, d = current.depth;
    final plan = <List<double>>[];
    if (current.gearTeeth > 0) {
      final segments = current.gearTeeth.clamp(6, 80) * 4;
      final outerRadius = current.width / 2;
      final rootRadius = current.gearRootRadius <= 0
          ? outerRadius * 0.82
          : current.gearRootRadius;
      for (var index = 0; index < segments; index++) {
        final toothPhase = index % 4;
        final radius =
            toothPhase == 1 || toothPhase == 2 ? outerRadius : rootRadius;
        final angle = index * math.pi * 2 / segments;
        plan.add([math.cos(angle) * radius, math.sin(angle) * radius, 0]);
      }
    } else if (current.revolved) {
      const segments = 48;
      for (var index = 0; index < segments; index++) {
        final angle = index * math.pi * 2 / segments;
        plan.add([math.cos(angle) * w, math.sin(angle) * h, 0]);
      }
    } else if (current.cornerRadius > 0) {
      const segments = 8;
      final r = current.cornerRadius;
      final centers = <Offset>[
        Offset(-w + r, -h + r),
        Offset(w - r, -h + r),
        Offset(w - r, h - r),
        Offset(-w + r, h - r),
      ];
      const starts = [-math.pi, -math.pi / 2, 0.0, math.pi / 2];
      for (var corner = 0; corner < 4; corner++) {
        for (var step = 0; step <= segments; step++) {
          final angle = starts[corner] + step * math.pi / 2 / segments;
          plan.add([
            centers[corner].dx + math.cos(angle) * r,
            centers[corner].dy + math.sin(angle) * r,
            0
          ]);
        }
      }
    } else if (current.chamfer > 0) {
      final c = current.chamfer;
      plan.addAll([
        [-w + c, -h, 0],
        [w - c, -h, 0],
        [w, -h + c, 0],
        [w, h - c, 0],
        [w - c, h, 0],
        [-w + c, h, 0],
        [-w, h - c, 0],
        [-w, -h + c, 0],
      ]);
    } else {
      plan.addAll([
        [-w, -h, 0],
        [w, -h, 0],
        [w, h, 0],
        [-w, h, 0],
      ]);
    }
    final v = <List<double>>[
      ...plan,
      ...plan.map((point) => [point[0], point[1], d]),
    ];
    final count = plan.length;
    final faces = <List<int>>[
      List.generate(count, (index) => index),
      List.generate(count, (index) => count * 2 - 1 - index),
      for (var index = 0; index < count; index++)
        [
          index,
          (index + 1) % count,
          count + (index + 1) % count,
          count + index
        ],
    ];
    final fill = Paint()..style = PaintingStyle.fill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xff9af4e0);
    for (var i = 0; i < faces.length; i++) {
      final path = Path();
      for (var j = 0; j < faces[i].length; j++) {
        final p = project(v[faces[i][j]], size, scale);
        if (j == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      fill.color = i == selectedFace
          ? const Color(0xffffbf69)
          : Color.lerp(const Color(0xff0c8877), const Color(0xff29d3b2),
                  i / faces.length)!
              .withValues(alpha: 0.72);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
      if (selectedEdge != null &&
          current.chamfer == 0 &&
          current.cornerRadius == 0) {
        final pair = SolidProjection.edgePairs[selectedEdge!];
        canvas.drawLine(
            project(v[pair[0]], size, scale),
            project(v[pair[1]], size, scale),
            Paint()
              ..color = const Color(0xffff784f)
              ..strokeWidth = 5);
      }
    }
    if (current.shellThickness > 0) {
      final t = current.shellThickness;
      final cavityTop = <List<double>>[
        [-w + t, -h + t, d],
        [w - t, -h + t, d],
        [w - t, h - t, d],
        [-w + t, h - t, d],
      ];
      final cavityBottom =
          cavityTop.map((point) => [point[0], point[1], t]).toList();
      Path polygon(List<List<double>> points) {
        final path = Path();
        for (var index = 0; index < points.length; index++) {
          final point = project(points[index], size, scale);
          index == 0
              ? path.moveTo(point.dx, point.dy)
              : path.lineTo(point.dx, point.dy);
        }
        return path..close();
      }

      canvas.drawPath(
          polygon(cavityTop),
          Paint()
            ..color = const Color(0xff071017)
            ..style = PaintingStyle.fill);
      canvas.drawPath(
          polygon(cavityBottom),
          Paint()
            ..color = const Color(0xff0b3f3a)
            ..style = PaintingStyle.fill);
      canvas.drawPath(polygon(cavityTop), edge);
      canvas.drawPath(polygon(cavityBottom), edge);
    }
    for (final cut in current.rectangularCuts) {
      final relative = cut.bounds.shift(
          -current.origin - Offset(current.width / 2, current.height / 2));
      final points = <List<double>>[
        [relative.left, relative.top, d],
        [relative.right, relative.top, d],
        [relative.right, relative.bottom, d],
        [relative.left, relative.bottom, d],
      ];
      final path = Path();
      for (var index = 0; index < points.length; index++) {
        final point = project(points[index], size, scale);
        index == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff071017)
            ..style = PaintingStyle.fill);
      canvas.drawPath(path, edge);
    }
    for (final cut in current.cuts) {
      final relative = Offset(
          cut.center.dx - current.origin.dx - current.width / 2,
          cut.center.dy - current.origin.dy - current.height / 2);
      final center = project([relative.dx, relative.dy, d], size, scale);
      canvas.drawCircle(
          center,
          cut.radius * scale,
          Paint()
            ..color = const Color(0xff071017)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(center, cut.radius * scale, edge);
    }
  }

  void _paintAssembly(Canvas canvas, Size size) {
    final maxWidth = parts
        .map((part) => part.offset.dx.abs() + part.solid.width)
        .fold<double>(400, math.max);
    final maxHeight = parts
        .map((part) =>
            part.offset.dy.abs() + part.solid.height + part.solid.depth)
        .fold<double>(260, math.max);
    final scale = (math.min(size.width / (maxWidth * 2.2),
                size.height / (maxHeight * 1.9)) *
            zoom)
        .clamp(0.18, 4.0);
    final sorted = [...parts]..sort((a, b) =>
        (a.offset.dy + a.solid.depth).compareTo(b.offset.dy + b.solid.depth));
    for (var index = 0; index < sorted.length; index += 1) {
      final part = sorted[index];
      final explode = assemblyMode == AssemblyViewMode.exploded ||
          assemblyMode == AssemblyViewMode.labels;
      final vector = part.offset == Offset.zero
          ? Offset((index - sorted.length / 2) * 34, index.isEven ? -24 : 24)
          : part.offset;
      final offset = explode ? vector * 1.75 : vector;
      final realistic = assemblyMode == AssemblyViewMode.render ||
          assemblyMode == AssemblyViewMode.labels;
      _drawPart(canvas, size, part, offset, scale, realistic: realistic);
      if (assemblyMode == AssemblyViewMode.labels) {
        _drawPartLabel(canvas, size, part, offset, scale, index + 1);
      }
    }
    if (assemblyMode == AssemblyViewMode.render) {
      _drawRenderTitle(canvas, size);
    }
  }

  List<List<double>> _planPoints(EvaluatedSolid current) {
    final w = current.width / 2, h = current.height / 2;
    final plan = <List<double>>[];
    if (current.gearTeeth > 0) {
      final segments = current.gearTeeth.clamp(6, 80) * 4;
      final outerRadius = current.width / 2;
      final rootRadius = current.gearRootRadius <= 0
          ? outerRadius * 0.82
          : current.gearRootRadius;
      for (var index = 0; index < segments; index++) {
        final toothPhase = index % 4;
        final radius =
            toothPhase == 1 || toothPhase == 2 ? outerRadius : rootRadius;
        final angle = index * math.pi * 2 / segments;
        plan.add([math.cos(angle) * radius, math.sin(angle) * radius, 0]);
      }
    } else if (current.revolved) {
      const segments = 48;
      for (var index = 0; index < segments; index++) {
        final angle = index * math.pi * 2 / segments;
        plan.add([math.cos(angle) * w, math.sin(angle) * h, 0]);
      }
    } else {
      plan.addAll([
        [-w, -h, 0],
        [w, -h, 0],
        [w, h, 0],
        [-w, h, 0],
      ]);
    }
    return plan;
  }

  void _drawPart(
      Canvas canvas, Size size, AssemblyPart part, Offset offset, double scale,
      {required bool realistic}) {
    final current = part.solid;
    final plan = _planPoints(current);
    final d = current.depth;
    final v = <List<double>>[
      ...plan.map((point) => [point[0] + offset.dx, point[1] + offset.dy, 0]),
      ...plan.map((point) => [point[0] + offset.dx, point[1] + offset.dy, d]),
    ];
    final count = plan.length;
    final faces = <List<int>>[
      List.generate(count, (index) => index),
      List.generate(count, (index) => count * 2 - 1 - index),
      for (var index = 0; index < count; index++)
        [
          index,
          (index + 1) % count,
          count + (index + 1) % count,
          count + index
        ],
    ];
    final fill = Paint()..style = PaintingStyle.fill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = realistic ? 1.2 : 1.5
      ..color = realistic ? const Color(0xffe5e7eb) : const Color(0xff9af4e0);
    for (var i = 0; i < faces.length; i++) {
      final path = Path();
      for (var j = 0; j < faces[i].length; j++) {
        final p = project(v[faces[i][j]], size, scale);
        j == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      final shade = 0.68 + (i / faces.length) * 0.28;
      fill.color = Color.lerp(Colors.black, part.color, shade)!
          .withValues(alpha: realistic ? 0.92 : 0.75);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
    }
    if (realistic &&
        (part.operation.displayName.toLowerCase().contains('fuel') ||
            part.operation.displayName.toLowerCase().contains('control'))) {
      final center = project([offset.dx, offset.dy, d + 8], size, scale);
      final text = TextPainter(
          text: const TextSpan(
              text: 'CadPilot',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr)
        ..layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    }
  }

  void _drawPartLabel(Canvas canvas, Size size, AssemblyPart part,
      Offset offset, double scale, int number) {
    final anchor =
        project([offset.dx, offset.dy, part.solid.depth + 20], size, scale);
    final labelOffset =
        Offset(anchor.dx + (offset.dx >= 0 ? 42 : -210), anchor.dy - 26);
    final paint = Paint()
      ..color = const Color(0xff8cf5df)
      ..strokeWidth = 1.4;
    canvas.drawLine(anchor, labelOffset + const Offset(18, 18), paint);
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(labelOffset.dx, labelOffset.dy, 190, 42),
        const Radius.circular(8));
    canvas.drawRRect(
        rect,
        Paint()
          ..color = const Color(0xdd0b1520)
          ..style = PaintingStyle.fill);
    canvas.drawRRect(rect, paint..style = PaintingStyle.stroke);
    final text = TextPainter(
        text: TextSpan(
            text: '$number. ${part.operation.displayName}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        maxLines: 2,
        ellipsis: '…',
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: 166);
    text.paint(canvas, labelOffset + const Offset(12, 8));
  }

  void _drawRenderTitle(Canvas canvas, Size size) {
    final title = TextPainter(
        text: const TextSpan(
            text: 'Real-life hardware render preview',
            style: TextStyle(
                color: Color(0xffdffdf7),
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr)
      ..layout();
    title.paint(canvas, Offset(24, size.height - 54));
    final subtitle = TextPainter(
        text: const TextSpan(
            text:
                'Colored parts and logo are visual guidance; CAD remains editable.',
            style: TextStyle(color: Color(0xff9fb8c7), fontSize: 12)),
        textDirection: TextDirection.ltr)
      ..layout();
    subtitle.paint(canvas, Offset(24, size.height - 30));
  }

  @override
  bool shouldRepaint(covariant SolidPainter oldDelegate) => true;
}

class SolidHit {
  const SolidHit({this.face, this.edge});
  final int? face;
  final int? edge;
}

class SolidProjection {
  SolidProjection(this.solid,
      {required this.yaw,
      required this.pitch,
      required this.zoom,
      required this.pan,
      required this.size});
  final EvaluatedSolid solid;
  final double yaw, pitch, zoom;
  final Offset pan;
  final Size size;
  static const faces = <List<int>>[
    [0, 1, 2, 3],
    [4, 7, 6, 5],
    [0, 4, 5, 1],
    [1, 5, 6, 2],
    [2, 6, 7, 3],
    [3, 7, 4, 0]
  ];
  static const edgePairs = <List<int>>[
    [0, 1],
    [1, 2],
    [2, 3],
    [3, 0],
    [4, 5],
    [5, 6],
    [6, 7],
    [7, 4],
    [0, 4],
    [1, 5],
    [2, 6],
    [3, 7]
  ];
  List<Offset> get points {
    final w = solid.width / 2, h = solid.height / 2, d = solid.depth;
    final vertices = <List<double>>[
      [-w, -h, 0],
      [w, -h, 0],
      [w, h, 0],
      [-w, h, 0],
      [-w, -h, d],
      [w, -h, d],
      [w, h, d],
      [-w, h, d]
    ];
    final scale = (math.min(size.width / (solid.width + solid.depth),
                size.height / (solid.height + solid.depth)) *
            0.55 *
            zoom)
        .clamp(0.2, 20.0);
    return vertices.map((point) {
      final x1 = point[0] * math.cos(yaw) - point[1] * math.sin(yaw),
          y1 = point[0] * math.sin(yaw) + point[1] * math.cos(yaw);
      final y2 = y1 * math.cos(pitch) - point[2] * math.sin(pitch),
          z2 = y1 * math.sin(pitch) + point[2] * math.cos(pitch);
      return Offset(size.width / 2 + x1 * scale + pan.dx,
          size.height / 2 + (y2 - z2 * 0.18) * scale + pan.dy);
    }).toList();
  }

  SolidHit hitTest(Offset point) {
    final projected = points;
    var bestEdge = -1, bestDistance = 12.0;
    for (var index = 0; index < edgePairs.length; index++) {
      final pair = edgePairs[index];
      final distance =
          _segmentDistance(point, projected[pair[0]], projected[pair[1]]);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestEdge = index;
      }
    }
    if (bestEdge >= 0) return SolidHit(edge: bestEdge);
    for (var face = faces.length - 1; face >= 0; face--) {
      if (_inside(
          point, faces[face].map((index) => projected[index]).toList())) {
        return SolidHit(face: face);
      }
    }
    return const SolidHit();
  }

  double _segmentDistance(Offset p, Offset a, Offset b) {
    final length = (b - a).distanceSquared;
    if (length == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) /
            length)
        .clamp(0.0, 1.0);
    return (p - Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t))
        .distance;
  }

  bool _inside(Offset point, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if (((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx <
              (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
        inside = !inside;
      }
    }
    return inside;
  }
}
