// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

struct LiveProductView: View {
    let product: CatalogProduct
    @EnvironmentObject private var session: LiveSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "gamecontroller").font(.largeTitle)
                        .frame(width: 80, height: 80)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(product.title).font(.title.bold())
                        Text("Public catalog - not ownership evidence").foregroundStyle(.secondary)
                        Text("\(product.market) / \(product.language) - \(product.freshness) metadata")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("Artwork is not provided by this integration. No placeholder is presented as this game's cover.")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                ForEach(product.editions) { edition in
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Edition \(edition.editionID)").font(.headline).textSelection(.enabled)
                        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                            facet("Access", edition.entitlement.kind.label,
                                  source: edition.entitlement.source)
                            facet("PC package", edition.installability.kind.label,
                                  source: edition.installability.reason ?? "No package authorization established.")
                            facet("Compatibility", edition.compatibility.kind.label,
                                  source: edition.compatibility.source)
                            facet("This Mac", installationStatus(edition),
                                  source: "Managed registry only; other game folders have not been checked.")
                        }
                        Divider()
                    }
                }
                if product.editions.isEmpty {
                    Label("No edition has been resolved. Installation is unavailable.", systemImage: "exclamationmark.circle")
                }
                Text("Install and Play are unavailable: authoritative PC access, a verified package plan and a signed paired runtime have not been established.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Checked \(product.checkedAt)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(28)
        }
        .frame(width: 680, height: 620)
    }

    private func facet(_ title: String, _ value: String, source: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                Text(source).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
    }

    private func installationStatus(_ edition: ProductEvidence) -> String {
        guard let snapshot = session.installedSnapshot else { return "Not checked" }
        let matches = snapshot.installations.filter {
            $0.productID == edition.productID && $0.editionID == edition.editionID
        }
        return matches.isEmpty ? "Not in managed registry" : matches.map { $0.health.label }.joined(separator: ", ")
    }
}
