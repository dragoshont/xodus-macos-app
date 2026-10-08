// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct GameCompatibilityBadge: View {
    @ObservedObject var operations: GameOperationsController
    let productID: String
    var allowsLoading = true

    var body: some View {
        Group {
            if let result = operations.compatibility[productID] {
                Text(result.badge).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            } else if let error = operations.compatibilityErrors[productID] {
                Text(error).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: productID) { if allowsLoading { await operations.loadCompatibility(productID: productID) } }
    }
}

struct GameServiceAccountView: View {
    @ObservedObject var operations: GameOperationsController
    @ObservedObject var library: PCGamesController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Games").font(.headline)
            if library.hasSavedSignIn {
                HStack {
                    Label("PC Library sign-in saved", systemImage: "checkmark.circle")
                    Spacer()
                    Button("Sign out of PC games") { Task { await library.signOut() } }
                        .disabled(library.busy).accessibilityIdentifier("xodus.pcGames.signOut")
                }
            }
            Text("Sign in to download and play. Your PC Library uses its own sign-in.")
                .font(.callout).foregroundStyle(.secondary)
            Label(operations.serviceLabel, systemImage: operations.serviceStatus?.signedIn == true
                  ? "checkmark.circle" : "person.crop.circle")
                .accessibilityIdentifier("xodus.games.accountStatus")
            HStack {
                Button("Check game sign-in") { operations.refreshService() }
                    .disabled(operations.serviceBusy || operations.setupRepairing)
                    .accessibilityIdentifier("xodus.games.checkSignIn")
                if operations.serviceStatus?.signedIn != true {
                    Button("Sign in for games") { operations.signInForGames() }
                        .disabled(!operations.canSignIn)
                        .accessibilityIdentifier("xodus.games.signIn")
                }
                if operations.serviceBusy { ProgressView().controlSize(.small) }
            }
            if operations.serviceSigningIn {
                Text("Finish signing in in the Microsoft window.").foregroundStyle(.secondary)
            }
            if let error = operations.serviceError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("xodus.games.signInError")
                if operations.serviceLog != nil {
                    Button("Show log") { operations.showServiceLog() }
                        .accessibilityIdentifier("xodus.games.signInLog")
                }
            }
            Divider()
            GamePassAccountView(operations: operations, library: library)
            Divider()
            GameSetupView(operations: operations)
        }
    }
}

struct GamePassAccountView: View {
    @ObservedObject var operations: GameOperationsController
    @ObservedObject var library: PCGamesController
    @EnvironmentObject private var session: LiveSession

    private var probeID: String? {
        GameOperationsController.gamePassProbes(discoveryProducts: session.gamePassProducts,
                                                ownedGames: library.snapshot?.games,
                                                compatibility: operations.compatibility).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(operations.gamePassLabel)
                    .accessibilityIdentifier("xodus.gamePass.status")
                Spacer()
                Button("Check") {
                    operations.checkGamePass(discoveryProducts: session.gamePassProducts,
                                             ownedGames: library.snapshot?.games)
                }
                .disabled(!operations.canStartMutation || operations.installConsent != nil
                    || operations.uninstallConsent != nil || probeID == nil)
                .accessibilityLabel("Check PC Game Pass")
                .accessibilityIdentifier("xodus.gamePass.check")
                if operations.gamePassBusy { ProgressView().controlSize(.small) }
            }
            if operations.gamePassFromCache {
                Text("Saved status on this Mac. Check to refresh.").font(.callout).foregroundStyle(.secondary)
            }
            if probeID == nil {
                Text("Load your PC library and browse Discover to check PC Game Pass.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = operations.gamePassError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if operations.gamePassFailureCode == 11 {
                    Button("Sign in for games") { operations.signInForGames() }
                        .disabled(!operations.canSignIn)
                }
                if operations.gamePassLog != nil {
                    Button("Show log") { operations.showGamePassLog() }
                        .accessibilityIdentifier("xodus.gamePass.showLog")
                }
            }
        }
    }
}

struct GameOperationProgressView: View {
    @ObservedObject var operations: GameOperationsController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let operation = operations.operation {
                Text(operation.title).font(.headline)
                if operations.recoveryRequired {
                    Button("Check last operation") { Task { await operations.reconcile() } }
                        .disabled(operations.checkingRecovery)
                        .accessibilityIdentifier("xodus.install.checkRecovery")
                } else {
                    Text(operations.cancelling ? "Stopping installation"
                         : operation.kind == .uninstall ? "Uninstalling"
                         : operations.progress?.phase.title ?? "Preparing download")
                        .foregroundStyle(.secondary)
                    if let value = operations.progress, let total = value.bytesTotal, total > 0 {
                        ProgressView(value: Double(value.bytesDone), total: Double(total))
                            .accessibilityLabel("Download progress")
                            .accessibilityIdentifier("xodus.install.progress")
                        Text("\(Self.bytes(value.bytesDone)) of \(Self.bytes(total)) (\(Int(Double(value.bytesDone) / Double(total) * 100))%)")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                        if let value = operations.progress {
                            Text("\(Self.bytes(value.bytesDone)) downloaded").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if operations.canCancel {
                        Button("Cancel installation") { Task { await operations.cancelInstall() } }
                            .accessibilityIdentifier("xodus.install.cancel")
                    }
                }
            }
            if let error = operations.error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("xodus.install.error")
                if operations.failureCode == 11 {
                    Button("Sign in for games") { operations.signInForGames() }
                        .disabled(!operations.canSignIn)
                        .accessibilityIdentifier("xodus.install.signIn")
                }
                if operations.log != nil {
                    Button("Show log") { operations.showLog() }
                        .accessibilityIdentifier("xodus.install.showLog")
                }
            }
            if let notice = operations.notice {
                Label(notice, systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    .accessibilityIdentifier("xodus.install.result")
            }
        }
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

struct GameInstallConsentView: View {
    @ObservedObject var operations: GameOperationsController
    let consent: GameInstallConsent

    var body: some View {
        let consent = operations.installConsent ?? self.consent
        VStack(alignment: .leading, spacing: 18) {
            Text(consent.installedID == nil ? "Install \(consent.game.title)" : "Check for update / Repair")
                .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            if consent.installedID != nil { Text(consent.game.title).font(.headline) }
            LabeledContent("Destination") { Text(consent.destination.path).textSelection(.enabled) }
            LabeledContent("Available space", value: GameOperationProgressView.bytes(consent.freeBytes))
            if operations.checkingCompatibility {
                ProgressView("Checking this game\u{2026}").controlSize(.small)
                    .accessibilityIdentifier("xodus.install.checking")
            } else if let result = consent.compatibility {
                Label(result.explanation, systemImage: result.supported ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("xodus.install.compatibility")
                if result.supported {
                    if let bytes = result.packageBytes {
                        Text("\(GameOperationProgressView.bytes(bytes)) download").foregroundStyle(.secondary)
                    } else { Text("Size shown when download starts").foregroundStyle(.secondary) }
                }
            } else if let error = consent.checkError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if operations.failureCode == 11 {
                    Button("Sign in for games") {
                        operations.installConsent = nil
                        operations.signInForGames()
                    }.disabled(!operations.canSignIn)
                }
                if operations.log != nil { Button("Show log") { operations.showLog() } }
            }
            if consent.compatibility?.supported == true {
                Text(consent.installedID == nil
                     ? "The game will be downloaded and set up for this Mac. Some PC packages aren't supported yet."
                     : "Xodus checks for changed or missing files in this folder. Your saves and installed entry are kept.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { Task { await operations.cancelInstallConsent() } }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("xodus.install.cancelConsent")
                Button(consent.installedID == nil ? "Install" : "Check and repair") { operations.confirmInstall(consent) }
                    .disabled(!operations.canConfirmInstall).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("xodus.install.confirm")
            }
        }
        .padding(28).frame(width: 520)
    }
}

struct GameOperationPresentation: View {
    @ObservedObject var operations: GameOperationsController

    var body: some View {
        Color.clear
            .sheet(item: $operations.installConsent) { consent in
                GameInstallConsentView(operations: operations, consent: consent)
                    .interactiveDismissDisabled(operations.checkingCompatibility)
            }
            .sheet(item: $operations.uninstallConsent) { game in
                VStack(alignment: .leading, spacing: 18) {
                    Text("Uninstall \(game.title)?").font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Deletes the game files. Your saves are kept.").foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Cancel") { operations.uninstallConsent = nil }.keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier("xodus.installed.cancelUninstall")
                        Button("Uninstall", role: .destructive) { operations.confirmUninstall(game) }
                            .disabled(!operations.canStartMutation)
                            .accessibilityIdentifier("xodus.installed.confirmUninstall")
                    }
                }.padding(28).frame(width: 480)
            }
    }
}

struct InstalledGameActions: View {
    @ObservedObject var library: InstalledGamesController
    @ObservedObject var operations: GameOperationsController
    let game: InstalledGame
    var usesGlass = false
    var heroStyle = false

    var body: some View {
        Menu {
            InstalledGameManagement(library: library, operations: operations, game: game)
        } label: {
            if heroStyle {
                Image(systemName: "ellipsis").font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28).accessibilityHidden(true)
            } else { Image(systemName: "ellipsis").accessibilityHidden(true) }
        }
        .menuIndicator(usesGlass ? .hidden : .automatic)
        .modifier(LibraryActionStyle(primary: false, usesGlass: usesGlass))
        .modifier(LibraryHeroControlSize(enabled: heroStyle))
        .buttonBorderShape(heroStyle ? .circle : .automatic)
        .fixedSize()
        .accessibilityLabel("Actions for \(game.title)")
    }
}

struct InstalledGameManagement: View {
    @ObservedObject var library: InstalledGamesController
    @ObservedObject var operations: GameOperationsController
    let game: InstalledGame

    var body: some View {
        Group {
            Button("Check for update / Repair") {
                Task { await operations.prepareInstall(PCGame(id: game.storeId, title: game.title, artwork: nil),
                                                        repairing: game) }
            }
            .disabled(!operations.canStartMutation || library.runningGameID == game.id)
            .accessibilityIdentifier("xodus.installed.repair")
            Button("Remove from list") { Task { await library.remove(game) } }
                .disabled(library.editing || library.choosing || library.mutationActive || library.runningGameID == game.id)
                .accessibilityIdentifier("xodus.installed.remove")
            Divider()
            Button("Uninstall…", role: .destructive) { operations.prepareUninstall(game) }
                .disabled(!operations.canStartMutation || library.runningGameID == game.id)
                .accessibilityIdentifier("xodus.installed.uninstall")
        }
    }
}
