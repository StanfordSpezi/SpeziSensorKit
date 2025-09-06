//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

@preconcurrency public import SensorKit
public import SpeziFoundation


/// A type-erased ``Sensor``
///
/// - Important: The ``AnySensor`` protocol is public, but your application should not declare any new conformances to it; ``Sensor`` is the only type allowed to conform to ``AnySensor``.
public protocol AnySensor<Sample>: Hashable, Identifiable, Sendable {
    associatedtype Sample: AnyObject, Hashable
    
    /// The underlying SensorKit `SRSensor`.
    var srSensor: SRSensor { get }
    /// The recommended display name.
    var displayName: String { get }
    /// How long the system hold data in quarantine before it can be queried by applications.
    var dataQuarantineDuration: Duration { get }
    /// The sensor's unique identifier.
    var id: String { get }
}

extension AnySensor {
    @inlinable public var id: String { // swiftlint:disable:this missing_docs
        srSensor.rawValue
    }
    
    var currentQuarantineBegin: Date {
        .now.addingTimeInterval(-dataQuarantineDuration.timeInterval)
    }
    
    var suggestedBatchSize: Duration {
        switch self {
        case Sensor.onWrist:
            .days(1)
        default:
            .hours(2)
        }
    }
}

/// Compare two sensors, based on their identifiers
@inlinable
public func ~= (lhs: Sensor<some Any>, rhs: any AnySensor) -> Bool { // swiftlint:disable:this static_operator
    lhs.id == rhs.id
}


/// A Sensor that can be used with SensorKit.
///
/// The `Sensor` type models a sensor that can be used with SensorKit.
/// It is a thin wrapper around SensorKit's `SRSensor` type, adding sensor-specific information such as a user-displayable name for the sensor and its iOS-enforced data quarantine period.
///
/// Additionally, `Sensor`'s generic parameter is used to associate each sensor with its specific sample type used by SensorKit.
///
/// You use the ``SensorReader`` to fetch a sensor's data from SensorKit.
///
/// ## Topics
///
/// ### Instance Properties
/// - ``srSensor``
/// - ``displayName``
/// - ``dataQuarantineDuration``
///
/// ### Supported Sensors
/// - ``accelerometer``
/// - ``ambientLight``
/// - ``ambientPressure``
/// - ``deviceUsage``
/// - ``ecg``
/// - ``heartRate``
/// - ``onWrist``
/// - ``pedometer``
/// - ``ppg``
/// - ``visits``
/// - ``wristTemperature``
///
/// ### Supporting Types
/// - ``AnySensor``
public struct Sensor<Sample: AnyObject & Hashable>: AnySensor {
    @usableFromInline
    enum SensorKitFetchReturnType: Sendable {
        case object, array
    }
    
    public let srSensor: SRSensor
    public let displayName: String
    public let dataQuarantineDuration: Duration
    @usableFromInline let sensorKitFetchReturnType: SensorKitFetchReturnType
    
    @inlinable
    init(srSensor: SRSensor, displayName: String, dataQuarantineDuration: Duration, sensorKitFetchReturnType: SensorKitFetchReturnType) {
        self.srSensor = srSensor
        self.displayName = displayName
        self.dataQuarantineDuration = dataQuarantineDuration
        self.sensorKitFetchReturnType = sensorKitFetchReturnType
    }
    
    /// Creates a ``Sensor`` from a type-erased ``AnySensor``.
    ///
    /// Since ``Sensor`` is the only type allowed to conform to ``AnySensor``, this is guaranteed to always succeed.
    @inlinable
    public init(_ typeErased: any AnySensor<Sample>) {
        // SAFETY: `Sensor` is the only type allowed to conform to `AnySensor`.
        self = typeErased as! Self // swiftlint:disable:this force_cast
    }
}
