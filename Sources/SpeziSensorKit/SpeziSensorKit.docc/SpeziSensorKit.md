# ``SpeziSensorKit``

<!--

This source file is part of the SpeziSensorKit open source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
       
-->

Interact with SensorKit in your Spezi application

## Overview
The Spezi HealthKit module enables apps to integrate with Apple's HealthKit system, fetch data, set up long-lived background data collection, and visualize Health-related data.

### Setup
You need to add the Spezi HealthKit Swift package to
 [your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) or
 [Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Spezi, follow the
 [Spezi setup article](https://swiftpackageindex.com/stanfordspezi/spezi/documentation/spezi/initial-setup) and set up the core Spezi infrastructure. 


### Example

```swift
import SpeziSensorKit

let reader = SensorReader(.)
```



## Topics

### The SensorKit Module
- ``SensorKit``

### Permission Handling
- ``SensorKit/authorizationStatus(for:)``
- ``SensorKit/requestAccess(to:)``

### Working with Sensors 
- ``Sensor``
- ``SensorReader``

### Supporting Types
- ``SensorKitActor``
