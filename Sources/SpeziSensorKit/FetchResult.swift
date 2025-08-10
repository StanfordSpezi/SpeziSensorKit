//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import SensorKit
import SpeziFoundation


extension SensorKit {
    /// A batch of samples returned by SensorKit
    public final class FetchResult<Sample: AnyObject & Hashable>: @unchecked Sendable {
        private enum State {
            case initial(SRFetchResult<AnyObject>)
            case processed([Sample])
        }
        
        private let sensor: Sensor<Sample>
        private let lock = RWLock()
        // protected by the lock
        private nonisolated(unsafe) var state: State
        
        /// The SensorKit framework's timestamp associated with this batch of samples
        public let sensorKitTimestamp: Date
        
        /// The samples.
        public var samples: [Sample] {
            lock.withWriteLock {
                switch state {
                case .initial(let fetchResult):
                    let samples: [Sample] = switch sensor.sensorKitFetchReturnType {
                    case .object:
                        [unsafeDowncast(fetchResult.sample, to: Sample.self)]
                    case .array:
                        Array(_immutableCocoaArray: unsafeDowncast(fetchResult.sample, to: NSArray.self))
                    }
                    state = .processed(samples)
                    return samples
                case .processed(let samples):
                    return samples
                }
            }
        }
        
        init(_ fetchResult: SRFetchResult<AnyObject>, for sensor: Sensor<Sample>) {
            self.sensor = sensor
            self.state = .initial(fetchResult)
            self.sensorKitTimestamp = Date(timeIntervalSinceReferenceDate: fetchResult.timestamp.toCFAbsoluteTime())
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


extension SensorKit.FetchResult: Hashable {
    public static func == (lhs: SensorKit.FetchResult<Sample>, rhs: SensorKit.FetchResult<Sample>) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
