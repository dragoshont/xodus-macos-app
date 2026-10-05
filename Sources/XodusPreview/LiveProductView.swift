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
                Text(session.productSummary(product))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Catalog info") {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(product.editions) { edition in
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Edition \(edition.editionID)")
                                    .font(.headline)
                                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                                    facet("Access", edition.entitlement.kind.label)
                                    facet("PC package", edition.installability.kind.label)
                                    facet("Compatibility", edition.compatibility.kind.label)
                                    facet("This Mac", "Not checked")
                                }
                                Text("Access: \(edition.entitlement.source)")
                                Text("PC package: \(edition.installability.reason ?? "No package authorization established.")")
                                Text("Compatibility: \(edition.compatibility.source)")
                                Text("This Mac: installed-game listing isn't available. A selected-folder marker check doesn't identify this edition or prove installation.")
                                Divider()
                            }
                        }
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Catalog info for \(product.title)")
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
