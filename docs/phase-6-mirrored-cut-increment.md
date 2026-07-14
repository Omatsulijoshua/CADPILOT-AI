# Phase 6 mirrored-cut increment

This increment adds a dependency-aware mirror feature for circular through-cuts across the rectangular solid's vertical center plane.

## Workflow

1. Create a rectangular extrusion and circular through-cut.
2. Open the source cut menu in the model tree and choose Mirror cut.
3. CadPilot calculates the symmetric hole center across the body's vertical center plane.
4. The validator rejects invalid profiles, out-of-body source holes, centerline self-overlap, and collisions with existing cut geometry.
5. Rename, suppress, delete, undo, or redo the mirror feature through the normal model history.

## Behavior

- The mirror stores its source operation ID and circular sketch profile.
- Suppressing or deleting the source prevents the dependent mirrored cut from evaluating.
- The mirrored hole affects preview, volume, surface area, material mass, and watertight STL export.
- Mirror operations survive project save and reopen.

## Verify

1. Place a circular cut away from the center plane and create Mirror cut.
2. Confirm the second hole appears at the symmetric X coordinate with the same radius.
3. Confirm measurements and mass update.
4. Export STL and validate the two-hole mesh is closed manifold.
5. Suppress the source and confirm both source and mirrored holes disappear.
6. Try mirroring a centerline hole and confirm overlap is rejected.

## Honest limitations

This increment mirrors circular through-cuts across the base solid's vertical center plane only. User-selected planes, horizontal or arbitrary planes, additive-feature mirrors, chained dependency visualization, and native B-rep topology naming remain for later Phase 6 increments.