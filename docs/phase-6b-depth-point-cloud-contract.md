# Phase 6B: Native depth and point-cloud frame contract

This increment establishes CadPilot's validated boundary for receiving a single depth-derived point-cloud frame from a future iOS LiDAR or Android depth-camera host. It does **not** claim that native depth capture, reconstruction, meshing, or LiDAR hardware support is complete.

## Why this boundary comes first

Native spatial APIs return platform-specific buffers, coordinate conventions, confidence values, timestamps, and tracking metadata. Passing those values directly into CAD would make corrupt, oversized, mismatched, or non-finite sensor data part of the project model. CadPilot now normalizes and validates one bounded frame before any reconstruction pipeline is allowed to consume it.

```mermaid
flowchart LR
    Capability{"Depth capability advertised?"} -- "No" --> Block["Block before native call"]
    Capability -- "Yes" --> Native["captureDepthFrame method channel"]
    Native --> Available{"Native frame returned?"}
    Available -- "No/error" --> Closed["Fail closed with no frame"]
    Available -- "Yes" --> Metadata["Validate session, frame, UTC time, coordinates"]
    Metadata --> Points["Validate count, finite XYZ, range, confidence"]
    Points --> Trusted["Typed SpatialPointCloudFrame"]
```

## Contract

A capture request contains:

- the trimmed active capture `sessionId`;
- coordinate system `right_handed_y_up_meters`;
- maximum requested point count of 250,000.

A native response must contain:

- a non-empty matching `sessionId`;
- a non-empty `frameId`;
- an ISO-8601 UTC `capturedAt` timestamp;
- the exact right-handed, Y-up, meter coordinate-system identifier;
- a sensor-to-world pose containing bounded translation and a normalized quaternion;
- between 3 and 250,000 point samples;
- finite numeric X, Y, and Z values within a conservative ±1,000 meter bound;
- a finite confidence value from 0 through 1 for every sample.

The strict coordinate-system name prevents millimeter/meter and handedness mistakes from silently distorting a CAD model. Native hosts must transform their platform coordinates into this convention before returning data.

## Pose normalization and multi-frame registration

Every frame now includes a sensor-to-world pose in the same right-handed, Y-up, meter system. Translation components must be finite and remain within ±1,000 meters. Rotation uses an `(x, y, z, w)` quaternion whose squared magnitude must stay within 0.01 of one; rejecting non-unit quaternions prevents scale distortion during rotation.

`SpatialFrameRegistration` accepts time-ordered frames from one session, rejects duplicate frame IDs, caps the aggregate at 500,000 samples, rotates each sensor-space point, applies world translation, and preserves confidence values.

```mermaid
flowchart LR
    Frames["Ordered typed frames"] --> Session{"One session and unique IDs?"}
    Session -- "No" --> Reject["Reject registration"]
    Session -- "Yes" --> Time{"Monotonic UTC times?"}
    Time -- "No" --> Reject
    Time -- "Yes" --> Limit{"At most 500,000 points?"}
    Limit -- "No" --> Reject
    Limit -- "Yes" --> Rotate["Quaternion rotation"]
    Rotate --> Translate["World translation"]
    Translate --> Cloud["Registered world-space point cloud"]
```

Registration is deterministic and intentionally performs only coordinate transformation. Cleanup is a separate, explicitly configured stage; meshing and persistence still require their own accuracy tolerances and tests.

## Deterministic point-cloud cleanup

`SpatialPointCloudProcessor` separates cleanup policy from registration and returns a typed result plus stage-by-stage statistics.

```mermaid
flowchart LR
    Input["Registered points"] --> Confidence["Minimum confidence filter"]
    Confidence --> Voxel["Best-confidence point per voxel"]
    Voxel --> Hash["Radius spatial hash"]
    Hash --> Neighbors{"Enough nearby points?"}
    Neighbors -- "No" --> Outlier["Remove isolated sample"]
    Neighbors -- "Yes" --> Output["Processed point cloud"]
    Output --> Stats["Removal statistics + provenance"]
```

Processing settings are validated before point work:

- confidence threshold must be from 0 through 1;
- voxel size must be from 1 millimeter through 1 meter;
- isolation radius must be between one and four voxel widths;
- required neighbor count must be from 0 through 26.

The radius-to-voxel ratio prevents an unbounded number of downsampled candidates from accumulating in each spatial-hash neighborhood. Voxel keys use mathematical floor operations, so negative and positive coordinates remain in distinct deterministic cells. The highest-confidence sample wins a voxel; equal-confidence ties preserve input order. A zero-neighbor setting intentionally disables isolation filtering.

This stage does not invent geometry, average surfaces, or persist scans. Default thresholds need calibration against labeled physical-device data before they can be treated as measurement-grade.

## Advisory measurement extraction

`SpatialMeasurementExtractor` derives bounded, axis-aligned observations from a processed cloud without claiming surface reconstruction.

```mermaid
flowchart LR
    Cloud["Processed point cloud"] --> Validate["Revalidate count, finite XYZ, confidence"]
    Validate --> Bounds["Min/max bounds + centroid"]
    Bounds --> Units["Convert meter extents to millimeters"]
    Units --> Summary["Dimensions, diagonal, mean confidence"]
    Summary --> Planar["Planar-axis check at 2x voxel resolution"]
    Planar --> Advisory["Advisory measurement result + provenance"]
```

The result includes width on X, height on Y, depth on Z, diagonal length, centroid, mean confidence, point count, source frame IDs, session ID, processing resolution, and the thinnest planar axis when its extent is no more than twice the voxel size. Extraction requires at least three points, rejects point-like and line-like bounds, revalidates finite coordinates and confidence, and retains the 500,000-point safety ceiling.

These are **axis-aligned scan bounds**, not oriented dimensions, watertight volume, surface area, toleranced inspection data, or certified measurements. The API always carries the label `Advisory scan bounds; not a certified measurement.` Physical-device calibration and an oriented/segmented geometry model are required before dimensions can drive manufacturing decisions.

## Bounded scan pipeline

`SpatialScanPipeline` is the orchestration boundary between native frame acquisition and
advisory scan output. It captures sequentially, with an explicit upper bound of 50
frames per scan, and then performs registration, cleanup, and measurement extraction in
that order. It never invents a measurement: no native frame returns `unavailable`, and
a scan with fewer than three validated processed points returns `insufficientData`.

```mermaid
flowchart LR
    Request["Requested frames: 1-50"] --> Capture["Sequential native capture"]
    Capture -->|"no frame"| Unavailable["unavailable result"]
    Capture --> Frames["Validated frames"]
    Frames --> Register["World-space registration"]
    Register --> Clean["Confidence, voxel, outlier cleanup"]
    Clean --> Enough{"At least 3 points?"}
    Enough -->|"no"| Insufficient["insufficientData result"]
    Enough -->|"yes"| Measurements["Advisory bounds"]
```

This is a Dart orchestration and safety boundary, not a claim of active device depth
capture. Android's native adapter remains unavailable until its ARCore depth session is
implemented and verified on compatible physical hardware.
## Capability gate

Capture is callable only when the capability snapshot reports `sceneDepthSupported` and identifies the method as `lidar` or `depth_camera`. Web and missing plugins return no frame. Platform errors also return no frame. Malformed frames throw `FormatException` so programming/data-contract errors remain distinguishable from unavailable hardware.

Android currently reports `sceneDepthSupported: false` and handles `captureDepthFrame` with the explicit `depth_capture_unavailable` platform error. This preserves truthful product behavior until an ARCore Depth session, camera texture, render/update loop, and depth-image conversion are implemented and verified on physical hardware.

## Safety properties

- Unsupported devices are rejected before invoking native code.
- Empty session identities are rejected.
- A response for another session is never accepted.
- NaN and infinite coordinates are rejected.
- Impossible confidence values and extreme coordinates are rejected.
- Tiny and oversized frames are rejected.
- Platform unavailability never becomes a successful empty scan.
- No point cloud is persisted or converted into CAD geometry in this increment.

## Verification

- Nineteen focused depth-frame, registration, cleanup, and measurement tests pass.
- The complete Flutter suite contains 158 passing tests.
- Flutter analysis passes with no issues.
- Android debug compilation verifies the Kotlin method-channel boundary against ARCore 1.54.0.
- Standard and WebAssembly web release builds remain compatible because web capture fails closed.

## Next Phase 6B work

1. Add a native ARCore Depth capability probe tied to a configured ARCore session.
2. Implement physical-device depth image acquisition and coordinate conversion.
3. Add pose-quality and tracking-state metadata from native capture.
4. Calibrate cleanup defaults against labeled physical-device scans.
5. Build bounded surface reconstruction without treating scan bounds as a mesh.
6. Add an iOS ARKit/LiDAR adapter using the same normalized frame contract.

Each step must retain separate capability claims. Depth frames, registered point clouds, meshes, and editable CAD geometry are different completion levels.
