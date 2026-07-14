import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'model_3d.dart';
import 'sketch_models.dart';

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
  late ModelDocument model;
  double yaw = -0.65;
  double pitch = 0.45;
  double zoom = 1;
  Offset pan = Offset.zero;
  Offset? lastFocal;
  final evaluator = const ModelEvaluator();
  @override
  void initState() {
    super.initState();
    model = widget.model;
  }

  EvaluatedSolid? get solid => evaluator.evaluate(widget.sketch, model);

  Future<double?> depthDialog(String title, double initial) async {
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
                    decoration: const InputDecoration(labelText: 'Depth (mm)')),
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
    setState(() => model = model.add(ModelOperation(
        id: const Uuid().v4(),
        kind: ModelOperationKind.extrude,
        profileId: rectangles.first.id,
        depth: depth,
        createdAt: DateTime.now().toUtc())));
    widget.onChanged(model);
  }

  Future<void> cut() async {
    if (solid == null) {
      message('Create an extrusion first.');
      return;
    }
    final circles = widget.sketch.entities
        .where((item) => item.kind == SketchEntityKind.circle)
        .toList();
    if (circles.isEmpty) {
      message('Draw a circle in Sketch mode for the cut profile.');
      return;
    }
    setState(() => model = model.add(ModelOperation(
        id: const Uuid().v4(),
        kind: ModelOperationKind.circularCut,
        profileId: circles.first.id,
        depth: solid!.depth,
        createdAt: DateTime.now().toUtc())));
    widget.onChanged(model);
  }

  Future<void> exportStl() async {
    final current = solid;
    if (current == null) {
      message('Nothing to export yet.');
      return;
    }
    try {
      final content = const StlExporter().export(current,
          name: widget.projectName.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_'));
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
          '${directory.path}/${widget.projectName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.stl');
      await file.writeAsString(content, flush: true);
      message('STL saved to ${file.path}');
    } on UnsupportedError catch (error) {
      message(error.message ?? error.toString());
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
                            yaw: yaw,
                            pitch: pitch,
                            zoom: zoom,
                            pan: pan)),
                  )),
                  Positioned(
                      top: 16,
                      left: 16,
                      child: Row(children: [
                        FilledButton.icon(
                            onPressed: extrude,
                            icon: const Icon(Icons.unfold_more),
                            label: const Text('Extrude')),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                            onPressed: cut,
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('Through cut')),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                            onPressed: exportStl,
                            icon: const Icon(Icons.download),
                            label: const Text('Export STL'))
                      ])),
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
                                  : '${solid!.width.toStringAsFixed(1)} x ${solid!.height.toStringAsFixed(1)} x ${solid!.depth.toStringAsFixed(1)} mm | Volume ${solid!.volume.toStringAsFixed(1)} mm³')))),
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
                                              operation.kind ==
                                                      ModelOperationKind.extrude
                                                  ? Icons.view_in_ar
                                                  : Icons.remove_circle_outline,
                                              color: const Color(0xff29d3b2)),
                                          title: Text(operation.kind ==
                                                  ModelOperationKind.extrude
                                              ? 'Extrude ${index + 1}'
                                              : 'Cut ${index + 1}'),
                                          subtitle: Text(
                                              '${operation.depth.toStringAsFixed(1)} mm'),
                                          dense: true);
                                    }))
                        ])))),
      ]);
}

class SolidPainter extends CustomPainter {
  SolidPainter(
      {required this.solid,
      required this.yaw,
      required this.pitch,
      required this.zoom,
      required this.pan});
  final EvaluatedSolid? solid;
  final double yaw, pitch, zoom;
  final Offset pan;
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
    final v = <List<double>>[
      [-w, -h, 0],
      [w, -h, 0],
      [w, h, 0],
      [-w, h, 0],
      [-w, -h, d],
      [w, -h, d],
      [w, h, d],
      [-w, h, d]
    ];
    const faces = <List<int>>[
      [0, 1, 2, 3],
      [4, 7, 6, 5],
      [0, 4, 5, 1],
      [1, 5, 6, 2],
      [2, 6, 7, 3],
      [3, 7, 4, 0]
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
      fill.color = Color.lerp(const Color(0xff0c8877), const Color(0xff29d3b2),
              i / faces.length)!
          .withValues(alpha: 0.72);
      canvas.drawPath(path, fill);
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

  @override
  bool shouldRepaint(covariant SolidPainter oldDelegate) => true;
}
