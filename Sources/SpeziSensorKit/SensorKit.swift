//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable no_extension_access_modifier all

import Foundation
public import Observation
import os
public import SensorKit
public import Spezi


@Observable
@MainActor
public final class SensorKit: Module, EnvironmentAccessible {
    nonisolated private let logger = Logger(subsystem: "edu.stanford.MHC", category: "SensorKit")
}


// MARK: Authorization

nonisolated extension SensorKit {
//    @SensorKitActor
    public func authorizationStatus(for sensor: SRSensor) -> SRAuthorizationStatus {
        let reader = SRSensorReader(sensor: sensor)
        return reader.authorizationStatus
    }
    
    @MainActor
    public func requestAccess(to sensors: Set<SRSensor>) async throws {
        do {
            try await SRSensorReader.requestAuthorization(sensors: sensors)
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


// MARK: SensorReader

//extension SensorKit {
//    enum FetchError: Error {
//        case invalidTimeRange
//    }
//}


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
