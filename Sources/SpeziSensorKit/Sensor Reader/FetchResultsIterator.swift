//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//


extension SensorKit {
    /// A utility iterator that can be used to efficiently work with ``SensorKit/FetchResult`` arrays.
    ///
    /// ``SensorKit/FetchResult``s returned from SensorKit can, depending on the specific sensor type, contain one or multiple individual samples that are all associated with the same ``SensorKit-class/FetchResult/sensorKitTimestamp``.
    /// This iterator enables efficient iteration over `(timestamp: Date, sample: Sample)` tuples for the elements from one or more ``SensorKit-class/FetchResult``s,
    /// without the need to perform unnecessary intermediate allocations.
    /// Since some sensors can result in very large amounts of data, this can have a significant impact.
    public struct FetchResultsIterator<Sample: AnyObject & Hashable, FetchResults: Collection<FetchResult<Sample>>>: Sequence, IteratorProtocol {
        public typealias Element = (timestamp: Date, sample: Sample)
        
        private var state: State
        
        public init(_ fetchResults: FetchResults) {
            state = .init(fetchResults[...])
        }
        
        public init(_ fetchResult: FetchResult<Sample>) where FetchResults == CollectionOfOne<FetchResult<Sample>> {
            self.init(CollectionOfOne(fetchResult))
        }
        
        public mutating func next() -> Element? {
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
    }
}


extension SensorKit.FetchResultsIterator {
    private enum State {
        case active(
            current: LazyMapCollection<SensorKit.FetchResult<Sample>, Element>.Iterator,
            remaining: FetchResults.SubSequence
        )
        /// The iterator has reached its end. There are no more samples to yield.
        case exhausted
        
        init(_ fetchResults: FetchResults.SubSequence) {
            if let idx = fetchResults.firstIndex(where: { !$0.isEmpty }) {
                self = .active(
                    current: Self.process(fetchResults[idx]),
                    remaining: fetchResults.dropFirst(fetchResults.distance(from: fetchResults.startIndex, to: fetchResults.index(after: idx)))
                )
            } else {
                self = .exhausted
            }
        }
        
        private static func process(
            _ fetchResult: SensorKit.FetchResult<Sample>
        ) -> LazyMapSequence<SensorKit.FetchResult<Sample>, Element>.Iterator {
            fetchResult.lazy
                .map { [date = fetchResult.sensorKitTimestamp] sample in (date, sample) }
                .makeIterator()
        }
    }
}
