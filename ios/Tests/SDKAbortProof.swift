import Foundation
import iOSMcuManagerLibrary

/// Compiles/runs against the entire actual SDK, with a transport that never
/// opens Bluetooth. Cancelled callbacks may remain outstanding indefinitely.
private final class HeldTransport: McuMgrTransport {
  var mtu: Int! = 244
  var sends = 0
  var callbacks: [() -> Void] = []
  var replies: [(Data) -> Void] = []
  var packets: [Data] = []
  var removedObservers = 0
  func getScheme() -> McuMgrScheme { .ble }
  func send<T: McuMgrResponse>(data: Data, timeout: Int, callback: @escaping McuMgrCallback<T>) {
    sends += 1; packets.append(data)
    callbacks.append { callback(nil, McuMgrTransportError.disconnected) }
    replies.append { data in
      let response: T = try! McuMgrResponse.buildResponse(scheme: .ble, data: data)
      callback(response, nil)
    }
  }
  private enum FileCommand: UInt8 { case file = 0 }
  func replyOffset(_ index: Int, _ offset: UInt64) {
    let header = try! McuMgrHeader(data: packets[index])
    let packet = McuManager.buildPacket(scheme: .ble, version: .SMPv2, op: .writeResponse,
      flags: 0, group: header.groupId, sequenceNumber: header.sequenceNumber,
      commandId: FileCommand.file, payload: ["off": .unsignedInt(offset)])
    replies[index](packet)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  }
  func connect(_ callback: @escaping ConnectionCallback) { callback(.deferred) }
  func close() {}
  func addObserver(_ observer: ConnectionObserver) {}
  func removeObserver(_ observer: ConnectionObserver) { removedObservers += 1 }
}

private final class HeldFileDelegate: FileUploadDelegate {
  var failures = 0
  var cancellations = 0
  func uploadProgressDidChange(bytesSent: Int, fileSize: Int, timestamp: Date) {}
  func uploadDidFail(with error: Error) { failures += 1 }
  func uploadDidCancel() { cancellations += 1 }
  func uploadDidFinish() {}
}

@main struct SDKAbortProof {
  static func main() {
    precondition(Thread.isMainThread)
    let transport = HeldTransport()
    var manager: FirmwareUpgradeManager? = FirmwareUpgradeManager(transport: transport, delegate: nil)
    weak var reference = manager
    let images = [ImageManager.Image(image: 0, hash: Data(repeating: 1, count: 32), data: Data(repeating: 0, count: 64))]
    manager!.start(images: images)
    precondition(manager!.isInProgress() && transport.sends == 1)
    precondition(!manager!.pauseUploadIfActive() && !manager!.isPaused(), "Lifecycle pause parked parameter discovery")
    manager!.cancel() // Upstream cancel intentionally does nothing before upload.
    precondition(manager!.isInProgress())
    transport.close() // Production owner invalidates its real transport first.
    manager!.abort(with: McuMgrTransportError.disconnected)
    precondition(!manager!.pauseUploadIfActive(), "Terminal manager accepted lifecycle pause")
    precondition(!manager!.isInProgress())
    precondition(transport.removedObservers == 1)
    transport.callbacks.first!() // Late parameter error must not start bootloader IO.
    precondition(transport.sends == 1)
    manager!.start(images: images)
    precondition(transport.sends == 1)
    manager = nil
    precondition(reference == nil, "SDK self-retention survived terminal teardown")
    let neverStarted = FirmwareUpgradeManager(transport: transport, delegate: nil)
    neverStarted.abort(with: McuMgrError.returnCode(.unsupported))
    neverStarted.start(images: images)
    precondition(transport.sends == 1)
    let fileTransport = HeldTransport()
    let fileDelegate = HeldFileDelegate()
    let files = FileSystemManager(transport: fileTransport)
    precondition(files.upload(name: "/owned", data: Data(repeating: 1, count: 4096),
      using: FirmwareUpgradeConfiguration(pipelineDepth: 3), delegate: fileDelegate))
    precondition(!files.pauseUploadIfActive(), "File lifecycle pause parked parameter discovery")
    fileTransport.callbacks[0]() // Unsupported parameters fall back to ordinary upload.
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    precondition(fileTransport.sends == 2)
    fileTransport.replyOffset(1, 200)
    precondition(fileTransport.sends == 5, "Initial ACK did not fill the file pipeline")
    precondition(files.pauseUploadIfActive(), "Active high-level file upload did not pause")
    precondition(!files.pauseUploadIfActive(), "Repeated pause changed transfer state")
    for index in 2...4 { fileTransport.replyOffset(index, 0) }
    precondition(fileTransport.sends == 5, "Paused ACK emitted another request")
    files.continueTransfer()
    precondition(fileTransport.sends == 6, "Paused file upload did not continue")
    fileTransport.replyOffset(5, 200)
    precondition(fileTransport.sends == 9, "Paused ACKs left phantom pipeline requests blocking resume")
    files.cancelTransfer(error: McuMgrTransportError.disconnected)
    precondition(!files.pauseUploadIfActive() && fileDelegate.failures == 1)
    let waitingTransport = HeldTransport()
    var waitingFiles: FileSystemManager? = FileSystemManager(transport: waitingTransport)
    weak var waitingReference = waitingFiles
    precondition(waitingFiles!.upload(name: "/owned", data: Data(repeating: 2, count: 64), delegate: fileDelegate))
    waitingFiles!.cancelTransfer()
    precondition(fileDelegate.cancellations == 1)
    precondition(waitingFiles!.upload(name: "/owned-new", data: Data(repeating: 3, count: 64), delegate: fileDelegate))
    waitingTransport.callbacks[0]() // Old parameters must not start the new transfer.
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    precondition(waitingTransport.sends == 2 && !waitingFiles!.pauseUploadIfActive())
    waitingFiles!.cancelTransfer(error: McuMgrTransportError.disconnected)
    waitingTransport.callbacks[1]() // Must not restart with discarded file data.
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    precondition(waitingTransport.sends == 2)
    waitingFiles = nil
    precondition(waitingReference == nil, "Cancelled file upload retained itself")
    var pipeline = McuMgrUploadPipeline(adopting: FirmwareUpgradeConfiguration(pipelineDepth: 3), over: HeldTransport())
    var offsets: [UInt64] = []
    let send: (UInt64) -> UInt64 = { offsets.append($0); return $0 + 100 }
    pipeline.pipelinedSend(ofSize: 1000, using: send)
    precondition(offsets == [0, 100, 200])
    for _ in 0..<2 {
      pipeline.receivedData(with: 0)
      pipeline.pipelinedSend(ofSize: 1000, using: send)
      precondition(offsets.count == 3, "Offset rewind kept refilling invalid requests")
    }
    pipeline.receivedData(with: 0)
    pipeline.pipelinedSend(ofSize: 1000, using: send)
    precondition(offsets == [0, 100, 200, 0, 100, 200], "Pipeline did not restart from server offset")
    print("PASS: SDK offset rewind drains old requests before restarting")
    print("PASS: SDK file upload-only pause/continue and late parameter cancellation")
    print("PASS: actual SDK terminal abort fences late requests and releases self-retention without a transport callback")
  }
}
