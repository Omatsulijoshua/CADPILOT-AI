package com.example.cadpilot_tablet

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val cameraRequestCode = 7401
    private var pendingCameraResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cadpilot/spatial")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCapabilities" -> result.success(spatialCapabilities())
                    "getCameraPermission" -> result.success(cameraPermission())
                    "requestCameraPermission" -> requestCameraPermission(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun spatialCapabilities(): Map<String, Any> {
        val manager = packageManager
        val camera = manager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
        val gyro = manager.hasSystemFeature(PackageManager.FEATURE_SENSOR_GYROSCOPE)
        val arCoreInstalled = try {
            manager.getPackageInfo("com.google.ar.core", 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
        val ar = camera && gyro && arCoreInstalled
        return mapOf(
            "platform" to "android",
            "cameraSupported" to camera,
            "arSupported" to ar,
            "lidarSupported" to false,
            "sceneDepthSupported" to false,
            "meshReconstructionSupported" to false,
            "planeDetectionSupported" to ar,
            "motionTrackingSupported" to gyro,
            "captureMethod" to if (ar) "camera_ar" else "manual"
        )
    }

    private fun cameraPermission(): String = when {
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED -> "granted"
        ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.CAMERA) ->
            "denied"
        else -> "not_determined"
    }

    private fun requestCameraPermission(result: MethodChannel.Result) {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
            result.success("unavailable")
            return
        }
        if (cameraPermission() == "granted") {
            result.success("granted")
            return
        }
        if (pendingCameraResult != null) {
            result.error("request_in_progress", "A camera permission request is already active.", null)
            return
        }
        pendingCameraResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CAMERA),
            cameraRequestCode
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != cameraRequestCode) return
        val status = if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            "granted"
        } else if (!ActivityCompat.shouldShowRequestPermissionRationale(
                this,
                Manifest.permission.CAMERA
            )) {
            "permanently_denied"
        } else {
            "denied"
        }
        pendingCameraResult?.success(status)
        pendingCameraResult = null
    }
}
