//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
@preconcurrency public import SensorKit


/// A type-erased ``SensorReader``.
public protocol SensorReaderProtocol<Sample>: AnyObject, Sendable {
    associatedtype Sample: AnyObject, Hashable
    
    /// The reader's underlying ``Sensor``
    var sensor: Sensor<Sample> { get }
    
    /// Tells the OS to start data collection for this reader's sensor
    @SensorKitActor
    func startRecording() async throws
    
    /// Tells the OS to stop data collection for this reader's sensor
    @SensorKitActor
    func stopRecording() async throws
    
    /// Fetches a list of all devices that collect data for this sensor.
    @SensorKitActor
    func fetchDevices() async throws -> sending [SRDevice]
    
    /// Fetches data from SensorKit
    @SensorKitActor
    func fetch(from device: SRDevice, timeRange: Range<Date>) async throws -> [SensorKit.FetchResult<Sample>]
}


extension SensorReaderProtocol {
    var typeErasedSensor: any AnySensor {
        sensor
    }
    
    /// Fetches data from SensorKit
    @SensorKitActor
    public func fetch(from device: SRDevice, mostRecentAvailable fetchDuration: Duration) async throws -> [SensorKit.FetchResult<Sample>] {
        let endDate = sensor.currentQuarantineBegin
        let startDate = endDate.addingTimeInterval(-fetchDuration.timeInterval)
        return try await fetch(from: device, timeRange: startDate..<endDate)
    }
    
    /// Performs a batched fetch, using a managed query anchor.
    @available(iOS 18, *)
    @SensorKitActor
    func fetchBatched(anchor: ManagedQueryAnchor) async throws -> some AsyncSequence<[SensorKit.FetchResult<Sample>], any Error> {
        try await BatchedAsyncDataFetcher(reader: self, anchor: anchor)
    }
}
