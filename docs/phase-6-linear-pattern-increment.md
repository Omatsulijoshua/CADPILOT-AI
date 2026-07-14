# Phase 6 linear cut-pattern increment

This increment adds an editable parametric linear pattern for circular through-cut features.

## Workflow

1. Create a rectangular extrusion and a circular through-cut.
2. Open the circular cut menu in the model tree and choose Linear pattern.
3. Enter a total instance count from 2 to 50 and positive X spacing.
4. CadPilot validates that spacing is at least the hole diameter and every instance remains inside the solid.
5. Edit, rename, suppress, delete, undo, or redo the pattern as a normal model-tree feature.

## Behavior

- The pattern references its source circular-cut operation.
- The source hole is the first instance; the pattern creates the remaining instances along positive X.
- Suppressing or deleting the source prevents dependent patterned holes from evaluating.
- Count, spacing, source ID, name, and suppression state persist across reopening.
- Pattern holes affect preview, net volume, surface area, material mass, and watertight STL export.
- Invalid counts, overlapping holes, non-circular profiles, and out-of-body instances are rejected by a reusable core validator before UI commit.

## Verify

1. Pattern a through-hole into three instances and confirm all three appear in the preview.
2. Confirm volume and mass decrease and surface area updates.
3. Export STL and validate the multi-hole mesh is closed manifold.
4. Edit count and spacing and confirm the feature updates as one history transaction.
5. Suppress the pattern and confirm only the source hole remains.
6. Suppress the source and confirm all dependent holes disappear.
7. Close and reopen the project and confirm pattern parameters remain editable.

## Honest limitations

This increment supports one-dimensional positive-X patterns of non-overlapping circular through-holes. Bidirectional patterns, arbitrary directions, rectangular and circular pattern layouts, patterned additive features, and native B-rep dependency graphs remain for later Phase 6 increments.