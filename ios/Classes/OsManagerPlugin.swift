import Flutter
import iOSMcuManagerLibrary
import CoreBluetooth

class OsManagerPlugin : OsManagerApi {
    private var managers: [String : DefaultManager] = [:]
    private let centralManager: CBCentralManager

    init(
        centralManager: CBCentralManager,
        messenger: FlutterBinaryMessenger
    ) {
        self.centralManager = centralManager
        OsManagerApiSetup.setUp(binaryMessenger: messenger, api: self)
    }

    private func getManager(_ remoteId: String) throws -> DefaultManager {
        if let mgr = managers[remoteId] {
            return mgr
        }
        guard let uuid = UUID(uuidString: remoteId) else {
            throw PigeonError(code: "INVALID_ID", message: "remoteId not a valid UUID.", details: nil)
        }
        guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first else {
            throw PigeonError(code: "DEVICE_NOT_FOUND", message: "Was not able to retrieve peripheral for UUID \(uuid)", details: nil)
        }
        let mgr = DefaultManager(transport: McuMgrBleTransport(peripheral))
        managers[remoteId] = mgr
        return mgr
    }

    func reset(remoteId: String, completion: @escaping (Result<Void, any Error>) -> Void) {
        do {
            let mgr = try getManager(remoteId)
            mgr.reset { response, error in
                if let error = error {
                    completion(Result.failure(error))
                } else {
                    // Clean up after successful reset since the device is rebooting
                    try? self.kill(remoteId: remoteId)
                    completion(Result.success(()))
                }
            }
        } catch {
            completion(Result.failure(error))
        }
    }

    func kill(remoteId: String) throws {
        managers.removeValue(forKey: remoteId)?.transport.close()
    }
}
