package no.nordicsemi.android.mcumgr_flutter

import android.bluetooth.BluetoothAdapter
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.runtime.mcumgr.McuMgrCallback
import io.runtime.mcumgr.exception.McuMgrException
import io.runtime.mcumgr.managers.DefaultManager
import io.runtime.mcumgr.response.dflt.McuMgrOsResponse
import no.nordicsemi.android.mcumgr_flutter.logging.LoggableMcuMgrBleTransport
import no.nordicsemi.android.mcumgr_flutter.utils.StreamHandler

class OsManagerPlugin(
    private val context: Context,
    private val logStreamHandler: StreamHandler,
    binaryMessenger: BinaryMessenger,
) : OsManagerApi {

    private var managers: MutableMap<String, DefaultManager> = mutableMapOf()
    private var transports: MutableMap<String, LoggableMcuMgrBleTransport> = mutableMapOf()

    init {
        OsManagerApi.setUp(binaryMessenger, this)
    }

    private fun getManager(remoteId: String): DefaultManager {
        synchronized(this) {
            return managers[remoteId]
                ?: run {
                    val device = BluetoothAdapter.getDefaultAdapter().getRemoteDevice(remoteId)
                    val transport = LoggableMcuMgrBleTransport(context, device, logStreamHandler)
                        .apply { setLoggingEnabled(true) }
                    val mgr = DefaultManager(transport)
                    managers[remoteId] = mgr
                    transports[remoteId] = transport
                    mgr
                }
        }
    }

    override fun reset(remoteId: String, callback: (Result<Unit>) -> Unit) {
        val mgr = getManager(remoteId)
        mgr.reset(object : McuMgrCallback<McuMgrOsResponse> {
            override fun onResponse(p0: McuMgrOsResponse) {
                // Clean up after successful reset since the device is rebooting
                kill(remoteId)
                callback(Result.success(Unit))
            }

            override fun onError(p0: McuMgrException) {
                callback(Result.failure(p0))
            }
        })
    }

    override fun kill(remoteId: String) {
        transports.remove(remoteId)
        managers.remove(remoteId)?.transporter?.release()
    }
}
