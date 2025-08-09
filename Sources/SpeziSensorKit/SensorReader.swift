//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import Observation
import OSLog
public import SensorKit


/// Read samples from a SensorKit ``Sensor``.
///
/// ## Topics
///
/// ### Initializers
/// - ``init(_:)``
///
/// ### Instance Properties
/// - ``sensor``
/// - ``authorizationStatus``
///
/// ### Operations
/// - ``fetchDevices()``
/// - ``fetch(from:timeRange:)``
/// - ``fetch(from:mostRecentAvailable:)``
///
/// ### Supporting Types
/// - ``SensorReaderProtocol``
@Observable
public final class SensorReader<Sample: AnyObject & Hashable>: SensorReaderProtocol, @unchecked Sendable {
    // We use a heap-allocated Array for building up the list of FetchResults;
    // for some reason this has significantly better performance when used as an associated value in an enum case
    // than simply using an Array directly.
    // (Presumably because fewer copies are made...)
    private final class FetchResultsArray {
        private(set) var fetchResults: [SensorKit.FetchResult<Sample>] = []
        func append(_ fetchResult: consuming SensorKit.FetchResult<Sample>) {
            fetchResults.append(fetchResult)
        }
    }
    
    private enum State {
        case idle
        case fetchingDevices(CheckedContinuation<[SRDevice], any Error>)
        case fetchingSamples(FetchResultsArray, CheckedContinuation<[SensorKit.FetchResult<Sample>], any Error>)
        case startingRecording(CheckedContinuation<Void, any Error>)
        case stoppingRecording(CheckedContinuation<Void, any Error>)
        
        var isIdle: Bool {
            switch self {
            case .idle: true
            default: false
            }
        }
    }
    
    @ObservationIgnored public let sensor: Sensor<Sample>
    @ObservationIgnored private var delegateImpl: SensorDelegate?
    @ObservationIgnored private let logger = Logger(subsystem: "edu.stanford.SpeziSensorKit", category: "SensorKit")
    @ObservationIgnored private let reader: SRSensorReader
    // NOTE: reads of `state` may happen on any thread, but we only write from the @SensorKitActor
    @ObservationIgnored private nonisolated(unsafe) var state: State = .idle
    @ObservationIgnored @SensorKitActor private let lock = Lock()
    @MainActor public private(set) var authorizationStatus: SRAuthorizationStatus = .notDetermined
    
    public nonisolated init(_ sensor: Sensor<Sample>) {
        self.sensor = sensor
        reader = SRSensorReader(sensor: sensor.srSensor)
        delegateImpl = SensorDelegate(reader: self)
        reader.delegate = delegateImpl
    }
    
    @SensorKitActor
    private func checkIsIdle() {
        precondition(state.isIdle)
    }
    
    /// Obtains the lock for operations on this ``SensorReader``.
    ///
    /// If the lock is already taken, this function will wait until the lock is released, obtain it, and then return.
    @SensorKitActor
    private func lock() async {
        await lock.lock()
    }
    
    /// Releases the lock.
    @SensorKitActor
    private func unlock() {
        lock.unlock()
    }
    
    @SensorKitActor
    public func fetchDevices() async throws -> sending [SRDevice] {
        await lock()
        checkIsIdle()
        defer {
            state = .idle
            unlock()
        }
        return try await withCheckedThrowingContinuation { continuation in
            checkIsIdle()
            state = .fetchingDevices(continuation)
            reader.fetchDevices()
        }
    }
    
    @SensorKitActor
    public func startRecording() async throws {
        await lock()
        checkIsIdle()
        defer {
            state = .idle
            unlock()
        }
        try await withCheckedThrowingContinuation { continuation in
            checkIsIdle()
            state = .startingRecording(continuation)
            reader.startRecording()
        }
    }
    
    @SensorKitActor
    public func stopRecording() async throws {
        await lock()
        checkIsIdle()
        defer {
            state = .idle
            unlock()
        }
        try await withCheckedThrowingContinuation { continuation in
            checkIsIdle()
            state = .stoppingRecording(continuation)
            reader.stopRecording()
        }
    }
    
    @SensorKitActor
    public func fetch(
        from device: SRDevice? = nil, // swiftlint:disable:this function_default_parameter_at_end
        timeRange: Range<Date>
    ) async throws -> [SensorKit.FetchResult<Sample>] {
        await lock()
        checkIsIdle()
        defer {
            state = .idle
            unlock()
        }
        let fetchRequest = SRFetchRequest()
        if let device {
            fetchRequest.device = device
        }
        fetchRequest.from = .fromCFAbsoluteTime(_cf: timeRange.lowerBound.timeIntervalSinceReferenceDate)
        fetchRequest.to = .fromCFAbsoluteTime(_cf: timeRange.upperBound.timeIntervalSinceReferenceDate)
        return try await withCheckedThrowingContinuation { continuation in
            checkIsIdle()
            state = .fetchingSamples(FetchResultsArray(), continuation)
            reader.fetch(fetchRequest)
        }
    }
}


extension SensorReader {
    // We put all of this into a separate, private type
    // so that the SensorReader class doesn't need to declare a public conformance to SRSensorReaderDelegate.
    private final class SensorDelegate: NSObject, SRSensorReaderDelegate, Sendable {
        unowned let reader: SensorReader
        
        nonisolated(unsafe) private var numFetchResults: Int = 0
        
        init(reader: SensorReader) {
            self.reader = reader
        }
        
        func sensorReader(_ reader: SRSensorReader, didChange authorizationStatus: SRAuthorizationStatus) {
            Task { @MainActor in
                self.reader.authorizationStatus = authorizationStatus
            }
        }
        
        func sensorReader(_ reader: SRSensorReader, didFetch devices: [SRDevice]) {
            nonisolated(unsafe) let devices = devices
            switch self.reader.state {
            case .fetchingDevices(let continuation):
                continuation.resume(returning: devices)
            default:
                reportUnexpectedDelegateCallback()
            }
        }
        
        func sensorReader(_ reader: SRSensorReader, fetchDevicesDidFailWithError error: any Error) {
            switch self.reader.state {
            case .fetchingDevices(let continuation):
                continuation.resume(throwing: error)
            default:
                reportUnexpectedDelegateCallback()
            }
        }
        
        func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, didFetchResult result: SRFetchResult<AnyObject>) -> Bool {
            nonisolated(unsafe) let result = result
            switch self.reader.state {
            case .fetchingSamples(let fetchResults, _):
                fetchResults.append(.init(result, for: self.reader.sensor))
            default:
                reportUnexpectedDelegateCallback()
            }
            return true
        }
        
        func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, failedWithError error: any Error) {
            switch self.reader.state {
            case .fetchingSamples(_, let continuation):
                continuation.resume(throwing: error)
            default:
                reportUnexpectedDelegateCallback()
            }
        }
        
        func sensorReader(_ reader: SRSensorReader, didCompleteFetch fetchRequest: SRFetchRequest) {
            switch self.reader.state {
            case let .fetchingSamples(fetchResults, continuation):
                continuation.resume(returning: fetchResults.fetchResults)
            default:
                reportUnexpectedDelegateCallback()
            }
        }
        
        func sensorReaderWillStartRecording(_ reader: SRSensorReader) {
            switch self.reader.state {
            case .startingRecording(let continuation):
                continuation.resume()
            default:
                reportUnexpectedDelegateCallback()
            }
        }
        
        func sensorReader(_ reader: SRSensorReader, startRecordingFailedWithError error: any Error) {
            switch self.reader.state {
            case .startingRecording(let continuation):
                continuation.resume(throwing: error)
            default:
                reportUnexpectedDelegateCallback()
            }
        }
        
        func sensorReaderDidStopRecording(_ reader: SRSensorReader) {
            switch self.reader.state {
            case .stoppingRecording(let continuation):
                continuation.resume()
            default:
                reportUnexpectedDelegateCallback()
            }
        }
        
        func sensorReader(_ reader: SRSensorReader, stopRecordingFailedWithError error: any Error) {
            switch self.reader.state {
            case .stoppingRecording(let continuation):
                continuation.resume(throwing: error)
            default:
                reportUnexpectedDelegateCallback()
            }
        }
        
        
        private func reportUnexpectedDelegateCallback(_ caller: StaticString = #function) {
            guard self.reader.state.isIdle else {
                let stateDesc = "\(self.reader.state)"
                preconditionFailure("Received unexpected delegate callback '\(caller)' while in state \(stateDesc)")
            }
            self.reader.logger.error("Unexpectedly received delegate callback '\(caller)' while in idle state.")
        }
    }
}


// MARK: Utils

extension SensorReader {
    private final class Lock {
        private var isLocked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        
        init() {}
        
        func lock() async {
            if !isLocked {
                precondition(waiters.isEmpty, "invalid state: lock is open but there are waiters.")
                isLocked = true
            } else {
                // the lock is locked.
                // we need to wait until it is our turn to obtain the lock.
                await withCheckedContinuation { continuation in
                    waiters.append(continuation)
                }
            }
        }
        
        func unlock() {
            precondition(isLocked, "invalid state: cannot unlock lock that isn't locked.")
            if waiters.isEmpty {
                // no one wants to take the lock over from us; we can simply open it
                isLocked = false
            } else {
                // if there are waiters, we keep the lock closed and (semantially) hand it over to the first continuation.
                waiters.removeFirst().resume()
            }
        }
    }
}
