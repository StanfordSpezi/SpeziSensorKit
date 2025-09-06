//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Observation
@_documentation(visibility: internal) @_exported @preconcurrency public import SensorKit
public import Spezi
import SpeziFoundation
import SpeziLocalStorage


/// Interact with SensorKit in your Spezi application
///
/// ## Topics
///
/// ### Initializers
/// - ``init()``
///
/// ### Authorization Handling
/// - ``authorizationStatus(for:)``
/// - ``requestAccess(to:)``
@Observable
public final class SensorKit: Module, EnvironmentAccessible, @unchecked Sendable {
    @ObservationIgnored @Dependency(LocalStorage.self) private var localStorage
    
    private let queryAnchorKeys = LocalStorageKeysStore<QueryAnchor> { sensor in
        LocalStorageKey("edu.stanford.SpeziSensorKit.QueryAnchors.\(sensor.id)")
    }
    
    /// Creates a new instance of the `SensorKit` module.
    public nonisolated init() {}
    
    // MARK: Authorization
    
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
    
    
    // MARK: Data Exporting
    @available(iOS 18, *)
    @SensorKitActor
    public func fetchAnchored<Sample>(_ sensor: Sensor<Sample>) async throws -> some AsyncSequence<[FetchResult<Sample>], any Error> {
        let anchor = await ManagedQueryAnchor(
            storageKey: queryAnchorKeys.key(for: sensor),
            in: localStorage
        )
        let reader = SensorReader(sensor)
        let batched = try await reader.fetchBatched(anchor: anchor)
        return batched
    }
    
    /// Resets the query anchor for the specified sensor.
    ///
    /// This will cause subsequent calls to ``fetchAnchored(_:)`` to potentially re-fetch already-processed samples.
    public func resetQueryAnchor(for sensor: Sensor<some Any>) throws {
        try localStorage.delete(queryAnchorKeys.key(for: sensor))
    }
}


// MARK: Utils

extension SensorKit {
    // Essentially just a thread-safe dictionary that keeps track of our `LocalStorageKey`s used by the `SampleTypeScopedLocalStorage`.
    // The reason this exists is bc the LocalStorage API is intended to be used with long-lived LocalStorageKey objects, which doesn't easily
    // work with the multi-key scoping approach we're using here.
    // Were we not to use something like this for caching and re-using the keys, we'd need to create temporary `LocalStorageKey`s for
    // every load/store operation, which would of course work but would also defeat the whole purpose of having the `LocalStorageKey`s
    // be long-lived objects which are also used for e.g. locking / properly handling concurrent reads or writes.
    final class LocalStorageKeysStore<Value>: Sendable {
        private struct DictKey: Hashable {
            let valueType: String
            let sampleType: String
            
            init(sensor: some AnySensor<some Any>) {
                // this is fine bc we're not using it as a stable identifier
                // (the `valueType` key must only be valid&unique for the lifetime of the app)
                self.valueType = String(reflecting: Value.self)
                self.sampleType = sensor.id
            }
        }
        
        private let makeKey: @Sendable (any AnySensor) -> LocalStorageKey<Value>
        private let lock = RWLock()
        nonisolated(unsafe) private var keys: [DictKey: LocalStorageKey<Value>] = [:]
        
        init(makeKey: @escaping @Sendable (any AnySensor) -> LocalStorageKey<Value>) {
            self.makeKey = makeKey
        }
        
        func key(for sensor: some AnySensor<some Any>) -> LocalStorageKey<Value> {
            lock.withWriteLock {
                let dictKey = DictKey(sensor: sensor)
                if let key = keys[dictKey] {
                    return key
                } else {
                    let key = makeKey(sensor)
                    keys[dictKey] = key
                    return key
                }
            }
        }
    }
    
    
    struct SensorScopedLocalStorage<Value: SendableMetatype>: Sendable {
        private let localStorage: LocalStorage
        private let localStorageKeysStore: LocalStorageKeysStore<Value>
        
        init(localStorage: LocalStorage, localStorageKeysStore: LocalStorageKeysStore<Value>) {
            self.localStorage = localStorage
            self.localStorageKeysStore = localStorageKeysStore
        }
        
        private func storageKey(for sensor: Sensor<some Any>) -> LocalStorageKey<Value> {
            localStorageKeysStore.key(for: sensor)
        }
        
        subscript(sensor: Sensor<some Any>) -> Value? {
            get {
                try? localStorage.load(storageKey(for: sensor))
            }
            nonmutating set {
                try? localStorage.store(newValue, for: storageKey(for: sensor))
            }
        }
    }
}
