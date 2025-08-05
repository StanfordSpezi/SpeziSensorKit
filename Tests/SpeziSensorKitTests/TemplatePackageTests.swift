//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import SpeziSensorKit
import XCTest


final class SpeziSensorKitTests: XCTestCase {
    func testSpeziSensorKit() throws {
        let SpeziSensorKit = SpeziSensorKit()
        XCTAssertEqual(SpeziSensorKit.stanford, "Stanford University")
    }
}
