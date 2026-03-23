import Flutter
import iOSMcuManagerLibrary
import CoreBluetooth

class ShellManagerPlugin: ShellManagerApi {
    private var managers: [String: ShellManager] = [:]
    private let centralManager: CBCentralManager

    init(
        centralManager: CBCentralManager,
        messenger: FlutterBinaryMessenger
    ) {
        self.centralManager = centralManager
        ShellManagerApiSetup.setUp(binaryMessenger: messenger, api: self)
    }

    private func getManager(_ remoteId: String) throws -> ShellManager {
        if let mgr = managers[remoteId] {
            return mgr
        }
        guard let uuid = UUID(uuidString: remoteId) else {
            throw PigeonError(code: "INVALID_ID", message: "remoteId not a valid UUID.", details: nil)
        }
        guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first else {
            throw PigeonError(code: "DEVICE_NOT_FOUND", message: "Was not able to retrieve peripheral for UUID \(uuid)", details: nil)
        }
        let mgr = ShellManager(transport: McuMgrBleTransport(peripheral))
        managers[remoteId] = mgr
        return mgr
    }

    func execute(remoteId: String, command: String, completion: @escaping (Result<ShellResponse, any Error>) -> Void) {
        do {
            let mgr = try getManager(remoteId)
            mgr.execute(command: command) { response, error in
                if let error = error {
                    completion(Result.failure(error))
                } else {
                    let output = response?.output ?? ""
                    let rc = response?.ret ?? -1
                    let shellResponse = ShellResponse(
                        output: output,
                        returnCode: Int64(rc)
                    )
                    completion(Result.success(shellResponse))
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
