//
//  McuMgrBleROBWriteBuffer.swift
//  iOSMcuManagerLibrary
//
//  Created by Dinesh Harjani on 14/7/25.
//

import Foundation
import Dispatch
import CoreBluetooth

// MARK: - McuMgrBleROBWriteBuffer

/**
 ROB for Re-Order Buffer.
 
 The purpose of this last-level transport layer is to guarantee all chunks for the same
 sequence number are sent in-order. If multiple pieces (chunks) of different sequence
 numbers are interleaved, it'll garble up the results and the firmware will not be able to
 understand anything.
 */
internal final class McuMgrBleROBWriteBuffer {
    
    // MARK: - Private Properties
    
    private let lifetime: McuMgrBleLifetime
    private let lock = DispatchQueue(label: "McuMgrBleROBWriteBuffer", qos: .userInitiated)
    
    private var pausedWritesWithoutResponse: Bool
    private var window: [Write]
    private var writeNumber: Int
    
    #if DEBUG
    private var peripheralNotReady: DispatchTime!
    private var peripheralIsReady: DispatchTime!
    #endif
    
    private weak var log: McuMgrLogDelegate?
    
    // MARK: init
    
    init(_ log: McuMgrLogDelegate?, lifetime: McuMgrBleLifetime) {
        self.lifetime = lifetime
        self.log = log
        self.pausedWritesWithoutResponse = false
        self.window = [Write]()
        self.writeNumber = 0
    }
    
    // MARK: API

    internal func setLogDelegate(_ delegate: McuMgrLogDelegate?) {
        lock.sync { log = delegate }
    }
    
    internal func isInFlight(_ sequenceNumber: McuSequenceNumber) -> Bool {
        lock.sync { [unowned self] in
            return window.contains(where: {
                $0.mcuMgrSequenceNumber == sequenceNumber
            })
        }
    }
    
    /**
     All chunks of the same packet need to be sent together. Otherwise, they can't be merged properly on the receiving end.
     */
    internal func enqueue(_ sequenceNumber: McuSequenceNumber, data: [Data], to peripheral: CBPeripheral, characteristic: CBCharacteristic, callback: @escaping (Data?, McuMgrTransportError?) -> Void) {
        lock.async { [weak self] in
            guard let self else { return }
            guard !lifetime.isInvalidated else { callback(nil, .disconnected); return }
            if window.contains(where: { $0.mcuMgrSequenceNumber == sequenceNumber }) {
                if pausedWritesWithoutResponse { unsafe_writeThroughWindow(to: peripheral) }
                return
            }
            window.append(contentsOf: Write.split(writeNumber, sequenceNumber: sequenceNumber, chunks: data, peripheral: peripheral, characteristic: characteristic, callback: callback))
            window.sort(by: <)
            writeNumber = writeNumber == .max ? 0 : writeNumber + 1
            unsafe_writeThroughWindow(to: peripheral)
        }
    }

    internal func clear(_ error: McuMgrTransportError) {
        lock.sync {
            let pending = window
            window.removeAll()
            pausedWritesWithoutResponse = false
            for write in pending { write.callback(nil, error) }
        }
    }

    internal func peripheralReadyToWrite(_ peripheral: CBPeripheral) {
        lock.async { [weak self] in
            guard let self else { return }
            // Note: peripheralIsReady(toSendWriteWithoutResponse:) is called many times.
            // We only want to continue past this guard when a write was paused and
            // thus added to `pausedWrites`.
            guard pausedWritesWithoutResponse else { return }
            pausedWritesWithoutResponse = false
            
            // Paused writes are never removed from the queue. So all we have to do is
            // restart from the front of the queue.
            let resumeWrite: Write! = window.first
            unsafe_logResume(resumeWrite)
            unsafe_writeThroughWindow(to: peripheral)
        }
    }
}
    
// MARK: - Private

private extension McuMgrBleROBWriteBuffer {
    
    func unsafe_writeThroughWindow(to peripheral: CBPeripheral) {
        while let write = window.first {
            guard !lifetime.isInvalidated else {
                let pending = window; window.removeAll()
                for write in pending { write.callback(nil, .disconnected) }
                return
            }
            guard peripheral.canSendWriteWithoutResponse else {
                pausedWritesWithoutResponse = true
                unsafe_logPause(write)
                return
            }
            
            // Clear state of pausedWritesWithoutResponse in case we end up here, and thus empty
            // the window (queue), before peripheralReadyToWrite()'s code runs.
            if pausedWritesWithoutResponse {
                pausedWritesWithoutResponse = false
                unsafe_logResume(write)
            }
            
            let admitted = lifetime.perform {
                peripheral.writeValue(write.chunk, for: write.characteristic, type: .withoutResponse)
            }
            write.callback(admitted ? write.chunk : nil, admitted ? nil : .disconnected)
            // ↓ Paranoia, I agree. But it makes me feel safe.
            assert(window[0] == write)
            window.remove(at: 0)
        }
    }
}

// MARK: - (Private) Log

private extension McuMgrBleROBWriteBuffer {
    
    func unsafe_logResume(_ write: Write) {
        #if DEBUG
        peripheralIsReady = .now()
        if #available(iOS 15.0, macOS 10.15, *) {
            if let peripheralNotReady, let peripheralIsReady {
                let elapsedTime = Measurement<UnitDuration>(value: Double((peripheralIsReady.uptimeNanoseconds - peripheralNotReady.uptimeNanoseconds)), unit: .nanoseconds)
                    .converted(to: .milliseconds)
                log(msg: "Peripheral Ready For Write Without Response Delay: \(elapsedTime)", atLevel: .debug)
            }
        }
        #endif
        
        // Paused writes are never removed from the queue. So all we have to do is
        // restart from the front of the queue.
        log(msg: "► [Seq: \(write.mcuMgrSequenceNumber), Chk: \(write.chunkIndex)] Resume (Peripheral Ready for Write Without Response)", atLevel: .debug)
    }
    
    func unsafe_logPause(_ write: Write) {
        log(msg: "⏸︎ [Seq: \(write.mcuMgrSequenceNumber), Chk: \(write.chunkIndex)] Paused (Peripheral not Ready for Write Without Response)", atLevel: .debug)
        #if DEBUG
        peripheralNotReady = .now()
        #endif
    }
    
    func log(msg: @autoclosure () -> String, atLevel level: McuMgrLogLevel) {
        log?.log(msg(), ofCategory: .transport, atLevel: level)
    }
}

// MARK: - Write

internal extension McuMgrBleROBWriteBuffer {
    
    struct Write {
        let writeNumber: Int
        let mcuMgrSequenceNumber: McuSequenceNumber
        let chunkIndex: Int
        let chunk: Data
        let peripheral: CBPeripheral
        let characteristic: CBCharacteristic
        let callback: (Data?, McuMgrTransportError?) -> Void
        
        init(_ writeNumber: Int, sequenceNumber: McuSequenceNumber, chunkIndex: Int, chunk: Data, peripheral: CBPeripheral, characteristic: CBCharacteristic, callback: @escaping (Data?, McuMgrTransportError?) -> Void) {
            self.writeNumber = writeNumber
            self.mcuMgrSequenceNumber = sequenceNumber
            self.chunkIndex = chunkIndex
            self.chunk = chunk
            self.peripheral = peripheral
            self.characteristic = characteristic
            self.callback = callback
        }
        
        static func split(_ writeID: Int, sequenceNumber: McuSequenceNumber, chunks: [Data], peripheral: CBPeripheral, characteristic: CBCharacteristic, callback: @escaping (Data?, McuMgrTransportError?) -> Void) -> [Self] {
            return chunks.indices.map { i in
                Self(writeID, sequenceNumber: sequenceNumber, chunkIndex: i, chunk: chunks[i], peripheral: peripheral, characteristic: characteristic, callback: callback)
            }
        }
    }
}

// MARK: Comparable

extension McuMgrBleROBWriteBuffer.Write: Comparable {
    
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.writeNumber == rhs.writeNumber {
            return lhs.chunkIndex < rhs.chunkIndex
        } else {
            return lhs.writeNumber < rhs.writeNumber
        }
    }
}

// MARK: Equatable

extension McuMgrBleROBWriteBuffer.Write: Equatable {
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.writeNumber == rhs.writeNumber
            && lhs.chunkIndex == rhs.chunkIndex
            && lhs.peripheral.identifier == rhs.peripheral.identifier
            && lhs.characteristic.uuid == rhs.characteristic.uuid
    }
}
