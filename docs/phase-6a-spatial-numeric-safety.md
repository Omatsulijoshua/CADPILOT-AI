# Phase 6A: Spatial numeric safety

This increment prevents invalid floating-point values from entering placement records, native transforms, or AR anchor requests.

## Included

- Finite, positive width, height, and depth validation in the placement form.
- Finite XYZ offset and rotation validation in the placement form.
- Independent validation at the native floor-transform boundary.
- Rejection of zero, negative, NaN, positive infinity, and negative infinity values.
- Required non-empty placement identity before creating a native anchor request.

## Safety rule

UI validation is not treated as a security or correctness boundary. Native transform generation repeats all critical checks so imported, migrated, or programmatically constructed records cannot bypass them.

## Verification

- Flutter static analysis passes.
- All 93 Flutter tests pass.
- Non-positive dimensions, NaN, infinity, non-finite transforms, and blank identities are covered by tests.
- Android debug APK builds successfully.
