//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

@preconcurrency import SensorKit


/// An `AsyncSequence` and `AsyncIterator` that can be used to fetch and process data from SensorKit, split into distinct batches.
///
/// Each batch will be fetched from SensorKit on demand, i.e. when ``next(isolation:)`` is called.
///
/// - Important: Due to the lazy nature of this type, and the fact that it uses a query anchor internally to keep track of already-fetched time ranhes,  the sequence should only be iterated once.
@available(iOS 18, *)
struct BatchedAsyncDataFetcher<Sample, SensorReader: SensorReaderProtocol<Sample>>: AsyncSequence, AsyncIteratorProtocol {
    typealias Element = [SensorKit.FetchResult<Sample>]
    typealias Failure = any Error
    typealias AsyncIterator = Self
    
    private enum State {
        case initial
        case process(timeRange: Range<Date>, devices: [SRDevice])
        /// The data fetcher is done, i.e. has fetched (and returned) all data that is currently available.
        case done
    }
    
    private let reader: SensorReader
    private let anchor: ManagedQueryAnchor
    private var sensor: Sensor<Sample> {
        reader.sensor
    }
    private let quarantineCutoff: Date
    nonisolated(unsafe) private let devices: [SRDevice]
    
    private var state: State = .initial
    
    init(reader: SensorReader, anchor: ManagedQueryAnchor) async throws {
        self.reader = reader
        self.anchor = anchor
        self.quarantineCutoff = reader.sensor.currentQuarantineBegin
        self.devices = try await reader.fetchDevices()
    }
    
    consuming func makeAsyncIterator() -> Self {
        self
    }
    
    private mutating func advanceState() throws {
        switch state {
        case .done:
            return
        case .initial:
            var currentAnchor = try anchor.value
            guard currentAnchor.timestamp < quarantineCutoff else {
                state = .done
                return
            }
            if currentAnchor.timestamp == .distantPast {
                // first time
                currentAnchor = .init(timestamp: quarantineCutoff.addingTimeInterval(-Duration.days(7).timeInterval))
                try anchor.update(currentAnchor)
            }
            let batchStartDate = currentAnchor.timestamp
            let batchEndDate = Swift.min(batchStartDate.addingTimeInterval(sensor.suggestedBatchSize.timeInterval), quarantineCutoff)
            state = .process(timeRange: batchStartDate..<batchEndDate, devices: devices)
        case let .process(timeRange, devices):
            guard devices.count <= 1 else {
                state = .process(timeRange: timeRange, devices: Array(devices.dropFirst()))
                return
            }
            try self.anchor.update(.init(timestamp: timeRange.upperBound))
            guard timeRange.upperBound < quarantineCutoff else {
                // we already were processing the last (currently available) batch
                state = .done
                return
            }
            let newStartDate = timeRange.upperBound
            let newEndDate = Swift.min(newStartDate.addingTimeInterval(sensor.suggestedBatchSize.timeInterval), quarantineCutoff)
            state = .process(timeRange: newStartDate..<newEndDate, devices: self.devices)
        }
    }
    
    mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        switch state {
        case .done:
            return nil
        case .initial:
            try advanceState()
            return try await next(isolation: actor)
        case let .process(timeRange, devices):
            guard let device = devices.first else {
                try advanceState()
                return try await next(isolation: actor)
            }
            let results = try await reader.fetch(from: device, timeRange: timeRange)
            try advanceState()
            return results
        }
    }
}
