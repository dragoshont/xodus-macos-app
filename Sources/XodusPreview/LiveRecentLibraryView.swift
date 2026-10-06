// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XodusManagement

enum RecentPlatformFilter: String, CaseIterable {
    case all = "All platforms", pc = "PC", console = "Console"

    func includes(_ platform: RecentLibraryPlatform) -> Bool {
        switch self {
        case .all: true
        case .pc: platform == .pc || platform == .mixed
        case .console: platform == .console || platform == .mixed
        }
    }
}

@MainActor
private final class RecentLibrarySelection: ObservableObject {
    @Published var platform: RecentPlatformFilter = .all
}

struct LiveRecentLibraryView: View {
    let query: String
    let openAccount: () -> Void
    let findInStore: (String) -> Void
    @EnvironmentObject private var session: LiveSession
    @StateObject private var selection = RecentLibrarySelection()

    private var titles: [RecentLibraryTitle] {
        (session.recentLibrary?.titles ?? []).filter {
            selection.platform.includes($0.platform) && (query.isEmpty || $0.name.localizedStandardContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your games").font(.largeTitle.bold())
                    Text("Recently played").foregroundStyle(.secondary)
                }
                Spacer()
                if session.recentLibraryLoading || session.recentLibraryBootstrapRunning {
                    ProgressView().controlSize(.small)
                }
                if session.recentLibrary != nil {
                    Picker("Platform", selection: $selection.platform) {
                        ForEach(RecentPlatformFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu).fixedSize()
                }
                if session.recentLibrary != nil {
                    Button("Refresh") { Task { await session.reloadRecentLibrary() } }
                        .disabled(!session.canLoadRecentLibrary)
                }
            }
            if session.recentLibrary != nil, let notice = session.recentLibraryNotice {
                Label(notice, systemImage: session.recentLibraryError == nil ? "clock" : "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            if let snapshot = session.recentLibrary {
                if titles.isEmpty {
                    ContentUnavailableView {
                        Label(snapshot.titles.isEmpty ? "No recent games" : "No matching games",
                              systemImage: "gamecontroller")
                    } description: {
                        Text(snapshot.titles.isEmpty ? "Microsoft returned no recent titles."
                             : "Try another search or platform.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    if query.isEmpty, selection.platform == .all, let first = snapshot.titles.first,
                       let artwork = CatalogArtworkReference.preferred(
                        in: first.artwork, roles: [.tile, .hero, .boxArt, .poster]) {
                        featured(first, artwork: artwork)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 24)],
                              alignment: .leading, spacing: 28) {
                        ForEach(titles) { title in
                            VStack(alignment: .leading, spacing: 10) {
                                CatalogArtworkView(reference: CatalogArtworkReference.preferred(
                                    in: title.artwork, roles: [.tile, .boxArt, .poster, .hero]),
                                    status: title.artworkStatus)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(title.name).font(.headline).lineLimit(2)
                                    .frame(minHeight: 40, alignment: .topLeading)
                                Text(title.platform.label).font(.caption).foregroundStyle(.secondary)
                                storeAction(for: title)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .contain)
                        }
                    }
                }
                DisclosureGroup("Recent activity info") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("One partial window of played history, not ownership, installation or Mac compatibility. No Store product mapping is established.")
                        Text("Source: Xbox TitleHub. Checked \(snapshot.checkedAt).")
                        Text(session.recentLibraryCurrent ? "Live read." : "Retained, unconfirmed activity.")
                        Text("Personal history stays in memory. Account checks, sign-out and connection changes clear it.")
                    }
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } else if session.recentLibraryBootstrapRunning || session.accountStatusChecking || session.recentLibraryLoading {
                VStack(spacing: 12) {
                    ProgressView(session.recentLibraryLoadingTitle)
                    Text(session.recentLibraryMessage).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ContentUnavailableView {
                    Label("Recently played games", systemImage: "gamecontroller")
                } description: {
                    Text(session.recentLibraryMessage)
                } actions: {
                    if session.canLoadRecentLibrary {
                        Button(session.accountError != nil || session.recentLibraryError != nil ? "Try again" : "Load recently played") {
                            Task { await session.reloadRecentLibrary() }
                        }
                    } else {
                        Button("Open Account", action: openAccount).disabled(session.accountBusy)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
    }

    private func featured(_ title: RecentLibraryTitle, artwork: CatalogArtworkReference) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 28) {
                CatalogArtworkView(reference: artwork, status: title.artworkStatus, contentMode: .fit)
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                featuredText(title).frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 18) {
                CatalogArtworkView(reference: artwork, status: title.artworkStatus, contentMode: .fit)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                featuredText(title)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func featuredText(_ title: RecentLibraryTitle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.name).font(.system(size: 32, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(title.platform.label).foregroundStyle(.secondary)
            if let stamp = title.lastPlayedAt, let date = Self.playedDate(stamp) {
                Text("Last played \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            storeAction(for: title)
        }
    }

    private func storeAction(for title: RecentLibraryTitle) -> some View {
        Button("Find in Store") { findInStore(title.name) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!session.isReady || (!session.supports(.query) && !session.supports(.search)))
            .accessibilityLabel("Find \(title.name) in Store")
            .accessibilityHint("Search Microsoft Store for this game name.")
            .accessibilityIdentifier("xodus.library.findInStore")
    }

    private static func playedDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
