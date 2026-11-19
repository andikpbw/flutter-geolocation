package id.humanize.geolocator_flutter

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

class GeolocatorFlutterPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private companion object {
        const val METHOD_CHANNEL = "id.humanize.geolocator_flutter/methods"
        const val POSITION_CHANNEL = "id.humanize.geolocator_flutter/positions"
        const val SERVICE_CHANNEL = "id.humanize.geolocator_flutter/service_status"
        const val PERMISSION_REQUEST_CODE = 8421
        const val PREFS_NAME = "id.humanize.geolocator_flutter.prefs"
        const val KEY_PERMISSION_REQUESTED = "permission_requested"
    }

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var positionChannel: EventChannel
    private lateinit var serviceChannel: EventChannel

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: Result? = null
    private var activeLocationListener: LocationListener? = null
    private var serviceReceiver: BroadcastReceiver? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        positionChannel = EventChannel(binding.binaryMessenger, POSITION_CHANNEL)
        positionChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                @Suppress("UNCHECKED_CAST")
                val args = arguments as? Map<String, Any?> ?: emptyMap()
                startPositionStream(args, events)
            }

            override fun onCancel(arguments: Any?) {
                stopPositionStream()
            }
        })

        serviceChannel = EventChannel(binding.binaryMessenger, SERVICE_CHANNEL)
        serviceChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                startServiceStatusStream(events)
            }

            override fun onCancel(arguments: Any?) {
                stopServiceStatusStream()
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopPositionStream()
        stopServiceStatusStream()
        methodChannel.setMethodCallHandler(null)
        positionChannel.setStreamHandler(null)
        serviceChannel.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isLocationServiceEnabled" -> result.success(isLocationEnabled())
            "checkPermission" -> result.success(currentPermissionStatus())
            "requestPermission" -> {
                val always = call.argument<Boolean>("always") ?: false
                requestLocationPermission(always, result)
            }
            "getLastKnownPosition" -> getLastKnownPosition(result)
            "getCurrentPosition" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                getCurrentPosition(args, result)
            }
            "openAppSettings" -> result.success(openAppSettings())
            "openLocationSettings" -> result.success(openLocationSettings())
            else -> result.notImplemented()
        }
    }

    private fun locationManager(): LocationManager? {
        return context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
    }

    private fun isLocationEnabled(): Boolean {
        val lm = locationManager() ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            lm.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }
    }

    private fun hasForegroundPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun hasBackgroundPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return hasForegroundPermission()
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun currentPermissionStatus(): String {
        if (hasForegroundPermission()) {
            return if (hasBackgroundPermission()) "always" else "whileInUse"
        }
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val wasRequested = prefs.getBoolean(KEY_PERMISSION_REQUESTED, false)
        val act = activity
        if (wasRequested && act != null) {
            val showFine = ActivityCompat.shouldShowRequestPermissionRationale(
                act,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
            val showCoarse = ActivityCompat.shouldShowRequestPermissionRationale(
                act,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
            if (!showFine && !showCoarse) {
                return "deniedForever"
            }
        }
        return "denied"
    }

    private fun requestLocationPermission(always: Boolean, result: Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "An active Android Activity is required to request permissions.", null)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_REQUEST_IN_PROGRESS", "A permission request is already in progress.", null)
            return
        }

        val permissions = mutableListOf<String>()
        if (!hasForegroundPermission()) {
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
            permissions.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        } else if (always && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !hasBackgroundPermission()) {
            permissions.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }

        if (permissions.isEmpty()) {
            result.success(currentPermissionStatus())
            return
        }

        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PERMISSION_REQUESTED, true)
            .apply()

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(act, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val pending = pendingPermissionResult ?: return false
        pendingPermissionResult = null
        pending.success(currentPermissionStatus())
        return true
    }

    @Suppress("MissingPermission")
    private fun getLastKnownPosition(result: Result) {
        if (!hasForegroundPermission()) {
            result.error("PERMISSION_DENIED", "Location permission has not been granted.", null)
            return
        }
        val lm = locationManager()
        if (lm == null) {
            result.success(null)
            return
        }
        var best: Location? = null
        for (provider in lm.getProviders(true)) {
            val candidate = try {
                lm.getLastKnownLocation(provider)
            } catch (_: SecurityException) {
                null
            } ?: continue
            if (best == null || candidate.time > best.time ||
                (candidate.time == best.time && candidate.accuracy < best.accuracy)
            ) {
                best = candidate
            }
        }
        result.success(best?.let { locationToMap(it) })
    }

    private fun selectBestProvider(lm: LocationManager, accuracy: String): String? {
        val preferHigh = accuracy == "high" || accuracy == "best" || accuracy == "navigation"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            lm.allProviders.contains(LocationManager.FUSED_PROVIDER) &&
            lm.isProviderEnabled(LocationManager.FUSED_PROVIDER)
        ) {
            return LocationManager.FUSED_PROVIDER
        }
        if (preferHigh && lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            return LocationManager.GPS_PROVIDER
        }
        if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            return LocationManager.NETWORK_PROVIDER
        }
        if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            return LocationManager.GPS_PROVIDER
        }
        if (lm.isProviderEnabled(LocationManager.PASSIVE_PROVIDER)) {
            return LocationManager.PASSIVE_PROVIDER
        }
        return null
    }

    @Suppress("MissingPermission")
    private fun getCurrentPosition(args: Map<String, Any?>, result: Result) {
        if (!isLocationEnabled()) {
            result.error("SERVICE_DISABLED", "Location services are disabled.", null)
            return
        }
        if (!hasForegroundPermission()) {
            result.error("PERMISSION_DENIED", "Location permission has not been granted.", null)
            return
        }
        val lm = locationManager()
        if (lm == null) {
            result.error("UNSUPPORTED", "LocationManager is unavailable.", null)
            return
        }
        val accuracy = args["accuracy"] as? String ?: "high"
        val timeoutMs = (args["timeoutMs"] as? Number)?.toLong() ?: 30_000L
        val provider = selectBestProvider(lm, accuracy)
        if (provider == null) {
            result.error("SERVICE_DISABLED", "No active location providers available.", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val signal = CancellationSignal()
            var completed = false
            val timeoutRunnable = Runnable {
                if (!completed) {
                    completed = true
                    signal.cancel()
                    result.error("TIMEOUT", "Timed out waiting for location fix.", null)
                }
            }
            mainHandler.postDelayed(timeoutRunnable, timeoutMs)
            lm.getCurrentLocation(provider, signal, ContextCompat.getMainExecutor(context)) { loc ->
                if (!completed) {
                    completed = true
                    mainHandler.removeCallbacks(timeoutRunnable)
                    if (loc != null) {
                        result.success(locationToMap(loc))
                    } else {
                        result.error("TIMEOUT", "Unable to acquire a current location fix.", null)
                    }
                }
            }
        } else {
            var completed = false
            lateinit var listener: LocationListener
            val timeoutRunnable = Runnable {
                if (!completed) {
                    completed = true
                    lm.removeUpdates(listener)
                    result.error("TIMEOUT", "Timed out waiting for location fix.", null)
                }
            }
            listener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    if (!completed) {
                        completed = true
                        mainHandler.removeCallbacks(timeoutRunnable)
                        lm.removeUpdates(this)
                        result.success(locationToMap(location))
                    }
                }

                @Deprecated("Deprecated in API 29")
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                override fun onProviderEnabled(provider: String) {}
                override fun onProviderDisabled(provider: String) {}
            }
            mainHandler.postDelayed(timeoutRunnable, timeoutMs)
            lm.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
        }
    }

    @Suppress("MissingPermission")
    private fun startPositionStream(args: Map<String, Any?>, events: EventChannel.EventSink) {
        if (!isLocationEnabled()) {
            events.error("SERVICE_DISABLED", "Location services are disabled.", null)
            return
        }
        if (!hasForegroundPermission()) {
            events.error("PERMISSION_DENIED", "Location permission has not been granted.", null)
            return
        }
        val lm = locationManager()
        if (lm == null) {
            events.error("UNSUPPORTED", "LocationManager is unavailable.", null)
            return
        }
        stopPositionStream()

        val accuracy = args["accuracy"] as? String ?: "high"
        val minTimeMs = (args["timeIntervalMs"] as? Number)?.toLong()?.coerceAtLeast(0L) ?: 1000L
        val minDistanceM = (args["distanceFilterMeters"] as? Number)?.toFloat()?.coerceAtLeast(0f) ?: 0f
        val provider = selectBestProvider(lm, accuracy)
        if (provider == null) {
            events.error("SERVICE_DISABLED", "No active location providers available.", null)
            return
        }

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                events.success(locationToMap(location))
            }

            @Deprecated("Deprecated in API 29")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {
                if (!isLocationEnabled()) {
                    events.error("SERVICE_DISABLED", "Location services were disabled.", null)
                }
            }
        }
        activeLocationListener = listener
        lm.requestLocationUpdates(provider, minTimeMs, minDistanceM, listener, Looper.getMainLooper())
    }

    private fun stopPositionStream() {
        val listener = activeLocationListener ?: return
        activeLocationListener = null
        locationManager()?.removeUpdates(listener)
    }

    private fun startServiceStatusStream(events: EventChannel.EventSink) {
        stopServiceStatusStream()
        events.success(if (isLocationEnabled()) "enabled" else "disabled")
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                events.success(if (isLocationEnabled()) "enabled" else "disabled")
            }
        }
        serviceReceiver = receiver
        val filter = IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    private fun stopServiceStatusStream() {
        val receiver = serviceReceiver ?: return
        serviceReceiver = null
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // Receiver was already unregistered.
        }
    }

    private fun openAppSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", context.packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openLocationSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun locationToMap(location: Location): Map<String, Any?> {
        val isMocked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            location.isMock
        } else {
            @Suppress("DEPRECATION")
            location.isFromMockProvider
        }
        val altAccuracy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasVerticalAccuracy()) {
            location.verticalAccuracyMeters.toDouble()
        } else {
            0.0
        }
        val headingAccuracy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasBearingAccuracy()) {
            location.bearingAccuracyDegrees.toDouble()
        } else {
            0.0
        }
        val speedAccuracy = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasSpeedAccuracy()) {
            location.speedAccuracyMetersPerSecond.toDouble()
        } else {
            0.0
        }
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "timestamp" to location.time,
            "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else 0.0,
            "altitude" to if (location.hasAltitude()) location.altitude else 0.0,
            "altitudeAccuracy" to altAccuracy,
            "heading" to if (location.hasBearing()) location.bearing.toDouble() else 0.0,
            "headingAccuracy" to headingAccuracy,
            "speed" to if (location.hasSpeed()) location.speed.toDouble() else 0.0,
            "speedAccuracy" to speedAccuracy,
            "isMocked" to isMocked,
            "provider" to (location.provider ?: "unknown")
        )
    }
}
