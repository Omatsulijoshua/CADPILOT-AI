import Flutter
import UIKit
import AVFoundation
import MobileCoreServices
#if canImport(ARKit)
import ARKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let maxProjectManifestBytes = 2 * 1024 * 1024
  private var pendingFileResult: FlutterResult?
  private var pendingFileOperation: FileOperation?
  private var temporaryExportDirectory: URL?

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
          result(FlutterError(
            code: "depth_capture_unavailable",
            message: "CadPilot native depth capture is not available in this build.",
            details: call.arguments
          ))
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
    return [
      "platform": "ios", "cameraSupported": true, "arSupported": arSupported,
      "lidarSupported": lidarSupported, "sceneDepthSupported": sceneDepthSupported,
      "arRuntimeInstalled": arSupported,
      "meshReconstructionSupported": meshSupported, "planeDetectionSupported": arSupported,
      "motionTrackingSupported": arSupported,
      "captureMethod": lidarSupported ? "lidar" : (arSupported ? "camera_ar" : "manual"),
      "nativeArRendererAvailable": false, "nativeDepthCaptureAvailable": false
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
}

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
