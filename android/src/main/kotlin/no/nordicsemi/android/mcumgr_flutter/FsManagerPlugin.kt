package no.nordicsemi.android.mcumgr_flutter

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.content.Context
import android.os.Handler
import io.flutter.plugin.common.BinaryMessenger
import io.runtime.mcumgr.McuMgrCallback
import io.runtime.mcumgr.exception.McuMgrException
import io.runtime.mcumgr.managers.FsManager
import io.runtime.mcumgr.response.fs.McuMgrFsStatusResponse
import io.runtime.mcumgr.transfer.DownloadCallback
import io.runtime.mcumgr.transfer.UploadCallback
import io.runtime.mcumgr.transfer.TransferController
import io.runtime.mcumgr.transfer.FileUploader
import no.nordicsemi.android.mcumgr_flutter.logging.LoggableMcuMgrBleTransport
import no.nordicsemi.android.mcumgr_flutter.utils.StreamHandler
import no.nordicsemi.android.mcumgr_flutter.utils.FsDownloadStreamHandler
import no.nordicsemi.android.mcumgr_flutter.utils.FsUploadStreamHandler

class FsManagerPlugin(
    private val context: Context,
    private val logStreamHandler: StreamHandler,
    binaryMessenger: BinaryMessenger,
    private val mainHandler: Handler,
) : FsManagerApi {

    private val fsDownloadStreamHandler = FsDownloadStreamHandler()
    private val fsUploadStreamHandler = FsUploadStreamHandler()
    private var fsManagers: MutableMap<String, FsManager> = mutableMapOf()
    private var transports: MutableMap<String, LoggableMcuMgrBleTransport> = mutableMapOf()
    private var controllers = mutableMapOf<String, TransferController>()

    init {
        GetFileDownloadEventsStreamHandler.register(binaryMessenger, fsDownloadStreamHandler)
        GetFileUploadEventsStreamHandler.register(binaryMessenger, fsUploadStreamHandler)
        FsManagerApi.setUp(
            binaryMessenger,
            this
        )
    }

    private fun getFsManager(remoteId: String): FsManager {
        synchronized(this) {
            return fsManagers[remoteId]
                ?: run {
                    val device = BluetoothAdapter.getDefaultAdapter().getRemoteDevice(remoteId)
                    val transport = LoggableMcuMgrBleTransport(context, device, logStreamHandler)
                        .apply { setLoggingEnabled(true) }
                    val mgr = FsManager(transport)
                    fsManagers[remoteId] = mgr
                    transports[remoteId] = transport
                    mgr
                }
        }
    }

    private fun getTransport(remoteId: String): LoggableMcuMgrBleTransport? {
        // Ensure manager exists which will create transport
        getFsManager(remoteId)
        return transports[remoteId]
    }

    override fun download(remoteId: String, path: String) {
        if (controllers[remoteId] != null) {
            throw FlutterError("TODO code", "A transfer is already ongoing for $remoteId.")
        }
        val mgr = getFsManager(remoteId)
        controllers[remoteId] = mgr.fileDownload(
            path,
            object : DownloadCallback {
                override fun onDownloadProgressChanged(current: Int, total: Int, timestamp: Long) {
                    mainHandler.post {
                        fsDownloadStreamHandler.onEvent(
                            OnDownloadProgressChangedEvent(current.toLong(), total.toLong(), timestamp, remoteId, path)
                        )
                    }
                }

                override fun onDownloadFailed(p0: McuMgrException) {
                    controllers.remove(remoteId)
                    mainHandler.post {
                        fsDownloadStreamHandler.onEvent(
                            OnDownloadFailedEvent(p0.message, remoteId, path)
                        )
                    }
                }

                override fun onDownloadCanceled() {
                    controllers.remove(remoteId)
                    mainHandler.post {
                        fsDownloadStreamHandler.onEvent(
                            OnDownloadCancelledEvent(remoteId, path)
                        )
                    }
                }

                override fun onDownloadCompleted(p0: ByteArray) {
                    controllers.remove(remoteId)
                    mainHandler.post {
                        fsDownloadStreamHandler.onEvent(
                            OnDownloadCompletedEvent(remoteId, path, p0)
                        )
                    }
                }
            }
        )
    }

    override fun upload(remoteId: String, path: String, data: ByteArray) {
        if (controllers[remoteId] != null) {
            throw FlutterError("TODO code", "A transfer is already ongoing for $remoteId.")
        }
        val mgr = getFsManager(remoteId)
        val transport = getTransport(remoteId)
        
        // Request high connection priority for faster BLE parameters:
        // CONNECTION_PRIORITY_HIGH: 11.25-15ms interval, 0 latency, 20s supervision timeout
        // vs BALANCED: 30-50ms interval (default)
        // This is the same approach used by the Nordic nRF Connect Device Manager app
        transport?.requestConnPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
        
        // Disable BLE logging during transfer to reduce overhead
        transport?.setLoggingEnabled(false)
        
        // Set the upload MTU to the transport's max packet length for SMP reassembly support
        // This allows sending larger packets if the device supports reassembly (NCS 2.0+)
        // The maxPacketLength is auto-detected by McuMgrBleTransport during connection
        val maxPacketLength = transport?.maxPacketLength ?: 0
        if (maxPacketLength > 0) {
            mgr.setUploadMtu(maxPacketLength)
        }
        
        // Use FileUploader with window capacity for SMP pipelining - significantly faster uploads
        // windowCapacity: Number of packets to send without waiting for ACK (default 3 for good balance)
        // memoryAlignment: Byte alignment required by device (4 for Nordic devices)
        // This is the same approach used by the Nordic nRF Connect Device Manager app
        val uploader = FileUploader(mgr, path, data, 3, 4)
        
        controllers[remoteId] = uploader.uploadAsync(
            object : UploadCallback {
                override fun onUploadProgressChanged(current: Int, total: Int, timestamp: Long) {
                    mainHandler.post {
                        fsUploadStreamHandler.onEvent(
                            OnUploadProgressChangedEvent(current.toLong(), total.toLong(), timestamp, remoteId, path)
                        )
                    }
                }

                override fun onUploadFailed(p0: McuMgrException) {
                    controllers.remove(remoteId)
                    // Re-enable logging after transfer
                    transport?.setLoggingEnabled(true)
                    mainHandler.post {
                        fsUploadStreamHandler.onEvent(
                            OnUploadFailedEvent(p0.message, remoteId, path)
                        )
                    }
                }

                override fun onUploadCanceled() {
                    controllers.remove(remoteId)
                    // Re-enable logging after transfer
                    transport?.setLoggingEnabled(true)
                    mainHandler.post {
                        fsUploadStreamHandler.onEvent(
                            OnUploadCancelledEvent(remoteId, path)
                        )
                    }
                }

                override fun onUploadCompleted() {
                    controllers.remove(remoteId)
                    // Re-enable logging after transfer
                    transport?.setLoggingEnabled(true)
                    mainHandler.post {
                        fsUploadStreamHandler.onEvent(
                            OnUploadCompletedEvent(remoteId, path)
                        )
                    }
                }
            }
        )
    }

    override fun pauseTransfer(remoteId: String) {
        controllers[remoteId]?.pause()
    }

    override fun continueTransfer(remoteId: String) {
        controllers[remoteId]?.resume()
    }

    override fun cancelTransfer(remoteId: String) {
        controllers[remoteId]?.cancel()
    }

    override fun status(remoteId: String, path: String, callback: (Result<Long>) -> Unit) {
        val mgr = getFsManager(remoteId)
        mgr.status(
            path,
            object : McuMgrCallback<McuMgrFsStatusResponse> {
                override fun onResponse(p0: McuMgrFsStatusResponse) {
                    callback(Result.success(p0.len.toLong()))
                }

                override fun onError(p0: McuMgrException) {
                    callback(Result.failure(p0))
                }
            }
        )
    }

    override fun kill(remoteId: String) {
        transports.remove(remoteId)
        fsManagers.remove(remoteId)?.transporter?.release()
    }
}