import Flutter
import UIKit
import AVFoundation
#if canImport(ARKit)
import ARKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CadPilotSpatial") else {
      return
    }
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
      "meshReconstructionSupported": meshSupported, "planeDetectionSupported": arSupported,
      "motionTrackingSupported": arSupported,
      "captureMethod": lidarSupported ? "lidar" : (arSupported ? "camera_ar" : "manual")
    ]
    #else
    return [
      "platform": "ios", "cameraSupported": true, "arSupported": false,
      "lidarSupported": false, "sceneDepthSupported": false,
      "meshReconstructionSupported": false, "planeDetectionSupported": false,
      "motionTrackingSupported": false, "captureMethod": "manual"
    ]
    #endif
  }
}
