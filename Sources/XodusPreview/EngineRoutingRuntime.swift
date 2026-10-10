// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusCore

/// The configurable default engine (M3). Persisted in `UserDefaults` alongside the
/// existing developer backend key, so a chosen default survives relaunch.
enum EngineDefaults {
    static let defaultEngineKey = "Xodus.defaultEngine"
    static let backendPathKey = "Xodus.developerBackendPath"

    static func defaultEngine(_ defaults: UserDefaults = .standard) -> RuntimeProviderKind? {
        defaults.string(forKey: defaultEngineKey).flatMap(RuntimeProviderKind.init(rawValue:))
    }

    static func setDefaultEngine(_ kind: RuntimeProviderKind?, _ defaults: UserDefaults = .standard) {
        if let kind { defaults.set(kind.rawValue, forKey: defaultEngineKey) }
        else { defaults.removeObject(forKey: defaultEngineKey) }
    }

    static func backendPath(_ defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: backendPathKey)
    }
}

/// Observes which runners are actually installed. CrossOver is verified by its
/// signed bundle (the app's existing release dependency); a non-CrossOver engine
/// counts as installed only when the user's selected engine binary is a real
/// executable on disk. Nothing here is hardcoded — absence means not installed.
enum RunnerAvailabilityDetector {
    static func detect(
        crossOver: CrossOverDependencyState = CrossOverDetector.detect(),
        defaultEngine: RuntimeProviderKind? = EngineDefaults.defaultEngine(),
        backendPath: String? = EngineDefaults.backendPath(),
        probe: (URL) -> Bool = RunnerAvailabilityDetector.isExecutable
    ) -> RunnerAvailability {
        var installed: Set<RuntimeProviderKind> = []
        if crossOver.isVerified { installed.insert(.crossover) }
        if let defaultEngine, defaultEngine != .crossover,
           let backendPath, !backendPath.isEmpty, probe(URL(fileURLWithPath: backendPath)) {
            installed.insert(defaultEngine)
        }
        return RunnerAvailability(installed)
    }

    static func isExecutable(_ url: URL) -> Bool {
        (try? InstalledGameFiles.checkLauncher(url)) != nil
    }
}
