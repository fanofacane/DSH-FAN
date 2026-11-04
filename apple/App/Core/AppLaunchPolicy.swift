// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// XCTest may launch its app host without the scheme's custom command-line argument.
enum AppLaunchPolicy {
    static var isUnitTestHost: Bool {
        isUnitTestHost(environment: ProcessInfo.processInfo.environment, arguments: ProcessInfo.processInfo.arguments)
    }
    static func isUnitTestHost(environment: [String: String], arguments: [String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        #if DEBUG
        return arguments.contains("-dsh-unit-tests")
        #else
        return false
        #endif
    }
}
