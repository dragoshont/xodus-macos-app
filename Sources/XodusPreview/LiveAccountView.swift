// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

@MainActor
final class AccountInteraction: ObservableObject {
    @Published var confirmingSignOut = false
}

struct LiveAccountView: View {
    @EnvironmentObject private var session: LiveSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @StateObject private var interaction = AccountInteraction()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .bottomLeading) {
                GameArtwork(kind: "orbit")
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                Text("Your account.\nSafely on your Mac.")
                    .font(.system(size: 32, weight: .bold)).foregroundStyle(.white).padding(24)
            }
            .frame(height: 210).clipped()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle").font(.largeTitle).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.accountLabel).font(.title2.bold())
                        Text("Xodus owns sign-in. Credentials stay in the native Keychain.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if session.accountBusy || session.signInPending { ProgressView().controlSize(.small) }
                }
                if session.signInPending {
                    Text("Complete Microsoft sign-in in the native authentication window. You can cancel without connecting an account.")
                        .fixedSize(horizontal: false, vertical: true)
                } else if session.authentication == nil && session.isReady {
                    Text("Check your saved sign-in or sign in with Microsoft. Public browsing does not read your Keychain.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if let flow = session.authentication?.flow {
                    if flow.state == .cancelled {
                        Label("Sign-in cancelled. No new connection was assumed.", systemImage: "xmark.circle")
                    } else if flow.state == .failed {
                        Label("Sign-in did not complete. Try again when you are ready.", systemImage: "exclamationmark.circle")
                    }
                }
                if session.authentication?.state == .expired || session.authentication?.state == .invalid {
                    Text("Disconnect this saved launcher sign-in first, then connect again. Other apps' accounts are not changed.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if session.authentication?.state == .credentialPresent {
                    Label("Saved Microsoft sign-in is not proof of PC ownership, package access or gameplay compatibility.",
                          systemImage: "info.circle").foregroundStyle(.secondary)
                } else if session.isReady && !session.supports(.authBegin) {
                    Text("This engine can check existing Keychain sign-in, but its native sign-in provider is not available yet.")
                        .foregroundStyle(.secondary)
                }
                if let error = session.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                HStack {
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
                    Spacer()
                    if session.needsAccountDisconnect {
                        Button(session.authentication?.state == .expired ? "Disconnect expired sign-in" : "Sign out") {
                            interaction.confirmingSignOut = true
                        }
                            .disabled(!session.canDisconnectAccount)
                    } else {
                        GlassAction(title: "Sign in with Microsoft") { Task { await session.beginSignIn() } }
                            .disabled(!session.canSignIn)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28)
        }
        .frame(width: 650)
        .task { await session.refreshAccount() }
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
                Text("Development integration. Only choose a management engine you trust; signed runtime distribution is not implemented yet.")
                    .foregroundStyle(.secondary)
                LabeledContent("Build", value: session.backendPath.isEmpty ? "Not selected" : URL(fileURLWithPath: session.backendPath).lastPathComponent)
                HStack {
                    Button("Choose Xodus build") { session.chooseBackend() }.disabled(session.phase == .connecting)
                    Spacer()
                    Button(session.isReady ? "Reconnect" : "Connect") { Task { await session.connect() } }
                        .disabled(session.backendPath.isEmpty || session.phase == .connecting)
                    if session.isReady { Button("Disconnect") { Task { await session.disconnect() } } }
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
            Section("Account") {
                LabeledContent("Status", value: session.accountLabel)
                Button("Open account") { state.showingAccount = true }
                Text("Microsoft sign-in, PC ownership and package authorization are independent.")
                    .foregroundStyle(.secondary)
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
                    .disabled(!session.supports(.diagnostics))
                if let preview = session.diagnosticPreview {
                    Text(preview).font(.callout).textSelection(.enabled)
                }
            }
            Section("Original design preview") {
                Button("Open offline fixture preview") {
                    Task {
                        guard await session.disconnect() else { return }
                        state.reset()
                        state.fixtureMode = true
                    }
                }
                Text("Invented games and simulated actions remain in a separate, explicitly labelled mode.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding()
        .frame(width: 560)
    }
}
