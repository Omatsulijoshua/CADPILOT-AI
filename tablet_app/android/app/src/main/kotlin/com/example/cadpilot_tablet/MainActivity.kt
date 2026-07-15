package com.example.cadpilot_tablet

import android.Manifest
import android.content.pm.PackageManager
import com.google.ar.core.ArCoreApk
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
                    "getCapabilities" -> spatialCapabilities(result)
                    "getCameraPermission" -> result.success(cameraPermission())
                    "requestCameraPermission" -> requestCameraPermission(result)
                    "startArSession",
                    "createFloorAnchor",
                    "captureArScreenshot" -> result.error(
                        "ar_renderer_unavailable",
                        "CadPilot native AR rendering is not available in this build.",
                        call.arguments
                    )
                    "stopArSession" -> result.success(false)
                    else -> result.notImplemented()
                }
            }
    }

    private fun spatialCapabilities(result: MethodChannel.Result) {
        val manager = packageManager
        val camera = manager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
        val gyro = manager.hasSystemFeature(PackageManager.FEATURE_SENSOR_GYROSCOPE)
        ArCoreApk.getInstance().checkAvailabilityAsync(this) { availability ->
            val ar = camera && gyro && availability.isSupported
            val capabilities = mapOf(
                "platform" to "android",
                "cameraSupported" to camera,
                "arSupported" to ar,
                "arRuntimeInstalled" to (availability == ArCoreApk.Availability.SUPPORTED_INSTALLED),
                "lidarSupported" to false,
                "sceneDepthSupported" to false,
                "meshReconstructionSupported" to false,
                "planeDetectionSupported" to ar,
                "motionTrackingSupported" to gyro,
                "captureMethod" to if (ar) "camera_ar" else "manual",
                "nativeArRendererAvailable" to false
            )
            runOnUiThread { result.success(capabilities) }
        }
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
