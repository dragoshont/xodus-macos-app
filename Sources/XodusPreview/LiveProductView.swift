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
                        if product.freshness == "cached" {
                            Text("Offline details").foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                Divider()
                ForEach(Array(product.editions.enumerated()), id: \.element.id) { index, edition in
                    VStack(alignment: .leading, spacing: 15) {
                        Text(product.editions.count == 1 ? "Game details" : "Edition \(index + 1)").font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                            facet("Access", edition.entitlement.kind.label)
                            facet("PC package", edition.installability.kind.label)
                            facet("Compatibility", edition.compatibility.kind.label)
                            facet("This Mac", session.installationStatus(edition))
                        }
                        DisclosureGroup("Details") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Edition \(edition.editionID)")
                                Text("Access: \(edition.entitlement.source)")
                                Text("PC package: \(edition.installability.reason ?? "No package authorization established.")")
                                Text("Compatibility: \(edition.compatibility.source)")
                                Text("This Mac: Xodus management registry only; other game folders haven't been checked.")
                            }
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Divider()
                    }
                }
                if product.editions.isEmpty {
                    Label("No edition has been resolved. Installation is unavailable.", systemImage: "exclamationmark.circle")
                }
                Text("Install and Play aren't available in this build.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Catalog details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source: \(product.source)")
                        Text("Product \(product.productID)")
                        Text("\(product.market) / \(product.language) - \(product.freshness) metadata")
                        Text("Checked \(product.checkedAt)")
                        if let resolved = product.resolvedLanguage,
                           resolved.caseInsensitiveCompare(product.language) != .orderedSame {
                            Text("Source metadata language: \(resolved). Requested scope: \(product.language).")
                        }
                        Text("Public catalog presence doesn't establish access. Installation requires verified access, a package plan and a paired gameplay runtime. Artwork isn't supplied by this catalog.")
                    }
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(28)
        }
        .frame(width: 680, height: 620)
    }

    private func facet(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }

}
