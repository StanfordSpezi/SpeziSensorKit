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
    /// A utility iterator that can be used to efficiently work with ``SensorKit/FetchResult`` arrays.
    ///
    /// ``SensorKit/FetchResult``s returned from SensorKit can, depending on the specific sensor type, contain one or multiple individual samples that are 
    public struct FetchResultsIterator<Sample: AnyObject & Hashable, FetchResults: Collection<FetchResult<Sample>>>: Sequence, IteratorProtocol {
        private enum State {
            case active(
                current: LazyMapCollection<FetchResult<Sample>, (Date, Sample)>.Iterator,
                remaining: FetchResults.SubSequence
            )
            /// The iterator has reached its end. There are no more samples to yield.
            case exhausted
            
            init(_ fetchResults: FetchResults.SubSequence) {
                if let idx = fetchResults.firstIndex(where: { !$0.isEmpty }) {
                    self = .active(
                        current: FetchResultsIterator.process(fetchResults[idx]),
                        remaining: fetchResults.dropFirst(fetchResults.distance(from: fetchResults.startIndex, to: idx))
                    )
                } else {
                    self = .exhausted
                }
            }
        }
        
        private var state: State
        
        public init(_ fetchResults: FetchResults) {
            state = .init(fetchResults[...])
        }
        
        public mutating func next() -> (Date, Sample)? {
            switch state {
            case .exhausted:
                return nil
            case .active(var current, let remaining):
                if let next = current.next() {
                    state = .active(current: current, remaining: remaining)
                    return next
                } else {
                    // the FetchResult's iterator is empty, meaning that there are no more samples in the fetch result.
                    // we need to move on to the next batch.
                    // we do this by re-initializing the state with the remaining FetchResults,
                    // and then simply calling next() again.
                    state = .init(remaining)
                    return next()
                }
            }
        }
        
        private static func process(_ fetchResult: FetchResult<Sample>) -> LazyMapSequence<FetchResult<Sample>, (Date, Sample)>.Iterator {
            fetchResult.lazy
                .map { [date = fetchResult.sensorKitTimestamp] sample in (date, sample) }
                .makeIterator()
        }
    }
}
