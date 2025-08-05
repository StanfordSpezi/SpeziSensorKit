//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import SensorKit


extension SensorKit {
    public struct FetchResult<Sample: AnyObject & Hashable>: Hashable, @unchecked Sendable {
        /// The SensorKit framework's timestamp
        public let sensorKitTimestamp: Date
        public let samples: [Sample]
        
        init(_ fetchResult: SRFetchResult<AnyObject>) {
            sensorKitTimestamp = Date(timeIntervalSinceReferenceDate: fetchResult.timestamp.toCFAbsoluteTime())
            samples = if let samples = fetchResult.sample as? [Sample] {
                samples
            } else if let sample = fetchResult.sample as? Sample {
                [sample]
            } else {
                preconditionFailure("Unable to process fetch result \(fetchResult)")
            }
        }
    }
}


extension SensorKit.FetchResult: RandomAccessCollection {
    public var startIndex: Int {
        samples.startIndex
    }
    
    public var endIndex: Int {
        samples.endIndex
    }
    
    public subscript(position: Int) -> Sample {
        samples[position]
    }
}
