import Flutter
import iOSMcuManagerLibrary
import CoreBluetooth

class FsManagerPlugin : FsManagerApi {
    private var managers: [String : FileSystemManager] = [:]
    private var downloadDelegates: [String : FileDownloadDelegate] = [:]
    private var uploadDelegates: [String : FileUploadDelegate] = [:]
    private let centralManager: CBCentralManager
    private let downloadStreamHandler = DownloadStreamHandler()
    private let uploadStreamHandler = UploadStreamHandler()

    init(
        centralManager: CBCentralManager,
        messenger: FlutterBinaryMessenger
    ) {
        self.centralManager = centralManager
        
        FsManagerApiSetup.setUp(binaryMessenger: messenger, api: self)
        GetFileDownloadEventsStreamHandler.register(with: messenger, streamHandler: downloadStreamHandler)
        GetFileUploadEventsStreamHandler.register(with: messenger, streamHandler: uploadStreamHandler)
    }
    
    private func getManager(_ remoteId: String) throws -> FileSystemManager {
        var mgr = managers[remoteId]
        guard let uuid = UUID(uuidString: remoteId) else {
            throw PigeonError(code: "TODO Code", message: "remoteId not a valid UUID.", details: nil)
        }
        guard let pheripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first else {
            throw PigeonError(code: "TODO Code", message: "Was not able to retrieve pheripheral for UUID \(uuid)", details: nil)
        }
        if mgr == nil {
            mgr = FileSystemManager(transport: McuMgrBleTransport(pheripheral))
            managers[remoteId] = mgr
        }
        return mgr!
    }
    
    /// Start downloading a file.
    /// Only a single file is downloadable at a time.
    /// If a file download is already on-going, this call will throw an [Exception].
    func download(remoteId: String, path: String) throws {
        let mgr = try getManager(remoteId)
        let delegate = FileDownloadDelegateImpl(
            streamHandler: downloadStreamHandler,
            remoteId: remoteId,
            path: path
        )
        guard mgr.download(name: path, delegate: delegate) else {
            throw PigeonError(code: "TODO Code", message: "Download failed to successfully start. Likely due to ongoing transaction.", details: nil)
        }
        downloadDelegates[remoteId] = delegate
    }
    
    /// Start uploading a file.
    /// Only a single transfer can be active at a time.
    /// If a transfer is already on-going, this call will throw an [Exception].
    func upload(remoteId: String, path: String, data: FlutterStandardTypedData) throws {
        let mgr = try getManager(remoteId)
        let delegate = FileUploadDelegateImpl(
            streamHandler: uploadStreamHandler,
            remoteId: remoteId,
            path: path
        )
        guard mgr.upload(name: path, data: data.data, delegate: delegate) else {
            throw PigeonError(code: "TODO Code", message: "Upload failed to successfully start. Likely due to ongoing transaction.", details: nil)
        }
        uploadDelegates[remoteId] = delegate
    }
    
    /// Pause an ongoing download
    func pauseTransfer(remoteId: String) throws {
        managers[remoteId]?.pauseTransfer()
    }
    
    /// Resume an ongoing download
    func continueTransfer(remoteId: String) throws {
        managers[remoteId]?.continueTransfer()
    }
    
    /// Cancel an ongoing download
    func cancelTransfer(remoteId: String) throws {
        managers[remoteId]?.cancelTransfer()
    }
    
    func status(remoteId: String, path: String, completion: @escaping (Result<Int64, any Error>) -> Void) {
        do {
            let mgr = try getManager(remoteId)
            mgr.status(
                name: path
            ) { response, error in
                if error != nil {
                    completion(Result.failure(error!))
                } else if response == nil || response?.len == nil {
                    completion(Result.failure(PigeonError(code: "TODO", message: "Unexpected error: nil response/response params", details: nil)))
                } else {
                    completion(Result.success(Int64(bitPattern: (response?.len)!)))
                }
            }
        } catch {
            completion(Result.failure(error))
        }
    }
    
    /// Kill the FsManager instance on the native platform.
    func kill(remoteId: String) throws {
        managers.removeValue(forKey: remoteId)?.transport.close()
    }
}

private class FileDownloadDelegateImpl : FileDownloadDelegate {
    private let streamHandler: DownloadStreamHandler
    private let remoteId: String
    private let path: String
    
    init(
        streamHandler: DownloadStreamHandler,
        remoteId: String,
        path: String
    ) {
        self.streamHandler = streamHandler
        self.remoteId = remoteId
        self.path = path
    }
    
    /// Called when a packet of file data has been sent successfully.
    ///
    /// - parameter bytesDownloaded: The total number of file bytes received so far.
    /// - parameter fileSize:        The overall size of the file being downloaded.
    /// - parameter timestamp:       The time this response packet was received.
    func downloadProgressDidChange(bytesDownloaded: Int, fileSize: Int, timestamp: Date) {
        streamHandler.onEvent(
            OnDownloadProgressChangedEvent(
                current: Int64(bytesDownloaded),
                total: Int64(fileSize),
                timestamp: timestamp.asInt64,
                remoteId: remoteId,
                path: path
            )
        )
    }
    
    /// Called when an file download has failed.
    ///
    /// - parameter error: The error that caused the download to fail.
    func downloadDidFail(with error: Error) {
        streamHandler.onEvent(
            OnDownloadFailedEvent(cause: error.localizedDescription, remoteId: remoteId, path: path)
        )
    }
    
    /// Called when the download has been cancelled.
    func downloadDidCancel() {
        streamHandler.onEvent(
            OnDownloadCancelledEvent(remoteId: remoteId, path: path)
        )
    }
    
    /// Called when the download has finished successfully.
    ///
    /// - parameter name: The file name.
    /// - parameter data: The file content.
    func download(of name: String, didFinish data: Data) {
        streamHandler.onEvent(
            OnDownloadCompletedEvent(remoteId: remoteId, path: path, bytes: FlutterStandardTypedData(bytes: data))
        )
    }
}

private class DownloadStreamHandler : GetFileDownloadEventsStreamHandler {

    private var sink: PigeonEventSink<DownloadCallbackEvent>? = nil
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<DownloadCallbackEvent>) {
        self.sink = sink
    }
    
    override func onCancel(withArguments arguments: Any?) {
        self.sink = nil
    }
    
    func onEvent(_ event: DownloadCallbackEvent) {
        sink?.success(event)
    }
}

private class FileUploadDelegateImpl : FileUploadDelegate {
    private let streamHandler: UploadStreamHandler
    private let remoteId: String
    private let path: String
    
    init(
        streamHandler: UploadStreamHandler,
        remoteId: String,
        path: String
    ) {
        self.streamHandler = streamHandler
        self.remoteId = remoteId
        self.path = path
    }
    
    /// Called when a packet of file data has been sent successfully.
    ///
    /// - parameter bytesSent:  The total number of file bytes sent so far.
    /// - parameter fileSize:   The overall size of the file being uploaded.
    /// - parameter timestamp:  The time this response packet was received.
    func uploadProgressDidChange(bytesSent: Int, fileSize: Int, timestamp: Date) {
        streamHandler.onEvent(
            OnUploadProgressChangedEvent(
                current: Int64(bytesSent),
                total: Int64(fileSize),
                timestamp: timestamp.asInt64,
                remoteId: remoteId,
                path: path
            )
        )
    }
    
    /// Called when a file upload has failed.
    ///
    /// - parameter error: The error that caused the upload to fail.
    func uploadDidFail(with error: Error) {
        streamHandler.onEvent(
            OnUploadFailedEvent(cause: error.localizedDescription, remoteId: remoteId, path: path)
        )
    }
    
    /// Called when the upload has been cancelled.
    func uploadDidCancel() {
        streamHandler.onEvent(
            OnUploadCancelledEvent(remoteId: remoteId, path: path)
        )
    }
    
    /// Called when the upload has finished successfully.
    func uploadDidFinish() {
        streamHandler.onEvent(
            OnUploadCompletedEvent(remoteId: remoteId, path: path)
        )
    }
}

private class UploadStreamHandler : GetFileUploadEventsStreamHandler {

    private var sink: PigeonEventSink<UploadCallbackEvent>? = nil
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<UploadCallbackEvent>) {
        self.sink = sink
    }
    
    override func onCancel(withArguments arguments: Any?) {
        self.sink = nil
    }
    
    func onEvent(_ event: UploadCallbackEvent) {
        sink?.success(event)
    }
}
