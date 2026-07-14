import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'sketch_models.dart';

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

  @override
  void initState() {
    super.initState();
    history = SketchHistory(widget.document);
  }

  void choose(SketchTool next) => setState(() {
        tool = next;
        pointerStart = null;
        pointerCurrent = null;
        moveDelta = Offset.zero;
      });
  void down(PointerDownEvent event) {
    final point = event.localPosition;
    setState(() {
      pointerStart = point;
      pointerCurrent = point;
      moveDelta = Offset.zero;
      if (tool == SketchTool.select) history.selectAt(point);
    });
  }

  void move(PointerMoveEvent event) {
    if (pointerStart == null) return;
    setState(() {
      pointerCurrent = event.localPosition;
      if (tool == SketchTool.select && history.selectedId != null) {
        moveDelta = pointerCurrent! - pointerStart!;
      }
    });
  }

  void up(PointerUpEvent event) {
    if (pointerStart == null) return;
    if (tool == SketchTool.select) {
      if (history.selectedId != null && moveDelta.distance > 1) {
        history.moveSelected(moveDelta);
      }
    } else if (pointerCurrent != null &&
        (pointerCurrent! - pointerStart!).distance > 3) {
      final kind = switch (tool) {
        SketchTool.line => SketchEntityKind.line,
        SketchTool.rectangle => SketchEntityKind.rectangle,
        SketchTool.circle => SketchEntityKind.circle,
        SketchTool.select => throw StateError('select cannot draw')
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
    });
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

  void delete() {
    setState(history.deleteSelected);
    widget.onChanged(history.document);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xff071017),
      child: Stack(children: [
        Positioned.fill(
            child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: down,
          onPointerMove: move,
          onPointerUp: up,
          child: CustomPaint(
              painter: SketchPainter(
                  document: history.document,
                  selectedId: history.selectedId,
                  preview: _preview(),
                  selectedDelta: moveDelta)),
        )),
        Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(children: [
              _tool(Icons.near_me_outlined, 'Select', SketchTool.select),
              _tool(Icons.show_chart, 'Line', SketchTool.line),
              _tool(
                  Icons.rectangle_outlined, 'Rectangle', SketchTool.rectangle),
              _tool(Icons.circle_outlined, 'Circle', SketchTool.circle),
              const Spacer(),
              IconButton.filledTonal(
                  tooltip: 'Undo',
                  onPressed: history.canUndo ? undo : null,
                  icon: const Icon(Icons.undo)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: 'Redo',
                  onPressed: history.canRedo ? redo : null,
                  icon: const Icon(Icons.redo)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: 'Delete selection',
                  onPressed: history.selectedId == null ? null : delete,
                  icon: const Icon(Icons.delete_outline)),
            ])),
        Positioned(
            left: 18,
            bottom: 16,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: const Color(0xdd121b25),
                    borderRadius: BorderRadius.circular(8)),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                        '${history.document.entities.length} entities Ã¢â‚¬Â¢ ${tool.name}')))),
      ]),
    );
  }

  Widget _tool(IconData icon, String label, SketchTool value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SegmentedButton<SketchTool>(
            segments: [
              ButtonSegment(value: value, icon: Icon(icon), label: Text(label))
            ],
            selected: tool == value ? {value} : <SketchTool>{},
            emptySelectionAllowed: true,
            onSelectionChanged: (_) => choose(value)),
      );

  SketchEntity? _preview() {
    if (tool == SketchTool.select ||
        pointerStart == null ||
        pointerCurrent == null) {
      return null;
    }
    final kind = switch (tool) {
      SketchTool.line => SketchEntityKind.line,
      SketchTool.rectangle => SketchEntityKind.rectangle,
      SketchTool.circle => SketchEntityKind.circle,
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
      required this.selectedDelta});
  final SketchDocument document;
  final String? selectedId;
  final SketchEntity? preview;
  final Offset selectedDelta;
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
    for (final entity in document.entities) {
      _draw(canvas,
          entity.id == selectedId ? entity.translated(selectedDelta) : entity,
          selected: entity.id == selectedId);
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
              : const Color(0xff29d3b2);
    switch (entity.kind) {
      case SketchEntityKind.line:
        canvas.drawLine(entity.start, entity.end, paint);
      case SketchEntityKind.rectangle:
        canvas.drawRect(Rect.fromPoints(entity.start, entity.end), paint);
      case SketchEntityKind.circle:
        canvas.drawCircle(
            entity.start, (entity.end - entity.start).distance, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) => true;
}
