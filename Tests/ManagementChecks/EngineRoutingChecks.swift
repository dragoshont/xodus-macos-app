// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusCore
import XodusManagement

extension Checks {
    /// M3: the pure launch-routing decision. Every case pins (package type x
    /// per-game override x configured default x installed-runner availability) to
    /// the exact routed runner or explicit unavailability. A missing selected
    /// engine must refuse launch, never silently substitute another runner.
    func engineRoutingChecks() throws {
        let cases = try fixture("engine-routing-v1")["cases"]?.array ?? []
        check(cases.count >= 10, "Engine-routing corpus pins type x override x default x availability")
        for value in cases {
            guard let name = value["name"]?.string, let request = value["request"],
                  let expected = value["expected"] else {
                check(false, "Engine-routing case is well formed")
                continue
            }
            let packageType = request["packageType"]?.string
                .flatMap(PackageType.init(rawValue:)) ?? .unknown
            let override = request["override"]?.string.flatMap(RuntimeProviderKind.init(rawValue:))
            let defaultEngine = request["defaultEngine"]?.string.flatMap(RuntimeProviderKind.init(rawValue:))
            let availability = try (request["availability"].map { try $0.decode(RunnerAvailability.self) })
                ?? RunnerAvailability()
            let outcome = EngineRouting.decide(.init(packageType: packageType, override: override,
                defaultEngine: defaultEngine, availability: availability))
            check(outcome == expectedOutcome(expected),
                  "Engine routing: \(name)")
        }
        // Explicit invariant: an override wins over an installed default.
        check(EngineRouting.decide(.init(packageType: .win32, override: .gptk4, defaultEngine: .crossover,
            availability: RunnerAvailability([.crossover, .gptk4]))) == .routed(.gptk4, .perGameOverride),
              "A per-game override takes precedence over an installed configured default")
        // Explicit invariant: an uninstalled override never falls back to an installed runner.
        check(EngineRouting.decide(.init(packageType: .win32, override: .standaloneWine,
            defaultEngine: .crossover, availability: RunnerAvailability([.crossover]))) ==
            .unavailable(.overrideNotInstalled(.standaloneWine)),
              "An uninstalled override refuses launch instead of substituting the installed default")
    }

    private func expectedOutcome(_ value: JSONValue) -> EngineRoutingOutcome {
        if value["outcome"]?.string == "routed",
           let runner = value["runner"]?.string.flatMap(RuntimeProviderKind.init(rawValue:)),
           let reason = value["reason"]?.string.flatMap(EngineRoutingReason.init(rawValue:)) {
            return .routed(runner, reason)
        }
        let kind = value["kind"]?.string.flatMap(RuntimeProviderKind.init(rawValue:))
        switch value["unavailable"]?.string {
        case "overrideNotInstalled": return .unavailable(.overrideNotInstalled(kind ?? .crossover))
        case "defaultNotInstalled": return .unavailable(.defaultNotInstalled(kind ?? .crossover))
        default: return .unavailable(.noRunnerInstalled)
        }
    }
}
