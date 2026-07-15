import 'spatial.dart';
import 'spatial_depth_capture.dart';
import 'spatial_measurements.dart';
import 'spatial_point_processing.dart';
import 'spatial_registration.dart';

const int maxSpatialFramesPerScan = 50;

enum SpatialScanStatus { completed, unavailable, insufficientData }

class SpatialScanResult {
  const SpatialScanResult({
    required this.status,
    required this.frames,
    this.processedCloud,
    this.measurements,
    this.message,
  });

  final SpatialScanStatus status;
  final List<SpatialPointCloudFrame> frames;
  final ProcessedSpatialPointCloud? processedCloud;
  final SpatialScanMeasurements? measurements;
  final String? message;

  bool get completed => status == SpatialScanStatus.completed;
}

class SpatialScanPipeline {
  const SpatialScanPipeline({
    SpatialFrameRegistration registration = const SpatialFrameRegistration(),
    SpatialPointCloudProcessor processor = const SpatialPointCloudProcessor(),
    SpatialMeasurementExtractor measurementExtractor =
        const SpatialMeasurementExtractor(),
  })  : _registration = registration,
        _processor = processor,
        _measurementExtractor = measurementExtractor;

  final SpatialFrameRegistration _registration;
  final SpatialPointCloudProcessor _processor;
  final SpatialMeasurementExtractor _measurementExtractor;

  Future<SpatialScanResult> captureAndProcess({
    required String sessionId,
    required SpatialCapabilities capabilities,
    required SpatialDepthCaptureService captureService,
    int requestedFrames = 1,
    SpatialPointProcessingSettings settings =
        const SpatialPointProcessingSettings(),
  }) async {
    if (requestedFrames < 1 || requestedFrames > maxSpatialFramesPerScan) {
      throw RangeError.range(
        requestedFrames,
        1,
        maxSpatialFramesPerScan,
        'requestedFrames',
      );
    }
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      throw const FormatException(
          'Spatial scan requires a non-empty sessionId.');
    }

    final frames = <SpatialPointCloudFrame>[];
    for (var index = 0; index < requestedFrames; index++) {
      final frame = await captureService.capture(
        sessionId: normalizedSessionId,
        capabilities: capabilities,
      );
      if (frame == null) break;
      if (frame.sessionId != normalizedSessionId) {
        throw const FormatException(
          'Spatial capture returned a frame for a different session.',
        );
      }
      frames.add(frame);
    }
    if (frames.isEmpty) {
      return const SpatialScanResult(
        status: SpatialScanStatus.unavailable,
        frames: [],
        message: 'No depth frame was available from this device or session.',
      );
    }
    return processFrames(frames, settings: settings);
  }

  SpatialScanResult processFrames(
    List<SpatialPointCloudFrame> frames, {
    SpatialPointProcessingSettings settings =
        const SpatialPointProcessingSettings(),
  }) {
    if (frames.isEmpty) {
      return const SpatialScanResult(
        status: SpatialScanStatus.insufficientData,
        frames: [],
        message: 'At least one validated depth frame is required.',
      );
    }
    final registered = _registration.register(frames);
    final processed = _processor.process(registered, settings: settings);
    if (processed.points.length < 3) {
      return SpatialScanResult(
        status: SpatialScanStatus.insufficientData,
        frames: List.unmodifiable(frames),
        processedCloud: processed,
        message: 'Too few validated points remain after scan cleanup.',
      );
    }
    return SpatialScanResult(
      status: SpatialScanStatus.completed,
      frames: List.unmodifiable(frames),
      processedCloud: processed,
      measurements: _measurementExtractor.extract(processed),
    );
  }
}
