//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import SensorKit
public import SpeziFoundation


public struct Sensor<Sample: AnyObject & Hashable>: Hashable, Sendable {
    /// The underlying SensorKit `SRSensor`
    public let srSensor: SRSensor
    /// The recommended display name
    public let displayName: String
    /// How long the system hold data in quarantine before it can be queried by applications.
    public let dataQuarantineDuration: Duration
    
    @inlinable
    init(srSensor: SRSensor, displayName: String, dataQuarantineDuration: Duration) {
        self.srSensor = srSensor
        self.displayName = displayName
        self.dataQuarantineDuration = dataQuarantineDuration
    }
}

extension Sensor where Sample == SRWristDetection {
    @inlinable public static var onWrist: Sensor<SRWristDetection> {
        Sensor(
            srSensor: .onWristState,
            displayName: "On-Wrist State",
            dataQuarantineDuration: .hours(24)
        )
    }
}

extension Sensor where Sample == SRAmbientLightSample {
    @inlinable public static var ambientLight: Sensor<SRAmbientLightSample> {
        Sensor(
            srSensor: .ambientLightSensor,
            displayName: "Ambient Light",
            dataQuarantineDuration: .hours(24)
        )
    }
}

extension Sensor where Sample == CMRecordedPressureData {
    @inlinable public static var ambientPressure: Sensor<CMRecordedPressureData> {
        Sensor(
            srSensor: .ambientPressure,
            displayName: "Ambient Pressure",
            dataQuarantineDuration: .hours(24)
        )
    }
}

extension Sensor where Sample == CMHighFrequencyHeartRateData {
    @inlinable public static var heartRate: Sensor<CMHighFrequencyHeartRateData> {
        Sensor(
            srSensor: .heartRate,
            displayName: "Heart Rate",
            dataQuarantineDuration: .hours(24)
        )
    }
}

extension Sensor where Sample == CMPedometerData {
    @inlinable public static var pedometer: Sensor<CMPedometerData> {
        Sensor(
            srSensor: .pedometerData,
            displayName: "Pedometer",
            dataQuarantineDuration: .hours(24)
        )
    }
}

extension Sensor where Sample == SRWristTemperatureSession {
    @inlinable public static var wristTemperature: Sensor<SRWristTemperatureSession> {
        Sensor(
            srSensor: .wristTemperature,
            displayName: "Wrist Temperature",
            dataQuarantineDuration: .hours(24)
        )
    }
}

@available(iOS 17.4, *)
extension Sensor where Sample == SRPhotoplethysmogramSample {
    @inlinable public static var ppg: Sensor<SRPhotoplethysmogramSample> {
        Sensor(
            srSensor: .photoplethysmogram,
            displayName: "PPG",
            dataQuarantineDuration: .hours(24)
        )
    }
}

@available(iOS 17.4, *)
extension Sensor where Sample == SRElectrocardiogramSample {
    @inlinable public static var ecg: Sensor<SRElectrocardiogramSample> {
        Sensor(
            srSensor: .electrocardiogram,
            displayName: "ECG",
            dataQuarantineDuration: .hours(24)
        )
    }
}

extension Sensor where Sample == SRVisit {
    @inlinable public static var visits: Sensor<SRVisit> {
        Sensor(
            srSensor: .visits,
            displayName: "Visits",
            dataQuarantineDuration: .hours(24)
        )
    }
}

extension Sensor where Sample == SRDeviceUsageReport {
    @inlinable public static var deviceUsage: Sensor<SRDeviceUsageReport> {
        Sensor(
            srSensor: .deviceUsageReport,
            displayName: "Device Usage Report",
            dataQuarantineDuration: .hours(24)
        )
    }
}
