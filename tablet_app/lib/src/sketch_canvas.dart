import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'sketch_models.dart';
import 'sketch_recognition.dart';

class SketchCanvas extends StatefulWidget {
  const SketchCanvas(
      {required this.document, required this.onChanged, super.key});
  final SketchDocument document;
  final ValueChanged<SketchDocument> onChanged;
  @override
  State<SketchCanvas> createState() => _SketchCanvasState();
}

class _SketchCanvasState extends State<SketchCanvas> {
  late SketchHistory history;
  SketchTool tool = SketchTool.select;
  Offset? pointerStart;
  Offset? pointerCurrent;
  Offset moveDelta = Offset.zero;
  Offset? hoverPoint;
  bool snapping = true;
  final roughPoints = <Offset>[];
  static const recognizer = RoughStrokeRecognizer();
  static const snapper = SketchSnapper();
  @override
  void initState() {
    super.initState();
    history = SketchHistory(widget.document);
  }

  void persist() => widget.onChanged(history.document);
  void choose(SketchTool next) => setState(() {
        tool = next;
        pointerStart = null;
        pointerCurrent = null;
        moveDelta = Offset.zero;
      });
  void down(PointerDownEvent event) {
    final point =
        tool == SketchTool.select || tool == SketchTool.rough || !snapping
            ? event.localPosition
            : snapper.snap(event.localPosition, history.document);
    setState(() {
      pointerStart = point;
      pointerCurrent = point;
      moveDelta = Offset.zero;
      if (tool == SketchTool.select) history.selectAt(point);
      if (tool == SketchTool.rough) roughPoints.add(point);
    });
  }

  void move(PointerMoveEvent event) {
    if (pointerStart == null) return;
    setState(() {
      pointerCurrent =
          tool == SketchTool.select || tool == SketchTool.rough || !snapping
              ? event.localPosition
              : snapper.snap(event.localPosition, history.document);
      if (tool == SketchTool.rough) roughPoints.add(event.localPosition);
      if (tool == SketchTool.select && history.selectedId != null) {
        moveDelta = pointerCurrent! - pointerStart!;
      }
    });
  }

  Future<void> up(PointerUpEvent event) async {
    if (pointerStart == null) return;
    if (tool == SketchTool.select) {
      if (history.selectedId != null && moveDelta.distance > 1) {
        history.moveSelected(moveDelta);
      }
    } else if (tool == SketchTool.rough) {
      final recognition = recognizer.recognize(roughPoints);
      if (recognition != null && mounted) {
        final corrected = await _confirmRecognition(recognition);
        if (!mounted) return;
        if (corrected != null) {
          history.add(recognition.toEntity(const Uuid().v4(),
              correctedKind: corrected));
        }
      }
    } else if (pointerCurrent != null &&
        (pointerCurrent! - pointerStart!).distance > 3) {
      final kind = switch (tool) {
        SketchTool.rough => throw StateError('rough uses recognition'),
        SketchTool.line => SketchEntityKind.line,
        SketchTool.rectangle => SketchEntityKind.rectangle,
        SketchTool.circle => SketchEntityKind.circle,
        SketchTool.arc => SketchEntityKind.arc,
        SketchTool.select => throw StateError('select cannot draw'),
      };
      history.add(SketchEntity(
          id: const Uuid().v4(),
          kind: kind,
          start: pointerStart!,
          end: pointerCurrent!));
    }
    setState(() {
      pointerStart = null;
      pointerCurrent = null;
      moveDelta = Offset.zero;
      roughPoints.clear();
    });
    persist();
  }

  Future<SketchEntityKind?> _confirmRecognition(SketchRecognition recognition) {
    return showDialog<SketchEntityKind>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm detected shape'),
        content: Text(
            '${recognition.kind.name} - ${(recognition.confidence * 100).round()}% confidence. Choose the intended editable shape.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Discard')),
          OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, SketchEntityKind.rectangle),
              child: const Text('Rectangle')),
          FilledButton(
              onPressed: () => Navigator.pop(context, SketchEntityKind.circle),
              child: const Text('Circle')),
        ],
      ),
    );
  }

  void undo() {
    setState(history.undo);
    persist();
  }

  void redo() {
    setState(history.redo);
    persist();
  }

  void delete() {
    setState(history.deleteSelected);
    persist();
  }

  void constrain(SketchConstraint constraint) {
    setState(() => history.constrainSelected(constraint));
    persist();
  }

  Future<void> dimension() async {
    final selected = history.selected;
    if (selected == null) return;
    final primary = TextEditingController(
        text: selected.primaryDimension.toStringAsFixed(1));
    final secondary = TextEditingController(
        text: selected.secondaryDimension?.toStringAsFixed(1));
    final result = await showDialog<List<double>>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(selected.kind == SketchEntityKind.rectangle
                  ? 'Set width and height'
                  : 'Set dimension'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: primary,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: selected.kind == SketchEntityKind.circle ||
                                selected.kind == SketchEntityKind.arc
                            ? 'Radius (mm)'
                            : selected.kind == SketchEntityKind.rectangle
                                ? 'Width (mm)'
                                : 'Length (mm)')),
                if (selected.secondaryDimension != null) ...[
                  const SizedBox(height: 12),
                  TextField(
                      controller: secondary,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Height (mm)'))
                ],
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () {
                      final first = double.tryParse(primary.text);
                      final second = selected.secondaryDimension == null
                          ? null
                          : double.tryParse(secondary.text);
                      if (first != null &&
                          first > 0 &&
                          (selected.secondaryDimension == null ||
                              second != null && second > 0)) {
                        Navigator.pop(
                            context, [first, if (second != null) second]);
                      }
                    },
                    child: const Text('Apply'))
              ],
            ));
    if (result == null) return;
    setState(() => history.dimensionSelected(
        result.first, result.length > 1 ? result[1] : null));
    persist();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xff071017),
        child: Stack(children: [
          Positioned.fill(
              child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: down,
                  onPointerMove: move,
                  onPointerUp: up,
                  onPointerHover: (event) =>
                      setState(() => hoverPoint = event.localPosition),
                  onPointerCancel: (_) => setState(() {
                        hoverPoint = null;
                        pointerStart = null;
                        pointerCurrent = null;
                        roughPoints.clear();
                      }),
                  child: CustomPaint(
                      painter: SketchPainter(
                          document: history.document,
                          selectedId: history.selectedId,
                          preview: _preview(),
                          selectedDelta: moveDelta,
                          hoverPoint: hoverPoint,
                          roughStroke: roughPoints)))),
          Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _tool(Icons.near_me_outlined, 'Select', SketchTool.select),
                    _tool(Icons.gesture, 'Rough', SketchTool.rough),
                    _tool(Icons.show_chart, 'Line', SketchTool.line),
                    _tool(Icons.rectangle_outlined, 'Rectangle',
                        SketchTool.rectangle),
                    _tool(Icons.circle_outlined, 'Circle', SketchTool.circle),
                    _tool(Icons.architecture, 'Arc', SketchTool.arc),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                        tooltip: snapping ? 'Snapping on' : 'Snapping off',
                        onPressed: () => setState(() => snapping = !snapping),
                        icon: Icon(snapping ? Icons.grid_on : Icons.grid_off)),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                        tooltip: 'Set dimension',
                        onPressed: history.selected == null ? null : dimension,
                        icon: const Icon(Icons.straighten)),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                        tooltip: 'Constrain horizontal',
                        onPressed:
                            history.selected?.kind == SketchEntityKind.line
                                ? () => constrain(SketchConstraint.horizontal)
                                : null,
                        icon: const Icon(Icons.horizontal_rule)),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                        tooltip: 'Constrain vertical',
                        onPressed:
                            history.selected?.kind == SketchEntityKind.line
                                ? () => constrain(SketchConstraint.vertical)
                                : null,
                        icon: const Icon(Icons.height)),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                        tooltip: 'Undo',
                        onPressed: history.canUndo ? undo : null,
                        icon: const Icon(Icons.undo)),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                        tooltip: 'Redo',
                        onPressed: history.canRedo ? redo : null,
                        icon: const Icon(Icons.redo)),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                        tooltip: 'Delete selection',
                        onPressed: history.selectedId == null ? null : delete,
                        icon: const Icon(Icons.delete_outline)),
                  ]))),
          Positioned(
              left: 18,
              bottom: 16,
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: const Color(0xdd121b25),
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Text(
                          '${history.document.entities.length} entities | ${tool.name} | ${_solveLabel(history.document.solveState)}')))),
        ]),
      );

  String _solveLabel(SketchSolveState state) => switch (state) {
        SketchSolveState.underConstrained => 'Under-constrained',
        SketchSolveState.fullyConstrained => 'Fully constrained',
        SketchSolveState.conflicting => 'Conflicting constraints',
      };
  Widget _tool(IconData icon, String label, SketchTool value) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SegmentedButton<SketchTool>(
          segments: [
            ButtonSegment(value: value, icon: Icon(icon), label: Text(label))
          ],
          selected: tool == value ? {value} : <SketchTool>{},
          emptySelectionAllowed: true,
          onSelectionChanged: (_) => choose(value)));
  SketchEntity? _preview() {
    if (tool == SketchTool.select ||
        tool == SketchTool.rough ||
        pointerStart == null ||
        pointerCurrent == null) {
      return null;
    }
    final kind = switch (tool) {
      SketchTool.rough => SketchEntityKind.line,
      SketchTool.line => SketchEntityKind.line,
      SketchTool.rectangle => SketchEntityKind.rectangle,
      SketchTool.circle => SketchEntityKind.circle,
      SketchTool.arc => SketchEntityKind.arc,
      SketchTool.select => SketchEntityKind.line
    };
    return SketchEntity(
        id: 'preview', kind: kind, start: pointerStart!, end: pointerCurrent!);
  }
}

class SketchPainter extends CustomPainter {
  SketchPainter(
      {required this.document,
      required this.selectedId,
      required this.preview,
      required this.selectedDelta,
      required this.hoverPoint,
      required this.roughStroke});
  final SketchDocument document;
  final String? selectedId;
  final SketchEntity? preview;
  final Offset selectedDelta;
  final Offset? hoverPoint;
  final List<Offset> roughStroke;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xff162633)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final axis = Paint()
      ..color = const Color(0xff315064)
      ..strokeWidth = 1.5;
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2), axis);
    canvas.drawLine(
        Offset(size.width / 2, 0), Offset(size.width / 2, size.height), axis);
    if (hoverPoint != null) {
      final hoverPaint = Paint()
        ..color = const Color(0x8896f7e3)
        ..strokeWidth = 1;
      canvas.drawCircle(
          hoverPoint!, 7, hoverPaint..style = PaintingStyle.stroke);
      canvas.drawLine(hoverPoint! - const Offset(11, 0),
          hoverPoint! + const Offset(11, 0), hoverPaint);
      canvas.drawLine(hoverPoint! - const Offset(0, 11),
          hoverPoint! + const Offset(0, 11), hoverPaint);
    }
    if (roughStroke.length > 1) {
      final roughPaint = Paint()
        ..color = const Color(0xffffbf69)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(roughStroke.first.dx, roughStroke.first.dy);
      for (final point in roughStroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, roughPaint);
    }
    for (final entity in document.entities) {
      final displayed =
          entity.id == selectedId ? entity.translated(selectedDelta) : entity;
      _draw(canvas, displayed, selected: entity.id == selectedId);
      _label(canvas, displayed);
    }
    if (preview != null) _draw(canvas, preview!, previewing: true);
  }

  void _draw(Canvas canvas, SketchEntity entity,
      {bool selected = false, bool previewing = false}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3 : 2
      ..color = selected
          ? const Color(0xffffbf69)
          : previewing
              ? const Color(0xaa29d3b2)
              : entity.recognitionConfidence != null &&
                      entity.recognitionConfidence! < 0.75
                  ? const Color(0xffff7b7b)
                  : const Color(0xff29d3b2);
    switch (entity.kind) {
      case SketchEntityKind.line:
        canvas.drawLine(entity.start, entity.end, paint);
      case SketchEntityKind.rectangle:
        canvas.drawRect(Rect.fromPoints(entity.start, entity.end), paint);
      case SketchEntityKind.circle:
        canvas.drawCircle(
            entity.start, (entity.end - entity.start).distance, paint);
      case SketchEntityKind.arc:
        final radius = (entity.end - entity.start).distance;
        canvas.drawArc(Rect.fromCircle(center: entity.start, radius: radius),
            -math.pi, math.pi, false, paint);
    }
    if (entity.constraint != null) {
      _text(
          canvas,
          entity.constraint == SketchConstraint.horizontal ? 'H' : 'V',
          (entity.start + entity.end) / 2 + const Offset(6, 6),
          const Color(0xff8ddcff));
    }
  }

  void _label(Canvas canvas, SketchEntity entity) {
    final anchor = switch (entity.kind) {
      SketchEntityKind.line =>
        (entity.start + entity.end) / 2 + const Offset(6, -22),
      SketchEntityKind.rectangle =>
        Rect.fromPoints(entity.start, entity.end).bottomCenter +
            const Offset(0, 6),
      SketchEntityKind.circle ||
      SketchEntityKind.arc =>
        entity.start + Offset(0, -(entity.end - entity.start).distance - 20)
    };
    _text(canvas, entity.measurementLabel, anchor, const Color(0xffa9bdc9));
  }

  void _text(Canvas canvas, String value, Offset offset, Color color) {
    final painter = TextPainter(
        text: TextSpan(
            text: value,
            style: TextStyle(
                color: color,
                fontSize: 11,
                backgroundColor: const Color(0xcc071017))),
        textDirection: TextDirection.ltr)
      ..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) => true;
}
