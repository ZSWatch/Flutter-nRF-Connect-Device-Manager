import Foundation
import iOSMcuManagerLibrary

/// Compiles/runs against the entire actual SDK, with a transport that never
/// opens Bluetooth. Cancelled callbacks may remain outstanding indefinitely.
private final class HeldTransport: McuMgrTransport {
  var mtu: Int! = 244
  var sends = 0
  var callbacks: [() -> Void] = []
  var removedObservers = 0
  func getScheme() -> McuMgrScheme { .ble }
  func send<T: McuMgrResponse>(data: Data, timeout: Int, callback: @escaping McuMgrCallback<T>) {
    sends += 1; callbacks.append { callback(nil, McuMgrTransportError.disconnected) }
  }
  func connect(_ callback: @escaping ConnectionCallback) { callback(.deferred) }
  func close() {}
  func addObserver(_ observer: ConnectionObserver) {}
  func removeObserver(_ observer: ConnectionObserver) { removedObservers += 1 }
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
    print("PASS: actual SDK terminal abort fences late requests and releases self-retention without a transport callback")
  }
}
