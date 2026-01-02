//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

private import Foundation
private import OSLog
import SensorKit
private import SpeziFoundation


/// An `AsyncSequence` that can be used to fetch and process data from SensorKit, split into distinct batches.
///
/// Each batch will be fetched from SensorKit on demand, i.e. when the iterator's `next(isolation:)` function is called.
///
/// - Important: Due to the lazy nature of this type, and the fact that it uses a query anchor internally to keep track of already-fetched time ranges, the sequence should only be iterated once.
@available(iOS 18, *)
public struct AnchoredAsyncDataFetcher<Sample: SensorKitSampleProtocol>: AsyncSequence {
    public typealias Element = (SensorKit.BatchInfo, [Sample.SafeRepresentation])
    public typealias Failure = any Error
    
    private let sensor: Sensor<Sample>
    private let queryAnchorProvider: (SensorKit.QueryAnchorKey) -> ManagedQueryAnchor
    private let batchSize: BatchSize
    nonisolated(unsafe) private let devices: [SRDevice]
    
    public init(
        sensor: some AnySensor<Sample>,
        queryAnchorProvider: @escaping (SensorKit.QueryAnchorKey) -> ManagedQueryAnchor,
        batchSize: BatchSize? = nil
    ) async throws {
        self.sensor = Sensor(sensor)
        self.queryAnchorProvider = queryAnchorProvider
        self.batchSize = batchSize ?? sensor.suggestedBatchSize
        self.devices = try await sensor.fetchDevices()
    }
    
    @AsyncIteratorBuilder<Element, Failure>
    public consuming func makeAsyncIterator() -> some AsyncIteratorProtocol<Element, Failure> {
        switch batchSize {
        case .numSamples(let limit):
            for device in devices {
                nonisolated(unsafe) let device = device
                SampleCountBasedFetcher(
                    sensor: sensor,
                    batchSize: limit,
                    anchor: queryAnchorProvider(SensorKit.QueryAnchorKey(sensor: sensor, deviceProductType: device.productType)),
                    device: device
                )
            }
        case .timeInterval(let duration):
            for device in devices {
                nonisolated(unsafe) let device = device
                TimeIntervalBasedFetcher(
                    sensor: sensor,
                    anchor: queryAnchorProvider(SensorKit.QueryAnchorKey(sensor: sensor, deviceProductType: device.productType)),
                    quarantineCutoff: sensor.currentQuarantineBegin,
                    batchSize: duration.timeInterval,
                    device: device
                )
            }
        }
    }
}


@available(iOS 18, *)
extension AnchoredAsyncDataFetcher {
    /// Async iterator that fetches samples batched by time interval.
    private struct TimeIntervalBasedFetcher: AsyncIteratorProtocol {
        private enum State {
            case initial
            case process(timeRange: Range<Date>)
            /// The data fetcher is done, i.e. has fetched (and returned) all data that is currently available.
            case done
        }
        
        private let sensor: Sensor<Sample>
        private let anchor: ManagedQueryAnchor
        private let quarantineCutoff: Date
        private let batchSize: TimeInterval
        nonisolated(unsafe) private let device: SRDevice
        private var state: State = .initial
        
        init(
            sensor: Sensor<Sample>,
            anchor: ManagedQueryAnchor,
            quarantineCutoff: Date,
            batchSize: TimeInterval,
            device: SRDevice
        ) {
            self.sensor = sensor
            self.anchor = anchor
            self.quarantineCutoff = quarantineCutoff
            self.batchSize = batchSize
            self.device = device
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
                let batchEndDate = Swift.min(batchStartDate.addingTimeInterval(batchSize), quarantineCutoff)
                state = .process(timeRange: batchStartDate..<batchEndDate)
            case .process(let timeRange):
                try anchor.update(.init(timestamp: timeRange.upperBound))
                guard timeRange.upperBound < quarantineCutoff else {
                    // we already were processing the last (currently available) batch
                    state = .done
                    return
                }
                let newStartDate = timeRange.upperBound
                let newEndDate = Swift.min(newStartDate.addingTimeInterval(batchSize), quarantineCutoff)
                state = .process(timeRange: newStartDate..<newEndDate)
            }
        }
        
        mutating func next(isolation: isolated (any Actor)?) async throws(Failure) -> Element? {
            switch state {
            case .done:
                return nil
            case .initial:
                try advanceState()
                return try await next(isolation: isolation)
            case .process(let timeRange):
                let results = try await sensor.fetch(from: device, timeRange: timeRange)
                try advanceState()
                let batchInfo = SensorKit.BatchInfo(timeRange: timeRange, device: SensorKit.DeviceInfo(device))
                return (batchInfo, results)
            }
        }
    }
}


@available(iOS 18.0, *)
extension AnchoredAsyncDataFetcher {
    /// Async iterator that fetches samples batched by #samples.
    fileprivate final class SampleCountBasedFetcher: AsyncIteratorProtocol {
        private let anchor: ManagedQueryAnchor
        private let reader: SRSensorReader
        nonisolated(unsafe) private let delegate: FetchDelegate // swiftlint:disable:this weak_delegate
        private let device: SRDevice
        private var isFetching = false
        
        init(
            sensor: Sensor<Sample>,
            batchSize: Int,
            anchor: ManagedQueryAnchor,
            device: SRDevice
        ) {
            self.anchor = anchor
            self.device = device
            self.reader = SRSensorReader(sensor)
            self.delegate = FetchDelegate(
                sensor: sensor,
                deviceInfo: SensorKit.DeviceInfo(device),
                batchSize: batchSize,
                anchor: anchor
            )
            self.reader.delegate = self.delegate
        }
        
        func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
            if !isFetching {
                isFetching = true
                let fetchRequest = SRFetchRequest()
                fetchRequest.device = device
                fetchRequest.from = SRAbsoluteTime(try anchor.value.timestamp)
                fetchRequest.to = .current()
                reader.fetch(fetchRequest)
            }
            return try await delegate.nextBatch()
        }
        
        deinit {
            // if the iterator is destroyed, we explicitly tell the fetch delegate to stop.
            // this is required to prevent SensorKit from providing us more and more data in
            // a situation where the loop stopped early (eg because of a break or return) rather
            // than because the iterator was exhausted
            delegate.stop()
        }
    }
}


@available(iOS 18.0, *)
extension AnchoredAsyncDataFetcher.SampleCountBasedFetcher {
    private final class FetchDelegate: NSObject, SRSensorReaderDelegate {
        private let logger: Logger
        private let sensor: Sensor<Sample>
        private let deviceInfo: SensorKit.DeviceInfo
        private let batchSize: Int
        private let anchor: ManagedQueryAnchor
        
        private var isActive = true
        
        private(set) var samples: [Sample.SafeRepresentation] = []
        private(set) var lastSeenTimestamp: SRAbsoluteTime?
        
        // the lock (which protects the `stop` and `processCurrentSamples` functions)
        // is needed to work around a double free which can occur when the owning `SampleCountBasedFetcher`
        // gets deallocated and calls the `stop()` function at the same time as SensorKit is also
        // calling `stop` and/or `processCurrentSamples. (i think.)
        private let lock = NSRecursiveLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var nextBatchContinuation: CheckedContinuation<Element?, any Error>?
        
        init(sensor: Sensor<Sample>, deviceInfo: SensorKit.DeviceInfo, batchSize: Int, anchor: ManagedQueryAnchor) {
            self.logger = Logger(subsystem: "edu.stanford.SpeziSensorKit", category: "\(Self.self)")
            self.sensor = sensor
            self.deviceInfo = deviceInfo
            self.batchSize = batchSize
            self.anchor = anchor
            self.samples.reserveCapacity(batchSize + (batchSize / 5))
        }
        
        func nextBatch() async throws -> Element? {
            guard isActive else {
                return nil
            }
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Element?, any Error>) in
                precondition(self.isActive)
                precondition(self.nextBatchContinuation == nil, "\(self.sensor.displayName)")
                self.nextBatchContinuation = continuation
                self.semaphore.signal() // signal that continuation is ready
                precondition(self.isActive)
            }
        }
        
        func stop() {
            lock.lock()
            defer {
                lock.unlock()
            }
            isActive = false
            samples.removeAll()
            lastSeenTimestamp = nil
            precondition(nextBatchContinuation == nil)
            nextBatchContinuation = nil
            semaphore.signal() // in case the process function is currently waiting on the semaphore...
        }
        
        private func processCurrentSamples() {
            lock.lock()
            defer {
                lock.unlock()
            }
            semaphore.wait() // wait for continuation to be ready
            guard let nextBatchContinuation else {
                return
            }
            if let first = samples.first, let last = samples.last {
                // samples is not empty
                self.nextBatchContinuation = nil
                nextBatchContinuation.resume(returning: (
                    SensorKit.BatchInfo(
                        // note that we intentionally use the lower bound of the last sample's time range,
                        // in order to make the batch's time range match the fetched time range, as opposed to the represented time range.
                        // (otherwise, using the batch's time ranges to perform follow up fetches could lead to missed samples...)
                        timeRange: first.timeRange.lowerBound..<last.timeRange.lowerBound,
                        device: deviceInfo
                    ),
                    samples
                ))
            } else {
                // samples is empty
                self.nextBatchContinuation = nil
                nextBatchContinuation.resume(returning: nil)
                stop()
            }
            if let lastSeenTimestamp {
                do {
                    try anchor.update(QueryAnchor(timestamp: Date(lastSeenTimestamp)))
                } catch {
                    logger.error("Failed to upadate query anchor: \(error)")
                }
            }
            samples.removeAll(keepingCapacity: true)
        }
        
        func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, didFetchResult result: SRFetchResult<AnyObject>) -> Bool {
            guard isActive else {
                return false
            }
            do {
                // make sure we properly limit the lifetimes of the on-demand-decoded SRFetchResult sample properties...
                try autoreleasepool {
                    let fetchResult = SensorKit.FetchResult(result, for: sensor)
                    let samples = SensorKit.FetchResultsIterator(fetchResult).map {
                        (timestamp: $0, sample: unsafeDowncast($1, to: Sample.SafeRepresentationProcessingInput.self))
                    }
                    self.samples.append(contentsOf: try Sample.processIntoSafeRepresentation(samples))
                    lastSeenTimestamp = lastSeenTimestamp.map { max($0, result.timestamp) } ?? result.timestamp
                }
            } catch {
                logger.error("Error processing fetch result: \(error)")
                // we simply skip this result and continue normally
                return true
            }
            if self.samples.count >= batchSize {
                processCurrentSamples()
            }
            return isActive
        }
        
        func sensorReader(_ reader: SRSensorReader, fetching fetchRequest: SRFetchRequest, failedWithError error: any Error) {
            isActive = false
            nextBatchContinuation?.resume(throwing: error)
            stop()
        }
        
        func sensorReader(_ reader: SRSensorReader, didCompleteFetch fetchRequest: SRFetchRequest) {
            isActive = false
            processCurrentSamples()
            stop()
        }
    }
}


extension SensorKit {
    /// Info about a device from which sensor data was collected.
    ///
    /// - Note: Since the same `DeviceInfo` instance is associated with many samples, and might be passed around a lot in code,
    ///     this is a class rather than a struct, in order to reduce the required amount of copying.
    public final class DeviceInfo: CustomStringConvertible, Sendable {
        /// The user-defined name of the device.
        public let model: String
        /// The framework-defined name of the device.
        public let name: String
        /// The device’s operating system.
        public let systemName: String
        /// The device’s operating system version.
        public let systemVersion: String
        /// A string that identifies the device used to save a sample.
        public let productType: String
        
        public var description: String {
            "model=\(model); name=\(name); systemName=\(systemName); systemVersion=\(systemVersion); productType=\(productType)"
        }
        
        /// Creates a new `DeviceInfo` from an `SRDevice`.
        @inlinable
        public init(_ device: borrowing SRDevice) {
            model = device.model
            name = device.name
            systemName = device.systemName
            systemVersion = device.systemVersion
            productType = device.productType
        }
    }
}


extension SensorKit {
    public struct BatchInfo: Sendable {
        /// The time range queried for when SensorKit returned this batch's samples.
        public let timeRange: Range<Date>
        /// The source device queried for when SensorKit returned this batch's samples.
        public let device: DeviceInfo
        
        @inlinable
        public init(timeRange: Range<Date>, device: DeviceInfo) {
            self.timeRange = timeRange
            self.device = device
        }
    }
}
