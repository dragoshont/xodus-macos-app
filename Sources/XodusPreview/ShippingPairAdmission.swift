// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusManagement

struct ShippingPairIdentity: Sendable {
    let schemaVersion: Int
    let appSourceCommit: String
    let appSourceTree: String
    let producerCommit: String
    let producerTree: String
    let engineSHA256: String
    let engineBytes: Int64
    let helperSHA256: String
    let helperBytes: Int64
    let helperVersion: Int
    let helperSourceCommit: String
}

enum ShippingPairAdmission {
    static func configuration(bundle: Bundle, stateDirectory: URL,
                              pins: ShippingPairIdentity?) throws -> BackendConfiguration {
        guard let pins, pins.schemaVersion == 1,
              pins.appSourceCommit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              pins.appSourceTree.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              pins.producerCommit == "9faa8755683b88ca95bd17012d82c89e2f1a58ce",
              pins.producerTree == "4b937ec03f8d2cf9ddde9132a9351a82a9c83c6a",
              pins.helperVersion == 1, pins.helperSourceCommit == pins.appSourceCommit,
              pins.engineBytes > 0, pins.helperBytes > 0,
              bundle.bundleURL.pathExtension == "app" else {
            throw ManagementError.pairedEngineUnavailable
        }
        do {
            guard let receipt = try NativeAuthHostBinding.bundled(
                in: bundle, expectedSourceCommit: pins.appSourceCommit),
                  receipt.sha256 == pins.helperSHA256, receipt.version == pins.helperVersion else {
                throw ManagementError.pairedEngineUnavailable
            }
            let engine = bundle.bundleURL.appendingPathComponent("Contents/Resources/XodusEngine/xodus-cli")
            let engineIdentity = NativeAuthHostBinding(executable: engine, sha256: pins.engineSHA256,
                                                       expectedBytes: pins.engineBytes)
            let helper = NativeAuthHostBinding(executable: receipt.executable, sha256: pins.helperSHA256,
                                               expectedBytes: pins.helperBytes)
            _ = try engineIdentity.validatedArguments()
            _ = try helper.validatedArguments()
            return BackendConfiguration(executable: engine, stateDirectory: stateDirectory,
                                        nativeAuthHost: helper, executableIdentity: engineIdentity)
        } catch { throw ManagementError.pairedEngineUnavailable }
    }
}
