//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import Observation
import os
public import SensorKit
public import Spezi


@Observable
public final class SensorKit: Module, EnvironmentAccessible, Sendable {
    nonisolated private let logger = Logger(subsystem: "edu.stanford.MHC", category: "SensorKit")
    @MainActor private var sensorReaders: [any SensorReaderProtocol] = []
    
    public nonisolated init() {}
    
    /// Obtains the reader for the specified ``Sensor``.
    @MainActor
    public func reader<Sample>(for sensor: Sensor<Sample>) -> SensorReader<Sample> {
        if let reader = sensorReaders.first(where: { $0.sensor.srSensor == sensor.srSensor }) {
            return reader as! SensorReader<Sample> // swiftlint:disable:this force_cast
        } else {
            let reader = SensorReader(sensor: sensor)
            sensorReaders.append(reader)
            return reader
        }
    }
}


// MARK: Authorization

extension SensorKit {
    /// Checks the  current authorization status of the specified sensor.
    public nonisolated func authorizationStatus(for sensor: Sensor<some Any>) -> SRAuthorizationStatus {
        SRSensorReader(sensor: sensor.srSensor).authorizationStatus
    }
    
    /// Requests access to read data from the specified ``Sensor``s.
    public nonisolated func requestAccess(to sensors: [any AnySensor]) async throws {
        do {
            try await SRSensorReader.requestAuthorization(sensors: sensors.mapIntoSet(\.srSensor))
        } catch {
            if (error as? SRError)?.code == .promptDeclined,
               (error as NSError).underlyingErrors.contains(where: { ($0 as NSError).code == 8201 }) {
                // the request failed bc we're already authenticated.
                return
            } else {
                throw error
            }
        }
    }
}


extension SRAuthorizationStatus {
    var displayName: String {
        switch self {
        case .notDetermined:
            "not determined"
        case .authorized:
            "authorized"
        case .denied:
            "denied"
        @unknown default:
            "unknown<\(rawValue)>"
        }
    }
}
