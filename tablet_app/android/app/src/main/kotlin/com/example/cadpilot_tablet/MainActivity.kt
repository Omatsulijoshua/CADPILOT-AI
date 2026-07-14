package com.example.cadpilot_tablet

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cadpilot/spatial")
            .setMethodCallHandler { call, result ->
                if (call.method != "getCapabilities") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val manager = packageManager
                val camera = manager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
                val gyro = manager.hasSystemFeature(PackageManager.FEATURE_SENSOR_GYROSCOPE)
                val arCoreInstalled = try {
                    manager.getPackageInfo("com.google.ar.core", 0)
                    true
                } catch (_: PackageManager.NameNotFoundException) {
                    false
                }
                result.success(
                    mapOf(
                        "platform" to "android",
                        "cameraSupported" to camera,
                        "arSupported" to (camera && gyro && arCoreInstalled),
                        "lidarSupported" to false,
                        "sceneDepthSupported" to false,
                        "meshReconstructionSupported" to false,
                        "planeDetectionSupported" to (camera && gyro && arCoreInstalled),
                        "motionTrackingSupported" to gyro,
                        "captureMethod" to if (camera && gyro && arCoreInstalled) "camera_ar" else "manual"
                    )
                )
            }
    }
}
