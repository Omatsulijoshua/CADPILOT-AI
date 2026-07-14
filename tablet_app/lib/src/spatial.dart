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

class SpatialCapabilityService {
  const SpatialCapabilityService({
    MethodChannel channel = const MethodChannel('cadpilot/spatial'),
  }) : _channel = channel;
  final MethodChannel _channel;

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
    this.onPlacementSaved,
    super.key,
  });
  final String projectName;
  final SpatialCapabilityService service;
  final List<SpatialPlacement> placements;
  final ValueChanged<SpatialPlacement>? onPlacementSaved;

  @override
  State<SpatialCapabilityPanel> createState() => _SpatialCapabilityPanelState();
}

class _SpatialCapabilityPanelState extends State<SpatialCapabilityPanel> {
  late final Future<SpatialCapabilities> capabilities = widget.service.detect();

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
              return Column(mainAxisSize: MainAxisSize.min, children: [
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
                  _status('LiDAR', value.lidarSupported),
                  _status('Scene depth', value.sceneDepthSupported),
                  _status(
                      'Mesh reconstruction', value.meshReconstructionSupported),
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
                      onPressed: value.cameraSupported ? () {} : null,
                      icon: const Icon(Icons.document_scanner),
                      label: const Text('Scan capture (next increment)'),
                    ),
                  ),
                ]),
                if (widget.placements.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Saved placements (${widget.placements.length})',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  ...widget.placements.take(3).map((placement) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(placement.name),
                        subtitle: Text(
                            '${placement.plane} plane - ${placement.widthMm} x ${placement.heightMm} x ${placement.depthMm} mm'),
                      )),
                ],
              ]);
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      );

  Future<void> _planPlacement(
      BuildContext context, SpatialCapabilities capabilities) async {
    final placement = await showDialog<SpatialPlacement>(
      context: context,
      builder: (_) => PlacementPlannerDialog(
        projectName: widget.projectName,
        source: capabilities.arSupported ? 'camera_ar' : 'manual',
      ),
    );
    if (placement != null) widget.onPlacementSaved?.call(placement);
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
    super.key,
  });

  final String projectName;
  final String source;

  @override
  State<PlacementPlannerDialog> createState() => _PlacementPlannerDialogState();
}

class _PlacementPlannerDialogState extends State<PlacementPlannerDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: 'Primary placement');
  final width = TextEditingController(text: '1000');
  final height = TextEditingController(text: '1000');
  final depth = TextEditingController(text: '1000');
  final x = TextEditingController(text: '0');
  final y = TextEditingController(text: '0');
  final z = TextEditingController(text: '0');
  final rotation = TextEditingController(text: '0');
  String plane = 'floor';

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
    return parsed == null || parsed <= 0 ? 'Enter a value above 0' : null;
  }

  String? numeric(String? value) =>
      double.tryParse(value?.trim() ?? '') == null ? 'Enter a number' : null;

  void save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      SpatialPlacement(
        id: 'placement-${DateTime.now().microsecondsSinceEpoch}',
        name: name.text.trim(),
        createdAt: DateTime.now().toUtc(),
        source: widget.source,
        plane: plane,
        widthMm: number(width),
        heightMm: number(height),
        depthMm: number(depth),
        offsetXMm: number(x),
        offsetYMm: number(y),
        offsetZMm: number(z),
        rotationDegrees: number(rotation),
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
