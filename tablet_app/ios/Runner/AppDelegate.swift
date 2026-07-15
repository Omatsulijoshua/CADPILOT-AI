import Flutter
import UIKit
import AVFoundation
import MobileCoreServices
import simd
#if canImport(ARKit)
import ARKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let maxProjectManifestBytes = 2 * 1024 * 1024
  private var pendingFileResult: FlutterResult?
  private var pendingFileOperation: FileOperation?
  private var temporaryExportDirectory: URL?
  #if canImport(ARKit)
  private var spatialSession: ARSession?
  private var pendingDepthResult: FlutterResult?
  private var pendingDepthSessionId: String?
  private var pendingDepthMaxPoints = 12000
  private let maxDepthPointsPerFrame = 12000
  #endif

  private enum FileOperation {
    case importManifest
    case exportManifest
  }
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CadPilotSpatial") {
      let channel = FlutterMethodChannel(
        name: "cadpilot/spatial",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getCapabilities":
          result(self.spatialCapabilities())
        case "getCameraPermission":
          result(self.cameraPermission())
        case "requestCameraPermission":
          AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { result(granted ? "granted" : self.cameraPermission()) }
          }
        case "captureDepthFrame":
          self.captureDepthFrame(call.arguments, result: result)
        case "startArSession", "createFloorAnchor", "captureArScreenshot":
          result(FlutterError(
            code: "ar_renderer_unavailable",
            message: "CadPilot native AR rendering is not available in this build.",
            details: call.arguments
          ))
        case "stopArSession":
          result(false)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CadPilotFiles") {
      let channel = FlutterMethodChannel(
        name: "cadpilot/files",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "pickProjectManifest":
          self.pickProjectManifest(result)
        case "saveProjectManifest":
          self.saveProjectManifest(call.arguments, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func pickProjectManifest(_ result: @escaping FlutterResult) {
    guard beginFileOperation(.importManifest, result: result) else { return }
    let picker = UIDocumentPickerViewController(
      documentTypes: [kUTTypeJSON as String], in: .import
    )
    picker.delegate = self
    presentDocumentPicker(picker, result: result)
  }

  private func saveProjectManifest(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any],
          let content = values["content"] as? String,
          let fileName = values["fileName"] as? String,
          !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(FlutterError(code: "invalid_arguments", message: "A project manifest and file name are required.", details: nil))
      return
    }
    guard content.lengthOfBytes(using: .utf8) <= maxProjectManifestBytes else {
      result(FlutterError(code: "project_manifest_too_large", message: "Project manifest is larger than 2 MiB.", details: nil))
      return
    }
    guard beginFileOperation(.exportManifest, result: result) else { return }
    do {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let safeFileName = URL(fileURLWithPath: fileName).lastPathComponent
      let temporaryUrl = directory.appendingPathComponent(safeFileName)
      try content.write(to: temporaryUrl, atomically: true, encoding: .utf8)
      temporaryExportDirectory = directory
      let picker = UIDocumentPickerViewController(url: temporaryUrl, in: .exportToService)
      picker.delegate = self
      presentDocumentPicker(picker, result: result)
    } catch {
      finishFileOperation(FlutterError(code: "project_manifest_save_failed", message: "Could not prepare the project manifest for export.", details: error.localizedDescription))
    }
  }

  private func beginFileOperation(_ operation: FileOperation, result: @escaping FlutterResult) -> Bool {
    guard pendingFileResult == nil else {
      result(FlutterError(code: "request_in_progress", message: "A project manifest file dialog is already active.", details: nil))
      return false
    }
    pendingFileOperation = operation
    pendingFileResult = result
    return true
  }

  private func presentDocumentPicker(_ picker: UIDocumentPickerViewController, result: @escaping FlutterResult) {
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) })
      .first?.rootViewController else {
      finishFileOperation(FlutterError(code: "document_picker_unavailable", message: "The project manifest picker is not available.", details: nil))
      return
    }
    root.present(picker, animated: true)
  }

  private func finishFileOperation(_ value: Any?) {
    let result = pendingFileResult
    pendingFileResult = nil
    pendingFileOperation = nil
    if let temporaryExportDirectory {
      try? FileManager.default.removeItem(at: temporaryExportDirectory)
      self.temporaryExportDirectory = nil
    }
    result?(value)
  }

  private func cameraPermission() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return "granted"
    case .notDetermined: return "not_determined"
    case .denied: return "permanently_denied"
    case .restricted: return "restricted"
    @unknown default: return "unavailable"
    }
  }

  private func spatialCapabilities() -> [String: Any] {
    #if canImport(ARKit)
    let arSupported = ARWorldTrackingConfiguration.isSupported
    var meshSupported = false
    var sceneDepthSupported = false
    if #available(iOS 13.4, *) {
      meshSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    if #available(iOS 14.0, *) {
      sceneDepthSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }
    let lidarSupported = meshSupported && sceneDepthSupported
    let nativeDepthCaptureAvailable = lidarSupported && cameraPermission() == "granted"
    return [
      "platform": "ios", "cameraSupported": true, "arSupported": arSupported,
      "lidarSupported": lidarSupported, "sceneDepthSupported": sceneDepthSupported,
      "arRuntimeInstalled": arSupported,
      "meshReconstructionSupported": meshSupported, "planeDetectionSupported": arSupported,
      "motionTrackingSupported": arSupported,
      "captureMethod": nativeDepthCaptureAvailable ? "lidar" : (arSupported ? "camera_ar" : "manual"),
      "nativeArRendererAvailable": false, "nativeDepthCaptureAvailable": nativeDepthCaptureAvailable
    ]
    #else
    return [
      "platform": "ios", "cameraSupported": true, "arSupported": false,
      "lidarSupported": false, "sceneDepthSupported": false,
      "arRuntimeInstalled": false,
      "meshReconstructionSupported": false, "planeDetectionSupported": false,
      "motionTrackingSupported": false, "captureMethod": "manual",
      "nativeArRendererAvailable": false, "nativeDepthCaptureAvailable": false
    ]
    #endif
  }

  private func captureDepthFrame(_ arguments: Any?, result: @escaping FlutterResult) {
    #if canImport(ARKit)
    guard #available(iOS 14.0, *) else {
      result(FlutterError(code: "depth_capture_unavailable", message: "ARKit scene depth requires iOS 14 or newer.", details: nil))
      return
    }
    guard cameraPermission() == "granted" else {
      result(FlutterError(code: "depth_capture_unavailable", message: "Camera access is required for LiDAR depth capture.", details: nil))
      return
    }
    guard ARWorldTrackingConfiguration.isSupported,
          ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
      result(FlutterError(code: "depth_capture_unavailable", message: "ARKit scene depth is unavailable on this iPad.", details: nil))
      return
    }
    guard let values = arguments as? [String: Any],
          let sessionId = values["sessionId"] as? String,
          !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          values["coordinateSystem"] as? String == "right_handed_y_up_meters" else {
      result(FlutterError(code: "invalid_arguments", message: "Depth capture requires a session ID and supported coordinate system.", details: nil))
      return
    }
    guard pendingDepthResult == nil else {
      result(FlutterError(code: "request_in_progress", message: "A depth capture request is already active.", details: nil))
      return
    }
    pendingDepthResult = result
    pendingDepthSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let requested = values["maxPoints"] as? Int ?? maxDepthPointsPerFrame
    pendingDepthMaxPoints = max(3, min(requested, maxDepthPointsPerFrame))
    let session = spatialSession ?? ARSession()
    spatialSession = session
    session.delegate = self
    let configuration = ARWorldTrackingConfiguration()
    configuration.frameSemantics.insert(.sceneDepth)
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self, self.pendingDepthResult != nil else { return }
      self.finishDepthCapture(FlutterError(code: "depth_capture_unavailable", message: "No ARKit depth frame was received in time.", details: nil))
    }
    #else
    result(FlutterError(code: "depth_capture_unavailable", message: "ARKit is unavailable in this build.", details: nil))
    #endif
  }

  #if canImport(ARKit)
  @available(iOS 14.0, *)
  private func depthFrameMap(_ frame: ARFrame, sessionId: String) -> [String: Any]? {
    guard let sceneDepth = frame.sceneDepth else { return nil }
    let depthMap = sceneDepth.depthMap
    let confidenceMap = sceneDepth.confidenceMap
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
    defer {
      CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
      CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
    }
    guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
          let confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap) else { return nil }
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.stride
    let confidenceStride = CVPixelBufferGetBytesPerRow(confidenceMap)
    let imageResolution = frame.camera.imageResolution
    guard imageResolution.width > 0, imageResolution.height > 0 else { return nil }
    let intrinsics = frame.camera.intrinsics
    let scaleX = Float(width) / imageResolution.width
    let scaleY = Float(height) / imageResolution.height
    let fx = intrinsics.columns.0.x * scaleX
    let fy = intrinsics.columns.1.y * scaleY
    let cx = intrinsics.columns.2.x * scaleX
    let cy = intrinsics.columns.2.y * scaleY
    guard fx > 0, fy > 0 else { return nil }
    let requested = pendingDepthMaxPoints
    let step = max(1, Int(ceil(sqrt(Double(width * height) / Double(requested)))))
    let depthValues = depthBase.assumingMemoryBound(to: Float32.self)
    let confidenceValues = confidenceBase.assumingMemoryBound(to: UInt8.self)
    var points = [[String: Double]]()
    points.reserveCapacity(requested)
    for row in stride(from: 0, to: height, by: step) {
      for column in stride(from: 0, to: width, by: step) {
        let depth = depthValues[row * depthStride + column]
        let confidence = confidenceValues[row * confidenceStride + column]
        guard depth.isFinite, depth > 0, confidence > 0 else { continue }
        let metres = Double(depth)
        points.append([
          "x": Double((Float(column) - cx) * depth / fx),
          "y": Double(-(Float(row) - cy) * depth / fy),
          "z": -metres,
          "confidence": Double(confidence) / 2.0
        ])
        if points.count >= requested { break }
      }
      if points.count >= requested { break }
    }
    guard points.count >= 3 else { return nil }
    let transform = frame.camera.transform
    let rotation = simd_quatf(transform)
    return [
      "sessionId": sessionId,
      "frameId": "ios-\(UUID().uuidString)",
      "capturedAt": ISO8601DateFormatter().string(from: Date()),
      "coordinateSystem": "right_handed_y_up_meters",
      "sensorPose": [
        "translation": ["x": Double(transform.columns.3.x), "y": Double(transform.columns.3.y), "z": Double(transform.columns.3.z)],
        "rotation": ["x": Double(rotation.imag.x), "y": Double(rotation.imag.y), "z": Double(rotation.imag.z), "w": Double(rotation.real)]
      ],
      "points": points
    ]
  }

  private func finishDepthCapture(_ value: Any?) {
    let result = pendingDepthResult
    pendingDepthResult = nil
    pendingDepthSessionId = nil
    pendingDepthMaxPoints = maxDepthPointsPerFrame
    result?(value)
  }
  #endif
}

#if canImport(ARKit)
extension AppDelegate: ARSessionDelegate {
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard #available(iOS 14.0, *), let sessionId = pendingDepthSessionId else { return }
    if let value = depthFrameMap(frame, sessionId: sessionId) {
      DispatchQueue.main.async { self.finishDepthCapture(value) }
    }
  }
}
#endif

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let operation = pendingFileOperation else { return }
    switch operation {
    case .importManifest:
      guard let url = urls.first else {
        finishFileOperation(nil)
        return
      }
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
      }
      do {
        let data = try Data(contentsOf: url)
        guard data.count <= maxProjectManifestBytes else {
          finishFileOperation(FlutterError(code: "project_manifest_read_failed", message: "Project manifest is larger than 2 MiB.", details: nil))
          return
        }
        guard let content = String(data: data, encoding: .utf8) else {
          finishFileOperation(FlutterError(code: "project_manifest_read_failed", message: "Project manifest must be UTF-8 text.", details: nil))
          return
        }
        finishFileOperation(content)
      } catch {
        finishFileOperation(FlutterError(code: "project_manifest_read_failed", message: "Could not read the selected project manifest.", details: error.localizedDescription))
      }
    case .exportManifest:
      finishFileOperation("Project manifest saved to the selected location.")
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    switch pendingFileOperation {
    case .importManifest:
      finishFileOperation(nil)
    case .exportManifest:
      finishFileOperation(FlutterError(code: "project_manifest_save_cancelled", message: "Project manifest save was cancelled.", details: nil))
    case .none:
      break
    }
  }
}
