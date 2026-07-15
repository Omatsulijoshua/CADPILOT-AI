package com.omatsulijoshua.cadpilot

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val cameraRequestCode = 7401
    private val projectImportRequestCode = 7402
    private val projectExportRequestCode = 7403
    private val maxProjectManifestBytes = 2 * 1024 * 1024
    private var pendingCameraResult: MethodChannel.Result? = null
    private var pendingProjectImportResult: MethodChannel.Result? = null
    private var pendingProjectExportResult: MethodChannel.Result? = null
    private var pendingProjectExportContent: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cadpilot/spatial")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCapabilities" -> spatialCapabilities(result)
                    "getCameraPermission" -> result.success(cameraPermission())
                    "requestCameraPermission" -> requestCameraPermission(result)
                    "requestArRuntimeInstall" -> requestArRuntimeInstall(result)
                    "startArSession",
                    "createFloorAnchor",
                    "captureArScreenshot" -> result.error(
                        "ar_renderer_unavailable",
                        "CadPilot native AR rendering is not available in this build.",
                        call.arguments
                    )
                    "captureDepthFrame" -> result.error(
                        "depth_capture_unavailable",
                        "CadPilot native depth capture is not available on this device/build.",
                        call.arguments
                    )
                    "stopArSession" -> result.success(false)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cadpilot/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickProjectManifest" -> pickProjectManifest(result)
                    "saveProjectManifest" -> saveProjectManifest(call.arguments, result)
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
                "nativeArRendererAvailable" to false,
                "nativeDepthCaptureAvailable" to false
            )
            runOnUiThread { result.success(capabilities) }
        }
    }

    private fun requestArRuntimeInstall(result: MethodChannel.Result) {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
            result.success("unavailable")
            return
        }
        try {
            when (ArCoreApk.getInstance().requestInstall(this, true)) {
                ArCoreApk.InstallStatus.INSTALLED -> result.success("installed")
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> result.success("install_requested")
            }
        } catch (_: UnavailableUserDeclinedInstallationException) {
            result.success("declined")
        } catch (error: Exception) {
            result.error(
                "ar_runtime_install_unavailable",
                "The AR runtime cannot be installed on this device.",
                error.javaClass.simpleName
            )
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

    private fun pickProjectManifest(result: MethodChannel.Result) {
        if (pendingProjectImportResult != null) {
            result.error("request_in_progress", "A project manifest picker is already active.", null)
            return
        }
        pendingProjectImportResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/json"))
        }
        startActivityForResult(intent, projectImportRequestCode)
    }

    private fun saveProjectManifest(arguments: Any?, result: MethodChannel.Result) {
        if (pendingProjectExportResult != null) {
            result.error("request_in_progress", "A project manifest save dialog is already active.", null)
            return
        }
        val values = arguments as? Map<*, *>
        val content = values?.get("content") as? String
        val fileName = values?.get("fileName") as? String
        if (content == null || fileName.isNullOrBlank()) {
            result.error("invalid_arguments", "A project manifest and file name are required.", null)
            return
        }
        if (content.toByteArray(StandardCharsets.UTF_8).size > maxProjectManifestBytes) {
            result.error("project_manifest_too_large", "Project manifest is larger than 2 MiB.", null)
            return
        }

        pendingProjectExportResult = result
        pendingProjectExportContent = content
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        startActivityForResult(intent, projectExportRequestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == projectExportRequestCode) {
            completeProjectExport(resultCode, data)
            return
        }
        if (requestCode != projectImportRequestCode) return

        val pendingResult = pendingProjectImportResult ?: return
        pendingProjectImportResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingResult.success(null)
            return
        }

        try {
            val content = contentResolver.openInputStream(uri)?.use { input ->
                val bytes = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (bytes.size() + read > maxProjectManifestBytes) {
                        throw IllegalArgumentException("Project manifest is larger than 2 MiB.")
                    }
                    bytes.write(buffer, 0, read)
                }
                bytes.toString(StandardCharsets.UTF_8.name())
            } ?: throw IllegalArgumentException("Could not read selected project manifest.")
            pendingResult.success(content)
        } catch (error: Exception) {
            pendingResult.error(
                "project_manifest_read_failed",
                "Could not read the selected project manifest.",
                error.message
            )
        }
    }

    private fun completeProjectExport(resultCode: Int, data: Intent?) {
        val pendingResult = pendingProjectExportResult ?: return
        val content = pendingProjectExportContent
        pendingProjectExportResult = null
        pendingProjectExportContent = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingResult.error("project_manifest_save_cancelled", "Project manifest save was cancelled.", null)
            return
        }
        if (content == null) {
            pendingResult.error("project_manifest_save_failed", "Project manifest content was unavailable.", null)
            return
        }
        try {
            contentResolver.openOutputStream(uri)?.bufferedWriter(StandardCharsets.UTF_8).use { writer ->
                writer?.write(content)
            } ?: throw IllegalArgumentException("Could not write the selected project manifest.")
            pendingResult.success("Project manifest saved to the selected location.")
        } catch (error: Exception) {
            pendingResult.error(
                "project_manifest_save_failed",
                "Could not save the selected project manifest.",
                error.message
            )
        }
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
