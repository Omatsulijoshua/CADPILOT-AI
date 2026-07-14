import 'package:cadpilot_tablet/src/sketch_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sketch entities serialize and hit test', () {
    const line = SketchEntity(
        id: 'line-1',
        kind: SketchEntityKind.line,
        start: Offset(10, 10),
        end: Offset(110, 10));
    final decoded = SketchEntity.fromJson(line.toJson());
    expect(decoded.hitTest(const Offset(60, 14)), isTrue);
    expect(decoded.hitTest(const Offset(60, 50)), isFalse);
  });

  test('history undo and redo restore committed geometry', () {
    final history = SketchHistory(const SketchDocument());
    history.add(const SketchEntity(
        id: 'rect-1',
        kind: SketchEntityKind.rectangle,
        start: Offset(20, 20),
        end: Offset(100, 80)));
    expect(history.document.entities, hasLength(1));
    history.undo();
    expect(history.document.entities, isEmpty);
    expect(history.canRedo, isTrue);
    history.redo();
    expect(history.document.entities.single.id, 'rect-1');
  });

  test('selection move and delete are reversible', () {
    final history = SketchHistory(const SketchDocument(entities: [
      SketchEntity(
          id: 'circle-1',
          kind: SketchEntityKind.circle,
          start: Offset(50, 50),
          end: Offset(70, 50))
    ]));
    history.selectAt(const Offset(70, 50));
    history.moveSelected(const Offset(10, 5));
    expect(history.document.entities.single.start, const Offset(60, 55));
    history.deleteSelected();
    expect(history.document.entities, isEmpty);
    history.undo();
    expect(history.document.entities, hasLength(1));
  });

  test('dimensions resize geometry and remain undoable', () {
    final history = SketchHistory(const SketchDocument(entities: [
      SketchEntity(
          id: 'rect-1',
          kind: SketchEntityKind.rectangle,
          start: Offset(10, 10),
          end: Offset(30, 25))
    ]));
    history.selectAt(const Offset(30, 18));
    history.dimensionSelected(120, 45);
    expect(history.selected!.primaryDimension, 120);
    expect(history.selected!.secondaryDimension, 45);
    history.undo();
    expect(history.document.entities.single.primaryDimension, 20);
  });

  test('line constraints persist through serialization', () {
    final history = SketchHistory(const SketchDocument(entities: [
      SketchEntity(
          id: 'line-1',
          kind: SketchEntityKind.line,
          start: Offset(5, 5),
          end: Offset(60, 30))
    ]));
    history.selectAt(const Offset(30, 17));
    history.constrainSelected(SketchConstraint.horizontal);
    final constrained = history.selected!;
    expect(constrained.end.dy, constrained.start.dy);
    final decoded = SketchEntity.fromJson(constrained.toJson());
    expect(decoded.constraint, SketchConstraint.horizontal);
  });

  test('arc stores radius and supports selection', () {
    const arc = SketchEntity(
        id: 'arc-1',
        kind: SketchEntityKind.arc,
        start: Offset(100, 100),
        end: Offset(140, 100));
    expect(arc.primaryDimension, 40);
    expect(arc.hitTest(const Offset(100, 60)), isTrue);
  });
}
