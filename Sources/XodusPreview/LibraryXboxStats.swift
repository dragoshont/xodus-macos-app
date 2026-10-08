// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation
import XodusManagement

struct LibraryXboxStatsCache: Decodable, Sendable {
    struct Friend: Decodable, Sendable {
        let gamertag: String
        let online: Bool
    }
    struct Game: Decodable, Sendable {
        let achievementsUnlocked: Int
        let achievementsTotal: Int
        let gamerscore: Int
        let gamerscoreTotal: Int
        let genres: [String]
        let logoUrl: String?
        let minutesPlayed: Int?
        let friendsWhoPlay: [Friend]

        var playTime: String? {
            minutesPlayed.map {
                "\((Double($0) / 60).formatted(.number.precision(.fractionLength(1)))) h on Xbox"
            }
        }
        var achievements: String {
            let count = achievementsTotal > 0
                ? "\(achievementsUnlocked.formatted()) of \(achievementsTotal.formatted()) achievements"
                : "\(achievementsUnlocked.formatted()) achievements"
            let score = gamerscoreTotal > 0
                ? "\(gamerscore.formatted()) / \(gamerscoreTotal.formatted()) G"
                : "\(gamerscore.formatted()) G"
            return "\(count) · \(score)"
        }
        var friends: String? {
            guard !friendsWhoPlay.isEmpty else { return nil }
            return friendsWhoPlay.count == 1 ? "1 friend plays" : "\(friendsWhoPlay.count.formatted()) friends play"
        }
        var friendHelp: String { friendsWhoPlay.map(\.gamertag).joined(separator: "\n") }
        var logo: CatalogArtworkReference? {
            PCGamesClient.artwork(uri: logoUrl, width: nil, height: nil, role: .hero)
        }
    }
    let friends: Int
    let checkedAt: String
    let games: [String: Game]

    var date: Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: checkedAt) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: checkedAt)
    }

    static func decode(_ data: Data) throws -> Self {
        let cache = try JSONDecoder().decode(Self.self, from: data)
        guard cache.date != nil, cache.friends >= 0, cache.games.count <= 5000,
              cache.games.allSatisfy({ id, game in
                  PCGamesClient.validProductID(id) && game.achievementsUnlocked >= 0 &&
                  game.achievementsTotal >= 0 && game.gamerscore >= 0 && game.gamerscoreTotal >= 0 &&
                  (game.achievementsTotal == 0 || game.achievementsUnlocked <= game.achievementsTotal) &&
                  (game.gamerscoreTotal == 0 || game.gamerscore <= game.gamerscoreTotal) &&
                  (game.minutesPlayed.map { (0...31_536_000).contains($0) } ?? true) &&
                  game.genres.count <= 20 && game.genres.allSatisfy { safeText($0, maximum: 128) } &&
                  game.friendsWhoPlay.count <= 2000 &&
                  game.friendsWhoPlay.allSatisfy { safeText($0.gamertag, maximum: 128) }
              }) else { throw PCGamesError.invalidResponse }
        return cache
    }

    private static func safeText(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximum &&
        !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

@MainActor
final class LibraryXboxStats: ObservableObject {
    static let shared = LibraryXboxStats()
    @Published private(set) var cache: LibraryXboxStatsCache?
    @Published private(set) var error: String?

    func loadReadOnly() async {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XodusRemote/game-stats.json")
        do {
            cache = try await Task.detached {
                var info = stat()
                if lstat(file.path, &info) != 0 {
                    guard errno == ENOENT else { throw PCGamesError.invalidResponse }
                    return Optional<LibraryXboxStatsCache>.none
                }
                let data = try InstalledGameFiles.readRegular(file, maximumBytes: 1_048_576, privateFile: true)
                return try LibraryXboxStatsCache.decode(data)
            }.value
            error = nil
        } catch {
            self.error = "Saved Xbox game stats couldn't be read. Your games and access haven't changed."
        }
    }
}
