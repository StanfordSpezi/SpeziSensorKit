//
// This source file is part of the My Heart Counts iOS application based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import Foundation


extension CMRecordedRotationRateData: SensorKitSampleProtocol {
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        public let timestamp: Date
        public let rotationRate: CMRotationRate
        
        init(_ sample: CMRecordedRotationRateData) {
            timestamp = sample.startDate
            rotationRate = sample.rotationRate
        }
    }
    
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: CMRecordedRotationRateData)>
    ) -> [SafeRepresentation] {
        samples.map { .init($1) }
    }
}


extension CMRotationRate: @retroactive Equatable, @retroactive Hashable {
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(z)
    }
}
