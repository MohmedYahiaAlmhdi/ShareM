package com.yahia.sharem

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android Wi-Fi Direct connection negotiator.
 * File traffic is handled by Dart over TCP port 43887 after group formation.
 * This does not work on iOS or desktop and does not bypass Android permissions.
 */
class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var sink: EventChannel.EventSink? = null
    private var registeredReceiver = false
    private var pendingPermission: MethodChannel.Result? = null
    private var isEnabled = false
    private var connected = false
    private var groupOwner = false
    private var ownerAddress: String? = null
    private var discoveredPeers: List<WifiP2pDevice> = emptyList()

    private val requestCode = 4688

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    isEnabled = intent.getIntExtra(
                        WifiP2pManager.EXTRA_WIFI_STATE, -1
                    ) == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    publish(mapOf("type" to "state", "enabled" to isEnabled))
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> updatePeers()
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> updateConnection()
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> updateConnection()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "sharem/wifi_direct").setMethodCallHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,
            "sharem/wifi_direct/events").setStreamHandler(this)

        if (packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)) {
            manager = getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            channel = manager?.initialize(this, mainLooper) {
                publish(mapOf("type" to "error",
                    "message" to "Wi-Fi Direct channel disconnected. Reopen ShareM."))
            }
            val filter = IntentFilter().apply {
                addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            }
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(receiver, filter)
            }
            registeredReceiver = true
            updateConnection()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> result.success(mapOf(
                    "available" to (manager != null && channel != null),
                    "enabled" to isEnabled,
                    "connected" to connected
                ))
                "requestPermission" -> requestPermission(result)
                "refresh" -> {
                    updatePeers()
                    updateConnection()
                    result.success(null)
                }
                "discover" -> {
                    if (!requireReady(result)) return
                    if (!hasPermission()) {
                        result.error("permission", "Allow Nearby Wi-Fi first", null)
                        return
                    }
                    if (!isLocationEnabled()) {
                        result.error("location", "Turn on Location to discover nearby Wi-Fi devices", null)
                        return
                    }
                    manager!!.discoverPeers(channel!!, action(result))
                }
                "connect" -> {
                    if (!requireReady(result)) return
                    if (!hasPermission()) {
                        result.error("permission", "Nearby Wi-Fi permission denied", null)
                        return
                    }
                    val addr = call.argument<String>("address")
                    val target = discoveredPeers.firstOrNull {
                        it.deviceAddress.equals(addr, ignoreCase = true)
                    }
                    if (target == null) {
                        result.error("peer_missing",
                            "The device is not currently in the discovered list", null)
                        return
                    }
                    val config = WifiP2pConfig().apply {
                        deviceAddress = target.deviceAddress
                        // Prefer the remote peer as group owner so initiator can
                        // reach it at the known Wi-Fi Direct group IP.
                        groupOwnerIntent = 0
                    }
                    manager!!.connect(channel!!, config, action(result))
                }
                "disconnect" -> {
                    if (!requireReady(result)) return
                    manager!!.removeGroup(channel!!, action(result))
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission", e.message ?: "Permission required", null)
        } catch (e: Exception) {
            result.error("native_error", e.message ?: "Wi-Fi Direct error", null)
        }
    }

    private fun action(result: MethodChannel.Result) =
        object : WifiP2pManager.ActionListener {
            override fun onSuccess() { result.success(null) }
            override fun onFailure(reason: Int) {
                result.error("wifi_p2p_$reason",
                    "Android Wi-Fi Direct operation failed (reason $reason)", null)
            }
        }

    private fun requireReady(result: MethodChannel.Result): Boolean {
        if (manager == null || channel == null) {
            result.error("unsupported", "Wi-Fi Direct not available on this device", null)
            return false
        }
        return true
    }

    private fun permissionName(): String =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES
        else Manifest.permission.ACCESS_FINE_LOCATION

    private fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, permissionName()) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (manager == null) {
            result.success(false)
            return
        }
        if (hasPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("busy", "Permission request already open", null)
            return
        }
        pendingPermission = result
        requestPermissions(arrayOf(permissionName()), requestCode)
    }

    override fun onRequestPermissionsResult(
        code: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(code, permissions, grantResults)
        if (code == requestCode) {
            pendingPermission?.success(
                grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            pendingPermission = null
        }
    }

    private fun isLocationEnabled(): Boolean {
        val location = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        return location?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true ||
            location?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
    }

    private fun updatePeers() {
        try {
            if (manager == null || channel == null || !hasPermission()) return
            manager!!.requestPeers(channel!!) { list ->
                discoveredPeers = list.deviceList.toList()
                publish(mapOf(
                    "type" to "peers",
                    "peers" to discoveredPeers.map {
                        mapOf("name" to (it.deviceName ?: "Android device"),
                            "address" to it.deviceAddress,
                            "status" to it.status)
                    }
                ))
            }
        } catch (e: SecurityException) {
            publish(mapOf("type" to "error", "message" to "Nearby Wi-Fi permission required"))
        }
    }

    private fun updateConnection() {
        try {
            if (manager == null || channel == null) return
            manager!!.requestConnectionInfo(channel!!) { info ->
                connected = info.groupFormed
                groupOwner = info.isGroupOwner
                ownerAddress = info.groupOwnerAddress?.hostAddress
                publish(mapOf(
                    "type" to "connection",
                    "connected" to connected,
                    "groupOwner" to groupOwner,
                    "ownerIp" to (ownerAddress ?: "")
                ))
            }
        } catch (e: SecurityException) {
            publish(mapOf("type" to "error",
                "message" to "Nearby Wi-Fi permission required"))
        }
    }

    private fun publish(message: Map<String, Any>) {
        runOnUiThread { sink?.success(message) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        publish(mapOf("type" to "state", "enabled" to isEnabled))
        publish(mapOf(
            "type" to "connection", "connected" to connected,
            "groupOwner" to groupOwner, "ownerIp" to (ownerAddress ?: "")
        ))
        updatePeers()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onDestroy() {
        pendingPermission?.error("destroyed", "Activity closed", null)
        pendingPermission = null
        if (registeredReceiver) {
            try { unregisterReceiver(receiver) } catch (_: Exception) { }
            registeredReceiver = false
        }
        super.onDestroy()
    }
}
