// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusCore
import XodusManagement

@MainActor
final class RuntimeProviderSettings: ObservableObject {
    @Published private(set) var configuration: RuntimeProviderConfiguration?
    @Published private(set) var plan: RuntimeConfigurationPlan?
    @Published private(set) var planning = false
    @Published private(set) var errorMessage: String?
    private let client = RuntimePlanClient()
    private var task: Task<Void, Never>?
    private var revision = UUID()

    func select(_ provider: RuntimeProviderKind?) {
        invalidate()
        configuration = provider.map(RuntimeProviderConfiguration.preset)
    }

    func update(_ change: (inout RuntimeProviderConfiguration) -> Void) {
        guard var value = configuration else { return }
        invalidate()
        change(&value)
        configuration = value
    }

    func cancel() {
        guard planning else { return }
        task?.cancel()
        errorMessage = RuntimePlanningError.cancelled.localizedDescription
    }

    private func invalidate() {
        task?.cancel()
        revision = UUID()
        plan = nil
        errorMessage = nil
    }

    func makePlan(executable: URL) {
        guard let configuration, !planning else { return }
        invalidate()
        let captured = revision
        planning = true
        task = Task {
            do {
                let result = try await client.plan(executable: executable, configuration: configuration)
                if captured == revision && !Task.isCancelled { plan = result }
            } catch {
                if captured == revision {
                    errorMessage = (error as? RuntimePlanningError)?.localizedDescription
                        ?? RuntimePlanningError.transportFailed.localizedDescription
                }
            }
            planning = false
            task = nil
        }
    }

    func text(_ path: WritableKeyPath<RuntimeProviderConfiguration, String?>) -> Binding<String> {
        Binding(get: { self.configuration?[keyPath: path] ?? "" },
                set: { text in self.update { $0[keyPath: path] = text.isEmpty ? nil : text } })
    }
}

struct RuntimeProviderSection: View {
    @ObservedObject var settings: RuntimeProviderSettings
    let backendPath: String

    var body: some View {
        Section("Runtime configuration") {
            Picker("Runtime provider", selection: Binding(
                get: { settings.configuration?.provider }, set: { settings.select($0) })) {
                Text("Choose a provider").tag(Optional<RuntimeProviderKind>.none)
                ForEach(RuntimeProviderKind.allCases, id: \.self) { provider in
                    Text(provider.label).tag(Optional(provider))
                }
            }
            .disabled(settings.planning)
            Text("Configuration only. This does not inspect, download or license a runtime, create a prefix, or enable Play.")
                .foregroundStyle(.secondary)
            if let configuration = settings.configuration {
                if configuration.provider == .crossover {
                    Text("Use your own legitimately installed and licensed CrossOver. Xodus does not include or copy CrossOver.")
                        .foregroundStyle(.secondary)
                }
                TextField("Provider version (unknown if blank)", text: settings.text(\.providerVersion))
                    .disabled(settings.planning)
                DisclosureGroup("Declared engine and graphics components") {
                    if configuration.provider == .standaloneWine {
                        Picker("Wine source", selection: Binding(
                            get: { settings.configuration?.engine.provenance ?? .userSelectedWine },
                            set: { source in settings.update { $0.engine.provenance = source } })) {
                            Text("User-selected Wine").tag(RuntimeEngineProvenance.userSelectedWine)
                            Text("User-selected source build").tag(RuntimeEngineProvenance.userSelectedSourceBuild)
                        }
                    } else {
                        LabeledContent("Wine source", value: configuration.engine.provenance.label)
                    }
                    TextField("Wine version (unknown if blank)", text: settings.text(\.engine.version))
                    TextField("Wine SHA-256 (unknown if blank)", text: settings.text(\.engine.artifactSha256))
                    Picker("Graphics backend", selection: Binding(
                        get: { settings.configuration?.graphics.backend },
                        set: { backend in
                            settings.update { value in
                                value.graphics = backend.map {
                                    RuntimeGraphicsConfiguration(backend: $0, provenance: .userSelected)
                                } ?? .init()
                            }
                        })) {
                        Text("Not declared").tag(Optional<RuntimeGraphicsBackend>.none)
                        ForEach(RuntimeGraphicsBackend.allCases, id: \.self) { backend in
                            Text(backend.label).tag(Optional(backend))
                        }
                    }
                    if configuration.graphics.backend != nil {
                        Picker("Graphics source", selection: Binding(
                            get: { settings.configuration?.graphics.provenance ?? .userSelected },
                            set: { provenance in settings.update { $0.graphics.provenance = provenance } })) {
                            Text("Apple toolkit").tag(RuntimeGraphicsProvenance.appleToolkit)
                            Text("CrossOver bundled").tag(RuntimeGraphicsProvenance.crossOverBundled)
                            Text("Engine bundled").tag(RuntimeGraphicsProvenance.engineBundled)
                            Text("User selected").tag(RuntimeGraphicsProvenance.userSelected)
                        }
                        TextField("Graphics version (unknown if blank)", text: settings.text(\.graphics.version))
                        TextField("Graphics SHA-256 (unknown if blank)", text: settings.text(\.graphics.artifactSha256))
                    }
                }
                .disabled(settings.planning)
                Text("Versions and hashes are your declarations, not installation or gameplay evidence. Engine and graphics identities are independent; changing either requires a fresh isolated plan.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Plan isolated configuration") {
                    settings.makePlan(executable: URL(fileURLWithPath: backendPath))
                }
                .disabled(settings.configuration == nil || backendPath.isEmpty || settings.planning)
                if settings.planning {
                    ProgressView().controlSize(.small)
                    Button("Cancel planning") { settings.cancel() }
                }
            }
            if let plan = settings.plan {
                LabeledContent("Planned generation", value: plan.generationID)
                Text("Installation not inspected. Device preflight not performed. No game verified; Play remains unavailable.")
                    .foregroundStyle(.secondary)
                Text("No existing bottle, prefix or saves were reused, migrated or deleted. This plan creates no files.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = settings.errorMessage {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
        }
    }
}
