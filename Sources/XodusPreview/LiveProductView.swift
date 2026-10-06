// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

struct LiveProductView: View {
    let product: CatalogProduct
    @EnvironmentObject private var session: LiveSession
    @Environment(\.dismiss) private var dismiss
    private var hero: CatalogArtworkReference? {
        CatalogArtworkReference.preferred(in: product.artwork, roles: [.hero])
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let hero {
                        CatalogArtworkView(reference: hero, status: product.artworkStatus)
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    HStack(alignment: .top, spacing: 18) {
                        CatalogArtworkView(reference: CatalogArtworkReference.preferred(
                            in: product.artwork, roles: [.boxArt, .poster, .tile, .hero]),
                            status: product.artworkStatus)
                            .frame(width: 80, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(product.title).font(.title.bold())
                            if product.freshness == "cached" {
                                Text("Offline details").foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    Text("Install and Play aren't available yet.")
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
                            Text("Public catalog presence doesn't establish access. Installation requires verified access, a package plan and a paired gameplay runtime.")
                            Text("Artwork: \(product.artworkStatus.rawValue). Image download failures don't change catalog metadata.")
                        }
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Catalog info for \(product.title)")
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(minWidth: 480, idealWidth: 600, maxWidth: 680,
               minHeight: 300, idealHeight: hero == nil ? 340 : 560, maxHeight: 680)
    }

    private func facet(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }

}
