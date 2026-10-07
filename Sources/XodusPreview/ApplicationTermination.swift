// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@MainActor
final class ApplicationTerminationCoordinator {
    private var operation: Task<Bool, Never>?

    func shutdown(session: LiveSession?, runtime: RuntimeProviderSettings?,
                  installedGames: InstalledGamesController? = nil) async -> Bool {
        if let operation { return await operation.value }
        installedGames?.applicationTerminating = true
        runtime?.beginApplicationTermination()
        session?.applicationTerminating = true
        let pending = Task {
            async let runtimeClosed = runtime?.shutdownForApplicationTermination() ?? true
            async let managementClosed = session?.disconnect() ?? true
            let results = await (runtimeClosed, managementClosed)
            return results.0 && results.1
        }
        operation = pending
        let closed = await pending.value
        if !closed {
            installedGames?.applicationTerminating = false
            runtime?.resumeAfterTerminationRefusal()
            session?.applicationTerminating = false
            operation = nil
        }
        return closed
    }
}
