import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'spatial_models.dart';

class SpatialCapabilities {
  const SpatialCapabilities({
    required this.platform,
    required this.cameraSupported,
    required this.arSupported,
    required this.lidarSupported,
    required this.sceneDepthSupported,
    required this.meshReconstructionSupported,
    required this.planeDetectionSupported,
    required this.motionTrackingSupported,
    required this.captureMethod,
    this.nativeArRendererAvailable = false,
    this.arRuntimeInstalled = false,
  });

  final String platform;
  final bool cameraSupported;
  final bool arSupported;
  final bool lidarSupported;
  final bool sceneDepthSupported;
  final bool meshReconstructionSupported;
  final bool planeDetectionSupported;
  final bool motionTrackingSupported;
  final String captureMethod;
  final bool nativeArRendererAvailable;
  final bool arRuntimeInstalled;

  factory SpatialCapabilities.fromMap(Map<Object?, Object?> value) =>
      SpatialCapabilities(
        platform: value['platform'] as String? ?? 'unknown',
        cameraSupported: value['cameraSupported'] as bool? ?? false,
        arSupported: value['arSupported'] as bool? ?? false,
        lidarSupported: value['lidarSupported'] as bool? ?? false,
        sceneDepthSupported: value['sceneDepthSupported'] as bool? ?? false,
        meshReconstructionSupported:
            value['meshReconstructionSupported'] as bool? ?? false,
        planeDetectionSupported:
            value['planeDetectionSupported'] as bool? ?? false,
        motionTrackingSupported:
            value['motionTrackingSupported'] as bool? ?? false,
        captureMethod: value['captureMethod'] as String? ?? 'manual',
        nativeArRendererAvailable:
            value['nativeArRendererAvailable'] as bool? ?? false,
        arRuntimeInstalled: value['arRuntimeInstalled'] as bool? ?? false,
      );

  static const unsupported = SpatialCapabilities(
    platform: 'unsupported',
    cameraSupported: false,
    arSupported: false,
    lidarSupported: false,
    sceneDepthSupported: false,
    meshReconstructionSupported: false,
    planeDetectionSupported: false,
    motionTrackingSupported: false,
    captureMethod: 'manual',
  );

  String get methodLabel => switch (captureMethod) {
        'lidar' => 'LiDAR depth scanning',
        'depth_camera' => 'Depth-camera scanning',
        'camera_ar' => 'Camera AR tracking',
        _ => 'Manual measurement fallback',
      };
}

enum CameraPermissionState {
  granted,
  notDetermined,
  denied,
  permanentlyDenied,
  restricted,
  unavailable;

  static CameraPermissionState fromNative(String? value) => switch (value) {
        'granted' => granted,
        'not_determined' => notDetermined,
        'denied' => denied,
        'permanently_denied' => permanentlyDenied,
        'restricted' => restricted,
        _ => unavailable,
      };

  String get label => switch (this) {
        granted => 'Camera access granted',
        notDetermined => 'Camera access not requested',
        denied => 'Camera access denied',
        permanentlyDenied => 'Camera access blocked in system settings',
        restricted => 'Camera access restricted by device policy',
        unavailable => 'Camera access unavailable',
      };
}

enum ArRuntimeInstallResult {
  installed,
  installRequested,
  declined,
  unavailable;

  static ArRuntimeInstallResult fromNative(String? value) => switch (value) {
        'installed' => installed,
        'install_requested' => installRequested,
        'declined' => declined,
        _ => unavailable,
      };
}

class ArPlacementPreflight {
  const ArPlacementPreflight({
    required this.capabilities,
    required this.cameraPermission,
  });

  final SpatialCapabilities capabilities;
  final CameraPermissionState cameraPermission;

  bool get ready =>
      capabilities.arSupported &&
      capabilities.planeDetectionSupported &&
      capabilities.arRuntimeInstalled &&
      capabilities.nativeArRendererAvailable &&
      cameraPermission == CameraPermissionState.granted;

  String get placementSource => ready ? 'camera_ar' : 'manual';

  List<String> get blockers => [
        if (!capabilities.arSupported) 'AR tracking is unavailable',
        if (capabilities.arSupported && !capabilities.planeDetectionSupported)
          'Plane detection is unavailable',
        if (capabilities.arSupported && !capabilities.arRuntimeInstalled)
          'AR runtime is not installed or needs an update',
        if (capabilities.arSupported && !capabilities.nativeArRendererAvailable)
          'CadPilot native AR rendering is unavailable',
        if (capabilities.arSupported &&
            cameraPermission != CameraPermissionState.granted)
          cameraPermission.label,
      ];
}

class SpatialCapabilityService {
  const SpatialCapabilityService({
    MethodChannel channel = const MethodChannel('cadpilot/spatial'),
  }) : _channel = channel;
  final MethodChannel _channel;
  Future<ArRuntimeInstallResult> requestArRuntimeInstall() async {
    if (kIsWeb) return ArRuntimeInstallResult.unavailable;
    try {
      final value =
          await _channel.invokeMethod<String>('requestArRuntimeInstall');
      return ArRuntimeInstallResult.fromNative(value);
    } on PlatformException {
      return ArRuntimeInstallResult.unavailable;
    } on MissingPluginException {
      return ArRuntimeInstallResult.unavailable;
    }
  }

  Future<SpatialAnchor?> createFloorAnchor({
    required SpatialPlacement placement,
    required ArPlacementPreflight preflight,
  }) async {
    if (!preflight.ready) {
      throw StateError(
          'AR placement preflight must pass before anchor creation.');
    }
    final request = NativeFloorAnchorRequest.fromPlacement(placement);
    if (kIsWeb) return null;
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'createFloorAnchor',
        request.toMap(),
      );
      if (value == null) return null;
      return SpatialAnchor.fromJson(Map<String, Object?>.from(value));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<ArPlacementPreflight> placementPreflight({
    SpatialCapabilities? knownCapabilities,
    bool requestPermission = false,
  }) async {
    final value = knownCapabilities ?? await detect();
    final permission = value.arSupported
        ? await cameraPermission(request: requestPermission)
        : CameraPermissionState.unavailable;
    return ArPlacementPreflight(
      capabilities: value,
      cameraPermission: permission,
    );
  }

  Future<CameraPermissionState> cameraPermission({bool request = false}) async {
    if (kIsWeb) return CameraPermissionState.unavailable;
    try {
      final value = await _channel.invokeMethod<String>(
          request ? 'requestCameraPermission' : 'getCameraPermission');
      return CameraPermissionState.fromNative(value);
    } on PlatformException {
      return CameraPermissionState.unavailable;
    } on MissingPluginException {
      return CameraPermissionState.unavailable;
    }
  }

  Future<SpatialCapabilities> detect() async {
    if (kIsWeb) return SpatialCapabilities.unsupported;
    try {
      final value =
          await _channel.invokeMapMethod<Object?, Object?>('getCapabilities');
      return value == null
          ? SpatialCapabilities.unsupported
          : SpatialCapabilities.fromMap(value);
    } on PlatformException {
      return SpatialCapabilities.unsupported;
    } on MissingPluginException {
      return SpatialCapabilities.unsupported;
    }
  }
}

class SpatialCapabilityPanel extends StatefulWidget {
  const SpatialCapabilityPanel({
    required this.projectName,
    this.service = const SpatialCapabilityService(),
    this.placements = const [],
    this.onPlacementsChanged,
    super.key,
  });
  final String projectName;
  final SpatialCapabilityService service;
  final List<SpatialPlacement> placements;
  final ValueChanged<List<SpatialPlacement>>? onPlacementsChanged;

  @override
  State<SpatialCapabilityPanel> createState() => _SpatialCapabilityPanelState();
}

class _SpatialCapabilityPanelState extends State<SpatialCapabilityPanel> {
  late Future<SpatialCapabilities> capabilities = widget.service.detect();
  late List<SpatialPlacement> placements;

  @override
  void initState() {
    super.initState();
    placements = [...widget.placements];
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Spatial workspace - ${widget.projectName}'),
        content: SizedBox(
          width: 620,
          child: FutureBuilder<SpatialCapabilities>(
            future: capabilities,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator()));
              }
              final value = snapshot.data!;
              return SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                    leading: Icon(value.lidarSupported
                        ? Icons.sensors
                        : value.arSupported
                            ? Icons.view_in_ar
                            : Icons.straighten),
                    title: Text(value.methodLabel),
                    subtitle: Text(value.lidarSupported
                        ? 'Hardware LiDAR capability confirmed.'
                        : value.arSupported
                            ? 'LiDAR is not reported; camera tracking is labeled separately.'
                            : 'AR is unavailable. CAD and manual measurements remain available.'),
                  ),
                  const Divider(),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    _status('Camera', value.cameraSupported),
                    _status('AR tracking', value.arSupported),
                    _status('AR runtime', value.arRuntimeInstalled),
                    _status('CadPilot AR renderer',
                        value.nativeArRendererAvailable),
                    _status('LiDAR', value.lidarSupported),
                    _status('Scene depth', value.sceneDepthSupported),
                    _status('Mesh reconstruction',
                        value.meshReconstructionSupported),
                    _status('Plane detection', value.planeDetectionSupported),
                  ]),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _planPlacement(context, value),
                        icon: Icon(value.arSupported
                            ? Icons.view_in_ar
                            : Icons.straighten),
                        label: Text(value.arSupported
                            ? 'Plan AR placement'
                            : 'Add manual placement'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: value.cameraSupported
                            ? () => _requestCameraAccess(context)
                            : null,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Check camera access'),
                      ),
                    ),
                  ]),
                  if (value.arSupported && !value.arRuntimeInstalled) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _requestArRuntime(context),
                        icon: const Icon(Icons.system_update_alt),
                        label: const Text('Install or update AR runtime'),
                      ),
                    ),
                  ],
                  if (placements.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Saved placements (${placements.length})',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    ...placements.map((placement) => ListTile(
                          dense: true,
                          leading: Icon(placement.anchor == null
                              ? Icons.location_searching
                              : Icons.location_on),
                          title: Text(placement.name),
                          subtitle: Text(
                              '${placement.plane} plane - 1:1 scale - ${placement.widthMm} x ${placement.heightMm} x ${placement.depthMm} mm\n${_anchorLabel(placement)}'),
                          trailing: Wrap(children: [
                            IconButton(
                                tooltip: 'Edit placement',
                                onPressed: placement.isLocked
                                    ? null
                                    : () => _editPlacement(context, placement),
                                icon: const Icon(Icons.edit_outlined)),
                            IconButton(
                                tooltip: placement.isLocked
                                    ? 'Unlock placement'
                                    : 'Lock placement',
                                onPressed: () => _toggleLock(placement),
                                icon: Icon(placement.isLocked
                                    ? Icons.lock_outline
                                    : Icons.lock_open_outlined)),
                            IconButton(
                                tooltip: 'Duplicate placement',
                                onPressed: () => _duplicatePlacement(placement),
                                icon: const Icon(Icons.copy_outlined)),
                            IconButton(
                                tooltip: 'Delete placement',
                                onPressed: placement.isLocked
                                    ? null
                                    : () =>
                                        _deletePlacement(context, placement),
                                icon: const Icon(Icons.delete_outline)),
                          ]),
                        )),
                  ],
                ]),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      );

  Future<void> _requestArRuntime(BuildContext context) async {
    final result = await widget.service.requestArRuntimeInstall();
    if (!context.mounted) return;
    final message = switch (result) {
      ArRuntimeInstallResult.installed =>
        'The AR runtime is installed. CadPilot will check readiness again.',
      ArRuntimeInstallResult.installRequested =>
        'Complete the AR runtime installation, then return to CadPilot.',
      ArRuntimeInstallResult.declined =>
        'AR runtime installation was declined. Manual placement remains available.',
      ArRuntimeInstallResult.unavailable =>
        'The AR runtime cannot be installed on this device. Manual placement remains available.',
    };
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('AR runtime'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => capabilities = widget.service.detect());
  }

  Future<void> _requestCameraAccess(BuildContext context) async {
    final state = await widget.service.cameraPermission(request: true);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Camera readiness'),
        content: Text(state == CameraPermissionState.granted
            ? 'Camera access is ready. Live AR and scan capture will start only when you choose a capture workflow.'
            : '${state.label}. Manual placement remains available.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _planPlacement(
      BuildContext context, SpatialCapabilities capabilities) async {
    final preflight = await widget.service.placementPreflight(
      knownCapabilities: capabilities,
      requestPermission: capabilities.arSupported,
    );
    if (!context.mounted) return;
    if (!preflight.ready && capabilities.arSupported) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Using manual placement'),
          content: Text(
              '${preflight.blockers.join('. ')}. This record will not be labeled as camera AR.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Continue')),
          ],
        ),
      );
      if (!context.mounted) return;
    }
    final placement = await showDialog<SpatialPlacement>(
      context: context,
      builder: (_) => PlacementPlannerDialog(
        projectName: widget.projectName,
        source: preflight.placementSource,
      ),
    );
    if (placement != null) _upsert(placement);
  }

  Future<void> _editPlacement(
      BuildContext context, SpatialPlacement placement) async {
    final updated = await showDialog<SpatialPlacement>(
      context: context,
      builder: (_) => PlacementPlannerDialog(
          projectName: widget.projectName,
          source: placement.source,
          initial: placement),
    );
    if (updated != null) _upsert(updated);
  }

  String _anchorLabel(SpatialPlacement placement) {
    final anchor = placement.anchor;
    if (anchor == null) return 'Unanchored placement plan';
    return '${anchor.platform.toUpperCase()} anchor - ${anchor.trackingState.name}';
  }

  void _toggleLock(SpatialPlacement placement) {
    _upsert(placement.copyWith(isLocked: !placement.isLocked));
  }

  void _duplicatePlacement(SpatialPlacement placement) {
    final stamp = DateTime.now();
    _upsert(placement
        .copyWith(
            id: 'placement-${stamp.microsecondsSinceEpoch}',
            name: '${placement.name} copy',
            createdAt: stamp.toUtc())
        .detachAnchor());
  }

  Future<void> _deletePlacement(
      BuildContext context, SpatialPlacement placement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete placement?'),
        content: Text('Remove "${placement.name}" from this project?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => placements.removeWhere((item) => item.id == placement.id));
    widget.onPlacementsChanged?.call(List.unmodifiable(placements));
  }

  void _upsert(SpatialPlacement placement) {
    setState(() {
      final index = placements.indexWhere((item) => item.id == placement.id);
      if (index < 0) {
        placements.add(placement);
      } else {
        placements[index] = placement;
      }
    });
    widget.onPlacementsChanged?.call(List.unmodifiable(placements));
  }

  static Widget _status(String label, bool supported) => Chip(
        avatar: Icon(supported ? Icons.check_circle : Icons.cancel,
            size: 18, color: supported ? Colors.greenAccent : Colors.grey),
        label: Text('$label: ${supported ? 'Supported' : 'Unavailable'}'),
      );
}

class PlacementPlannerDialog extends StatefulWidget {
  const PlacementPlannerDialog({
    required this.projectName,
    required this.source,
    this.initial,
    super.key,
  });

  final String projectName;
  final String source;
  final SpatialPlacement? initial;

  @override
  State<PlacementPlannerDialog> createState() => _PlacementPlannerDialogState();
}

class _PlacementPlannerDialogState extends State<PlacementPlannerDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController width;
  late final TextEditingController height;
  late final TextEditingController depth;
  late final TextEditingController x;
  late final TextEditingController y;
  late final TextEditingController z;
  late final TextEditingController rotation;
  late String plane;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    name = TextEditingController(text: initial?.name ?? 'Primary placement');
    width = TextEditingController(text: '${initial?.widthMm ?? 1000}');
    height = TextEditingController(text: '${initial?.heightMm ?? 1000}');
    depth = TextEditingController(text: '${initial?.depthMm ?? 1000}');
    x = TextEditingController(text: '${initial?.offsetXMm ?? 0}');
    y = TextEditingController(text: '${initial?.offsetYMm ?? 0}');
    z = TextEditingController(text: '${initial?.offsetZMm ?? 0}');
    rotation = TextEditingController(text: '${initial?.rotationDegrees ?? 0}');
    plane = initial?.plane ?? 'floor';
  }

  @override
  void dispose() {
    for (final controller in [name, width, height, depth, x, y, z, rotation]) {
      controller.dispose();
    }
    super.dispose();
  }

  double number(TextEditingController controller) =>
      double.parse(controller.text.trim());

  String? positive(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null || !parsed.isFinite || parsed <= 0
        ? 'Enter a finite value above 0'
        : null;
  }

  String? numeric(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null || !parsed.isFinite ? 'Enter a finite number' : null;
  }

  void save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      SpatialPlacement(
        id: widget.initial?.id ??
            'placement-${DateTime.now().microsecondsSinceEpoch}',
        name: name.text.trim(),
        createdAt: widget.initial?.createdAt ?? DateTime.now().toUtc(),
        source: widget.source,
        plane: plane,
        widthMm: number(width),
        heightMm: number(height),
        depthMm: number(depth),
        offsetXMm: number(x),
        offsetYMm: number(y),
        offsetZMm: number(z),
        rotationDegrees: number(rotation),
        isLocked: widget.initial?.isLocked ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Placement plan - ${widget.projectName}'),
        content: SizedBox(
          width: 600,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Chip(
                  avatar: Icon(Icons.aspect_ratio),
                  label: Text('True scale locked at 1:1'),
                ),
                const SizedBox(height: 8),
                Text(widget.source == 'camera_ar'
                    ? 'Camera AR is available. This plan will be ready for a live plane anchor.'
                    : 'Manual fallback: enter measured values without claiming an AR anchor.'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Placement name'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Enter a placement name'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: plane,
                  decoration:
                      const InputDecoration(labelText: 'Mounting plane'),
                  items: const [
                    DropdownMenuItem(value: 'floor', child: Text('Floor')),
                    DropdownMenuItem(value: 'wall', child: Text('Wall')),
                    DropdownMenuItem(value: 'ceiling', child: Text('Ceiling')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: (value) => setState(() => plane = value!),
                ),
                const SizedBox(height: 12),
                _row([
                  _field(width, 'Width (mm)', positive),
                  _field(height, 'Height (mm)', positive),
                  _field(depth, 'Depth (mm)', positive),
                ]),
                const SizedBox(height: 12),
                _row([
                  _field(x, 'X offset (mm)', numeric),
                  _field(y, 'Y offset (mm)', numeric),
                  _field(z, 'Z offset (mm)', numeric),
                ]),
                const SizedBox(height: 12),
                _field(rotation, 'Rotation (degrees)', numeric),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton.icon(
              onPressed: save,
              icon: const Icon(Icons.save),
              label: const Text('Save placement')),
        ],
      );

  Widget _field(TextEditingController controller, String label,
          String? Function(String?) validator) =>
      TextFormField(
        controller: controller,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: label),
        validator: validator,
      );

  Widget _row(List<Widget> children) => Row(
        children: children
            .expand(
                (child) => [Expanded(child: child), const SizedBox(width: 8)])
            .toList()
          ..removeLast(),
      );
}
