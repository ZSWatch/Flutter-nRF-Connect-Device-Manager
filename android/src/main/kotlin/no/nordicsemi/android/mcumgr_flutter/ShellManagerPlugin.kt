package no.nordicsemi.android.mcumgr_flutter

import android.bluetooth.BluetoothAdapter
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.runtime.mcumgr.McuMgrCallback
import io.runtime.mcumgr.exception.McuMgrException
import io.runtime.mcumgr.managers.ShellManager
import io.runtime.mcumgr.response.shell.McuMgrExecResponse
import no.nordicsemi.android.mcumgr_flutter.logging.LoggableMcuMgrBleTransport
import no.nordicsemi.android.mcumgr_flutter.utils.StreamHandler

class ShellManagerPlugin(
    private val context: Context,
    private val logStreamHandler: StreamHandler,
    binaryMessenger: BinaryMessenger,
) : ShellManagerApi {

    private var managers: MutableMap<String, ShellManager> = mutableMapOf()
    private var transports: MutableMap<String, LoggableMcuMgrBleTransport> = mutableMapOf()

    init {
        ShellManagerApi.setUp(binaryMessenger, this)
    }

    private fun getManager(remoteId: String): ShellManager {
        synchronized(this) {
            return managers[remoteId]
                ?: run {
                    val device = BluetoothAdapter.getDefaultAdapter().getRemoteDevice(remoteId)
                    val transport = LoggableMcuMgrBleTransport(context, device, logStreamHandler)
                        .apply { setLoggingEnabled(true) }
                    val mgr = ShellManager(transport)
                    managers[remoteId] = mgr
                    transports[remoteId] = transport
                    mgr
                }
        }
    }

    override fun execute(remoteId: String, command: String, callback: (Result<ShellResponse>) -> Unit) {
        val mgr = getManager(remoteId)
        val parts = command.trim().split(Regex("\\s+"))
        val cmd = parts.first()
        val argv = if (parts.size > 1) parts.drop(1).toTypedArray() else null
        mgr.exec(cmd, argv, object : McuMgrCallback<McuMgrExecResponse> {
            override fun onResponse(response: McuMgrExecResponse) {
                val shellResponse = ShellResponse(
                    output = response.o ?: "",
                    returnCode = response.ret.toLong()
                )
                callback(Result.success(shellResponse))
            }

            override fun onError(exception: McuMgrException) {
                callback(Result.failure(exception))
            }
        })
    }

    override fun kill(remoteId: String) {
        transports.remove(remoteId)
        managers.remove(remoteId)?.transporter?.release()
    }
}
