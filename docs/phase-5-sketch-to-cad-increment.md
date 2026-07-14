# Phase 5 sketch-to-CAD increment

This increment adds a local rough-stroke recognition workflow that converts stylus input into editable CadPilot sketch entities rather than a bitmap or mesh.

## Workflow

1. Choose Rough in the Sketch toolbar.
2. Draw one closed circle or rectangle in a single stroke.
3. CadPilot filters closely spaced samples, smooths stroke noise, checks closure, and scores the detected shape.
4. Review the detected type and confidence in the confirmation dialog.
5. Choose Circle or Rectangle to correct the interpretation, or Discard to leave the sketch unchanged.
6. Edit, move, dimension, delete, undo, or redo the committed entity with the existing sketch tools.

## Behavior

- Rough circles become dimension-locked editable circle entities.
- Rough rectangles become axis-aligned, dimension-locked editable rectangle entities.
- Recognition confidence is persisted in the project file.
- Results below 75% confidence are highlighted in red for correction.
- Open strokes and tiny closed marks are rejected rather than converted speculatively.
- Every accepted recognition is one undoable sketch-history transaction.

## Verify

1. Draw a noisy closed circle and confirm an editable circle is proposed.
2. Draw a rough rectangular loop and confirm an editable constrained rectangle is proposed.
3. Deliberately choose the other shape in the confirmation dialog and confirm the corrected type is committed.
4. Select the result, change its dimensions, move it, undo it, and redo it.
5. Close and reopen the project and confirm the editable entity and confidence remain available.
6. Draw an open stroke and confirm no geometry is added.

## Honest limitations

This first recognizer handles one closed circle or axis-aligned rectangle per stroke. Multi-stroke grouping, lines and arcs, corner/symmetry suggestions, rotated rectangles, learned recognition, and automatic 3D-operation suggestions remain for later Phase 5 increments.