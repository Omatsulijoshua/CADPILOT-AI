import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    super.key,
  });
  final String projectName;
  final SpatialCapabilityService service;

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
                      onPressed: value.arSupported ? () {} : null,
                      icon: const Icon(Icons.view_in_ar),
                      label: const Text('AR placement (foundation ready)'),
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

  static Widget _status(String label, bool supported) => Chip(
        avatar: Icon(supported ? Icons.check_circle : Icons.cancel,
            size: 18, color: supported ? Colors.greenAccent : Colors.grey),
        label: Text('$label: ${supported ? 'Supported' : 'Unavailable'}'),
      );
}
