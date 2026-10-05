// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

@MainActor
final class AccountInteraction: ObservableObject {
    @Published var confirmingSignOut = false
}

struct LiveAccountView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var session: LiveSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Environment(\.layoutDirection) private var layoutDirection
    @StateObject private var interaction = AccountInteraction()
#if !XODUS_SHIPPING
    var refreshStatusOnAppear = true
#endif

    var body: some View {
        AccountSheetLayout(showsHeader: false) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle").font(.largeTitle).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.accountNoticeTitle).font(.title2.bold())
                    }
                    Spacer()
                    if session.accountBusy || session.signInPending { ProgressView().controlSize(.small) }
                }
                Text(session.accountMessage)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("xodus.account.statusExplanation")
                if session.isReady && !session.supports(.authBegin) {
                    Text("Sign-in isn't available in this build.").foregroundStyle(.secondary)
                }
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(session.accountExplanation)
                        Text("Credentials stay in the native Keychain.")
                        if let summary = session.accountFailureSummary {
                            Text(summary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("xodus.account.failureSummary")
                        }
                        if let observation = session.accountFailureObservation {
                            Text(observation).accessibilityIdentifier("xodus.account.failureObservation")
                        }
                        if let error = session.errorMessage {
                            Text(error).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 12)
                }
            }
        } actions: {
            AccountActionsLayout(layoutDirection: layoutDirection) {
                Button(session.signInPending ? "Cancel sign-in" : "Close") {
                    Task {
                        let cancelling = session.signInPending
                        if cancelling { await session.cancelSignIn() }
                        if !session.signInPending,
                           !cancelling || session.authentication?.flow?.state != .completed { dismiss() }
                    }
                }
                .keyboardShortcut(.cancelAction).disabled(session.accountBusy)
                .accessibilityLabel(session.signInPending ? "Cancel sign-in" : "Close account")
                .accessibilityIdentifier(session.signInPending ? "xodus.account.cancelSignIn" : "xodus.account.close")
                if session.isReady {
                    Button("Check status") { Task { await session.refreshAccount() } }
                        .disabled(session.accountBusy)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Check account status")
                        .accessibilityIdentifier("xodus.account.checkStatus")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { Task { await session.refreshAccount() } }
                } else { Button("Settings", action: openSettings.callAsFunction) }
                if session.needsAccountDisconnect {
                    Button(session.currentCredentialState == .expired ? "Disconnect expired sign-in" : "Sign out") {
                        interaction.confirmingSignOut = true
                    }
                        .disabled(!session.canDisconnectAccount)
                } else {
                    GlassAction(title: "Sign in with Microsoft") {
                        if session.canSignIn { Task { await session.beginSignIn() } }
                    }
                        .disabled(!session.canSignIn)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Sign in with Microsoft")
                        .accessibilityIdentifier("xodus.account.signIn")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            if session.canSignIn { Task { await session.beginSignIn() } }
                        }
                }
            }
            .controlSize(.regular)
        }
        .task {
#if !XODUS_SHIPPING
            if !refreshStatusOnAppear { return }
#endif
            await session.refreshAccount()
        }
        .interactiveDismissDisabled(session.accountBusy || session.signInPending)
        .confirmationDialog("Sign out of Xodus on this Mac?", isPresented: $interaction.confirmingSignOut) {
            Button("Disconnect sign-in", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Xodus removes its launcher sign-in and invalidates account-bound evidence. Other apps' credentials and game saves are not removed.")
        }
    }
}

struct LiveSettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var session: LiveSession

    var body: some View {
        Form {
            Section("Xodus engine") {
#if XODUS_SHIPPING
                Text("Only this app's approved bundled engine and sign-in helper can be used. Gameplay runtime certification is separate.")
                    .foregroundStyle(.secondary)
#else
                Text("Development integration. Only choose a management engine you trust; signed runtime distribution is not implemented yet.")
                    .foregroundStyle(.secondary)
#endif
                LabeledContent("Build", value: session.backendPath.isEmpty ? "Not selected" : URL(fileURLWithPath: session.backendPath).lastPathComponent)
                HStack {
#if !XODUS_SHIPPING
                    Button("Choose Xodus build") { session.chooseBackend() }.disabled(session.connectionTransitioning)
#endif
                    Spacer()
                    Button(session.isReady ? "Reconnect" : "Connect") { Task { await session.connect() } }
                        .disabled(session.backendPath.isEmpty || session.connectionTransitioning)
                    if session.isReady {
                        Button("Disconnect") { Task { await session.disconnect() } }
                            .disabled(session.connectionTransitioning)
                    }
                }
                if let hello = session.hello {
                    LabeledContent("Management", value: "1.0")
                    LabeledContent("Backend", value: hello.backendVersion)
                    LabeledContent("Runtime", value: "Not certified for gameplay")
                }
                if let error = session.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                }
            }
            RuntimeProviderSection(settings: state.runtimeSettings, backendPath: session.backendPath)
            Section("Account") {
                LabeledContent("Status", value: session.accountLabel)
                Button("Open account") { state.showingAccount = true }
                DisclosureGroup("Details") { Text(session.accountExplanation).foregroundStyle(.secondary) }
            }
            Section("Advanced public catalog") {
                Text(session.supports(.query)
                     ? "Discover browses PC Game Pass titles or searches the public Microsoft Store. Neither source is an owned library."
                     : "Discover checks a bounded public PC Game Pass page. This engine searches checked products only, not the whole Store or an owned library.")
                    .foregroundStyle(.secondary)
                TextField("Market (for example US)", text: $session.market)
                TextField("Language (for example en-US)", text: $session.language)
                Button("Refresh catalog scope") { Task { await session.refreshCatalog(state.query) } }
                    .disabled(!session.isReady || session.searching)
                TextField("Public Store product ID", text: $session.lookupID)
                    .onSubmit { Task { await session.lookupProduct() } }
                HStack {
                    Button("Check public product") { Task { await session.lookupProduct() } }
                        .disabled(!session.supports(.enqueue) || session.lookupBusy)
                    if session.lookupBusy { ProgressView().controlSize(.small) }
                }
                Text("Checks public metadata only. It does not buy, authorize, download or install a game.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Button("Preview redacted diagnostic summary") { Task { await session.previewDiagnostics() } }
                    .disabled(!session.supports(.diagnostics) || session.diagnosticSaving || session.diagnosticPreviewing)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Preview redacted diagnostic summary")
                    .accessibilityIdentifier("xodus.diagnostics.preview")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { Task { await session.previewDiagnostics() } }
                if let preview = session.diagnosticPreview {
                    Text(preview).font(.callout).textSelection(.enabled)
                    Button("Save reviewed summary...") { session.chooseDiagnosticDestination() }
                        .disabled(session.diagnosticSaving)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Save reviewed diagnostic summary")
                        .accessibilityIdentifier("xodus.diagnostics.save")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { session.chooseDiagnosticDestination() }
                    Text("Only the summary shown above is saved, not raw engine logs or account data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if session.diagnosticPreviewing { ProgressView("Preparing summary") }
                if session.diagnosticSaving { ProgressView("Saving summary") }
                if session.diagnosticSaved {
                    Label("Diagnostic summary saved.", systemImage: "checkmark.circle")
                }
                if let error = session.diagnosticExportError {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped).padding()
        .frame(width: 560)
        .task { await state.runtimeSettings.refreshCrossOverDependency() }
    }
}
