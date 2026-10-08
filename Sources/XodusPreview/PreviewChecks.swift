// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XodusCore
import XodusManagement

@MainActor
enum PreviewChecks {
    static func checkDetailMetadata() -> Bool {
        do {
            let args = CommandLine.arguments
            guard args.count == 5, args[1] == "--catalog-detail-check",
                  PCGamesClient.market(args[3]) == args[3],
                  PCGamesClient.language(args[4]) == args[4],
                  let data = try GameScriptFiles.read(URL(fileURLWithPath: args[2]), maximumBytes: 4 * 1024 * 1024) else {
                throw PCGamesError.invalidResponse
            }
            let products = try JSONDecoder().decode(PCGamesCatalog.self, from: data).Products
            let payload = try JSONDecoder().decode(CatalogDetailPayload.self, from: data).Products
            guard !products.isEmpty, products.count <= 20, products.count == payload.count,
                  Set(products.map(\.ProductId)).count == products.count,
                  Set(products.map(\.ProductId)) == Set(payload.map(\.ProductId)) else {
                throw PCGamesError.invalidResponse
            }
            var videos = 0, screenshots = 0, ratings = 0, requirements = 0
            for product in payload {
                guard PCGamesClient.validProductID(product.ProductId),
                      let base = products.first(where: { $0.ProductId == product.ProductId }) else {
                    throw PCGamesError.invalidResponse
                }
                let facts = try CatalogDetailFacts(product: product,
                    images: base.LocalizedProperties?.first?.Images ?? [], market: args[3], language: args[4])
                videos += facts.trailers.count
                screenshots += facts.screenshots.count
                ratings += facts.storeRating == nil ? 0 : 1
                requirements += facts.requirements == nil ? 0 : 1
            }
            print("Validated \(products.count) saved public products: \(videos) HLS trailers, \(screenshots) screenshots, \(ratings) Store ratings, \(requirements) PC requirement tables. No network, player or backend started.")
            return true
        } catch {
            FileHandle.standardError.write(Data("Saved public detail metadata was rejected.\n".utf8))
            return false
        }
    }

    static func run() -> Bool {
        var count = 0, failures = 0
        func check(_ condition: Bool, _ name: String) {
            count += 1
            if condition { print("PASS: \(name)") }
            else {
                failures += 1
                FileHandle.standardError.write(Data("FAIL: \(name)\n".utf8))
            }
        }

        let state = AppState()
        check(!DevelopmentArguments.accepts(["--check-native"]) &&
              !DevelopmentArguments.accepts(["--live-check", "--unknown"]),
              "Unknown or conflicting development check arguments fail closed before ordinary startup")
        check(DevelopmentArguments.accepts([]) && DevelopmentArguments.accepts(["--live-check"]) &&
              DevelopmentArguments.accepts(["--library-preview", "/private/review", "--game-detail", "/private/catalog", "FIXTURE00002"]),
              "Ordinary startup and correctly shaped explicit check/review arguments remain supported")
        check(state.destination == .library && !state.showsRecentActivity,
              "Live startup opens the PC Library without claiming ownership or selecting activity")
        state.navigate(.library)
        check(ArtAssets.images.count == 6, "Six original fixture image resources load")
        check(state.visibleGames.count == 4, "Library excludes catalog-only and unknown-access fixtures")
        state.query = "moss"
        check(state.visibleGames.isEmpty, "Library search does not broaden to catalog")
        state.navigate(.discover)
        check(state.query.isEmpty && state.visibleGames.count == 6, "Changing scope clears query")
        state.query = "moss"
        check(state.visibleGames.count == 1 && state.visibleGames[0].entitlement == .none,
              "Discover search does not grant entitlement")
        state.query = ""
        state.category = .space
        check(state.visibleGames.map(\.art) == ["orbit"], "Empty-query category browse is scoped")
        state.navigate(.library)
        state.accessFilter = .subscription
        check(state.visibleGames.count == 1, "Library access filter distinguishes subscription")
        state.accessFilter = nil
        state.sortByTitle = true
        check(state.visibleGames.first?.title == "Lumen Harbor", "Title sort is deterministic")

        let game = Fixtures.games[2]
        state.lowSpace = true
        state.enqueue(game)
        check(state.jobs.isEmpty && state.message != nil, "Insufficient space creates no job")
        state.lowSpace = false
        state.message = nil
        state.enqueue(game)
        check(state.jobs.count == 1 && state.destination == .downloads, "Approved fixture plan enqueues once")
        state.enqueue(game)
        check(state.jobs.count == 1, "Duplicate fixture submission creates no second active job")
        if let job = state.jobs.first {
            for _ in 0..<5 { state.updateJob(job.id) { $0.advance() } }
        }
        check(state.installed.contains(game.id), "Only completed fixture job marks installed")
        state.simulateLaunch(game)
        check(state.message?.contains("No game or runtime was started") == true,
              "Simulated launch never claims real gameplay")
        state.connected = false
        check(state.decision(for: game).reason != nil, "Disconnected account blocks action")
        state.reset()
        check(state.jobs.isEmpty && !state.installed.contains(game.id),
              "Fixture reset clears queue and simulated installation")
        for destination in Destination.allCases {
            state.query = "prior scope"
            state.accessFilter = .subscription
            state.sortByTitle = true
            state.category = .space
            state.navigationSelection.wrappedValue = destination
            check(state.destination == destination && state.navigationSelection.wrappedValue == destination
                  && state.query.isEmpty && state.accessFilter == nil && !state.sortByTitle
                  && state.category == .all && !state.showingAccount && !state.showingWelcome,
                  "Native toolbar binding preserves \(destination.rawValue) routing and clears only browse scope")
        }
        let live = LiveSession()
        check(!state.fixtureMode, "Default application mode does not present fixture games")
        check(live.products.isEmpty, "Live catalog never starts with invented titles")
        check(live.authentication == nil, "Live account does not start with simulated sign-in")
        check(live.currentCredentialState == nil && live.accountSymbol == "person.crop.circle"
              && live.accountLabel == "Connect Xodus",
              "Disconnected live account presentation never borrows the fixture's connection or profile badge")
        check(live.activity.jobs.isEmpty, "Live activity does not start with simulated jobs")
        check(!live.canSignIn, "Sign-in is disabled until backend capability negotiation")
        check(!live.supports(.launch) && !live.supports(.plan), "Live gameplay and installation fail closed")
        check(!live.signInPending && !live.accountBusy, "No unattended native sign-in begins")
        check(live.diagnosticPreview == nil, "No diagnostics or raw engine text are captured at startup")
        check(live.phase == .disconnected, "Presentation checks do not contact Xodus or Keychain")
        libraryChecks(check: check)
        detailChecks(check: check)
        NativeUIChecks.run(check: check)
        print("\(count) preview checks, \(failures) failures. No backend connected.")
        return failures == 0
    }

    private static func detailChecks(check: (Bool, String) -> Void) {
        do {
            let data = Data("""
                {"Products":[{"ProductId":"FIXTURE00002","LocalizedProperties":[{"Language":"en-US",
                "ProductDescription":"An original synthetic adventure.","DeveloperName":"Original Studio",
                "PublisherName":"Original Publisher","CMSVideos":[{"HLS":"https://cdn-dynmedia-1.microsoft.com/is/content/microsoftassets/original-fixture-AVS.m3u8?packagedStreaming=true",
                "Caption":"Original trailer","PreviewImage":{"Uri":"//store-images.s-microsoft.com/image/apps.fixture","Width":1920,"Height":1080}}]}],
                "MarketProperties":[{"Markets":["US"],"OriginalReleaseDate":"2026-01-02T00:00:00.0000000Z",
                "UsageData":[{"AggregateTimeSpan":"7Days","AverageRating":1,"RatingCount":1},
                {"AggregateTimeSpan":"AllTime","AverageRating":4.5,"RatingCount":20}],
                "ContentRatings":[{"RatingSystem":"ESRB","RatingId":"ESRB:T","RatingDescriptors":["ESRB:FanVio"],
                "InteractiveElements":["ESRB:InGamPur"]}]}],
                "DisplaySkuAvailabilities":[{"Sku":{"Properties":{"Packages":[{"PlatformDependencies":[{"PlatformName":"Windows.Desktop"}]}],
                "HardwareProperties":{"MinimumProcessor":"Original PC CPU","RecommendedGraphics":"Original PC GPU"}}}}]}]}
                """.utf8)
            let product = try JSONDecoder().decode(CatalogDetailPayload.self, from: data).Products[0]
            let screenshot = PCGamesCatalog.Product.Localized.Image(ImagePurpose: "Screenshot",
                Uri: "//store-images.s-microsoft.com/image/apps.fixture", Width: 1920, Height: 1080)
            let facts = try CatalogDetailFacts(product: product, images: [screenshot], market: "US", language: "en-US")
            check(facts.description == "An original synthetic adventure." && facts.developer == "Original Studio",
                  "D3 optional description/developer facts decode independently of access or installation")
            check(facts.publisher == "Original Publisher" && facts.releaseDate != nil,
                  "D3 public publisher/release metadata accepts the observed seven-digit ISO date shape")
            check(facts.storeRating?.average == 4.5 && facts.storeRating?.count == 20,
                  "Store rating uses only actual all-time average/count, never a short-period score or Metascore")
            check(facts.contentRating?.label == "ESRB Teen" &&
                  facts.contentRating?.interactiveElements == ["In-game purchases"],
                  "Native content-rating copy retains real age-system and in-app-purchase semantics")
            check(facts.trailers.count == 1 && facts.trailers[0].preview != nil,
                  "Public HLS and preview decode without creating a player or downloading trailer bytes")
            check(facts.screenshots.count == 1 && facts.screenshots[0].role == .hero,
                  "Detail screenshots reuse validated bounded public-image references")
            check(facts.requirements?.MinimumProcessor == "Original PC CPU" && !facts.requirementsVaryByEdition,
                  "Requirements are selected only from an explicit Windows.Desktop SKU")
            let empty = CatalogDetailPayload.Product(ProductId: "FIXTURE00002", LocalizedProperties: nil,
                MarketProperties: nil, DisplaySkuAvailabilities: nil)
            let absent = try CatalogDetailFacts(product: empty, images: [], market: "US", language: "en-US")
            check(absent.description == nil && absent.trailers.isEmpty && absent.storeRating == nil &&
                  absent.contentRating == nil && absent.requirements == nil,
                  "Absent optional detail fields stay absent rather than invented placeholders or claims")
            let otherMarket = try CatalogDetailFacts(product: product, images: [], market: "GB", language: "en-US")
            check(otherMarket.releaseDate == nil && otherMarket.storeRating == nil && otherMarket.contentRating == nil,
                  "Missing requested-market details never borrow another market's date or ratings")
            do {
                _ = try CatalogDetailFacts(product: product, images: [], market: "US", language: "fr-FR")
                check(false, "Unrelated localized descriptions must be rejected")
            } catch PCGamesError.invalidResponse {
                check(true, "Detail metadata rejects unrelated language fallback")
            }
            let repeated = try CatalogDetailFacts(product: product, images: Array(repeating: screenshot, count: 20),
                                                   market: "US", language: "en-US")
            check(repeated.screenshots.count == 1, "Screenshot gallery deduplicates exact URLs before its twelve-image bound")
            let consoleData = Data(String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "Windows.Desktop", with: "Xbox.Console").utf8)
            let consoleProduct = try JSONDecoder().decode(CatalogDetailPayload.self, from: consoleData).Products[0]
            let console = try CatalogDetailFacts(product: consoleProduct, images: [], market: "US", language: "en-US")
            check(console.requirements == nil, "Console SKU hardware cannot masquerade as Windows PC requirements")
            let alternateProperties = CatalogDetailPayload.Product.Availability.SKU.PropertiesDTO(
                HardwareProperties: CatalogPCRequirements(MinimumProcessor: "Another PC CPU",
                    RecommendedProcessor: nil, MinimumGraphics: nil, RecommendedGraphics: nil),
                Packages: product.DisplaySkuAvailabilities?[0].Sku?.Properties?.Packages)
            let differing = CatalogDetailPayload.Product(ProductId: product.ProductId,
                LocalizedProperties: product.LocalizedProperties, MarketProperties: product.MarketProperties,
                DisplaySkuAvailabilities: (product.DisplaySkuAvailabilities ?? []) + [
                    .init(Sku: .init(Properties: alternateProperties))])
            let editionFacts = try CatalogDetailFacts(product: differing, images: [], market: "US", language: "en-US")
            check(editionFacts.requirements == nil && editionFacts.requirementsVaryByEdition,
                  "Different PC editions disclose varying requirements rather than selecting an arbitrary SKU")
            let whitespaceData = Data(String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "Original PC CPU", with: "  ")
                .replacingOccurrences(of: "Original PC GPU", with: " Original PC GPU ").utf8)
            let whitespaceProduct = try JSONDecoder().decode(CatalogDetailPayload.self, from: whitespaceData).Products[0]
            let normalized = try CatalogDetailFacts(product: whitespaceProduct, images: [], market: "US", language: "en-US")
            check(normalized.requirements?.MinimumProcessor == nil &&
                  normalized.requirements?.RecommendedGraphics == "Original PC GPU",
                  "Missing whitespace-only hardware fields hide; genuine values are normalized")
            let playback = CatalogTrailerPlayback()
            check(playback.player == nil && playback.error == nil,
                  "Constructing trailer state never creates an AVPlayer, starts autoplay or fetches a video")
            playback.stop()
            check(playback.player == nil, "Closing unused trailer state remains side-effect-free")
            for url in ["http://cdn-dynmedia-1.microsoft.com/is/content/microsoftassets/original-AVS.m3u8",
                        "https://example.com/is/content/microsoftassets/original-AVS.m3u8",
                        "https://cdn-dynmedia-1.microsoft.com/is/content/microsoftassets/original-AVS.m3u8?token=secret",
                        "https://user@cdn-dynmedia-1.microsoft.com/is/content/microsoftassets/original-AVS.m3u8",
                        "https://cdn-dynmedia-1.microsoft.com:443/is/content/microsoftassets/original-AVS.m3u8",
                        "https://cdn-dynmedia-1.microsoft.com/is/content/microsoftassets/original-AVS.m3u8#fragment",
                        "https://cdn-dynmedia-1.microsoft.com/is/content/microsoftassets/original-AVS.m3u8?packagedStreaming=true&packagedStreaming=true"] {
                do {
                    _ = try CatalogTrailer.validatedURL(url)
                    check(false, "Invalid trailer source must be rejected")
                } catch PCGamesError.invalidResponse {
                    check(true, "Trailer source rejects unsafe scheme/host/credential/query without a network request")
                }
            }
        } catch { check(false, "Synthetic D3 detail schema failed: \(error.localizedDescription)") }
    }

    private static func libraryChecks(check: (Bool, String) -> Void) {
        let installed = InstalledGame(id: UUID(), title: "Original Harbor", identityName: "fixture",
            version: "1.0.0.0", storeId: "FIXTURE00001", folder: "/fixture", launcher: "/fixture/run",
            importedAt: .distantPast, lastPlayedAt: Date(timeIntervalSince1970: 100))
        let owned = PCGame(id: "FIXTURE00002", title: "Original Ridge", artwork: nil)
        do {
            func product(_ id: String) throws -> CatalogProduct {
                try JSONDecoder().decode(CatalogProduct.self, from: Data("""
                    {"productID":"\(id)","title":"Original Moss","market":"US","language":"en-US",
                    "source":"MicrosoftGamePassSigls:v3","checkedAt":"2026-10-08T00:00:00Z",
                    "freshness":"current","editions":[],"pcCatalogCandidate":true,
                    "artwork":[],"artworkStatus":"absent"}
                    """.utf8))
            }
            let pass = try product("FIXTURE00003")
            let catalogOnly = try product("FIXTURE00004")
            check(DiscoverCopy.noResults("tomb") == "No Results for “tomb”" &&
                  DiscoverCopy.emptyDescription == "Try another title or clear your search.",
                  "A valid zero-result search names the query and offers title/clear recovery, never reconnection")
            check(DiscoverCopy.noOtherGames("gears") == "No other games match “gears”.",
                  "Owned-only matches use consumer copy rather than Store/evidence terminology")
            let browseFacts = [pass.id: LibraryCatalogFacts(genres: ["Puzzle"])]
            check(DiscoverBrowse.genres(products: [pass, catalogOnly], facts: browseFacts) == ["Puzzle"],
                  "Discover genres come only from supplied catalog facts, not invented editorial categories")
            check(DiscoverBrowse.visible(products: [pass, catalogOnly], facts: browseFacts, genre: nil).count == 2,
                  "Empty-query browse retains the actual catalog order and count")
            check(DiscoverBrowse.visible(products: [pass, catalogOnly], facts: browseFacts, genre: "Puzzle").map(\.id) == [pass.id],
                  "Genre filtering stays within the loaded page and hides titles with missing genre")
            check(DiscoverBrowse.visible(products: [pass], facts: browseFacts, genre: "Absent").isEmpty,
                  "An unavailable genre has a real empty result instead of manufactured recommendations")
            check(!DiscoverBrowse.canInstall(owned: false, gamePass: true, subscriptionActive: false),
                  "Discover feed membership without a confirmed subscription does not enable Install")
            check(DiscoverBrowse.canInstall(owned: true, gamePass: false, subscriptionActive: false) &&
                  DiscoverBrowse.canInstall(owned: false, gamePass: true, subscriptionActive: true),
                  "Purchased or confirmed Game Pass access preserves the protected Install route")
            check(!DiscoverBrowse.canInstall(owned: false, gamePass: false, subscriptionActive: true),
                  "An active subscription does not grant installation to arbitrary checked-catalog titles")
            check(try CatalogReviewSnapshot(products: [pass, catalogOnly]).pcProducts(market: "US", language: "en-US").count == 2,
                  "Read-only catalog snapshots validate unchanged public PC records in the exact market/language")
            do {
                _ = try CatalogReviewSnapshot(products: [pass, pass]).pcProducts(market: "US", language: "en-US")
                check(false, "Duplicate snapshot identities must fail closed")
            } catch ManagementError.invalidPayload {
                check(true, "Duplicate snapshot identities fail closed without inventing catalog membership")
            }
            do {
                _ = try CatalogReviewSnapshot(products: [pass]).pcProducts(market: "GB", language: "en-US")
                check(false, "Wrong-scope catalog snapshots must fail closed")
            } catch ManagementError.invalidPayload {
                check(true, "Wrong-scope catalog snapshots fail closed before a public media load")
            }
            let all = LibraryGame.collection(installed: [installed, installed], owned: [owned, owned],
                products: [catalogOnly], gamePass: [pass, pass], active: true)
            check(all.count == 3 && Set(all.map(\.id)).count == 3,
                  "Refreshed Library joins exact identities once across repeated inputs")
            check(all.first?.installed != nil && all.first?.owned == false,
                  "Importing a game never changes its ownership evidence")
            check(!all.contains { $0.id == catalogOnly.id },
                  "Library never imports unrelated Store discovery into an entitled collection")
            check(LibraryGame.visible(all, query: "", filter: .owned, sort: .title).map(\.id) == [owned.id],
                  "Owned filter is based only on the complete PC account collection")
            check(LibraryGame.visible(all, query: "", filter: .gamePass, sort: .title).map(\.id) == [pass.id],
                  "Game Pass filter preserves separate membership evidence")
            check(LibraryGame.collection(installed: [installed], owned: [owned], products: [],
                gamePass: [pass], active: false).map(\.id) == [installed.storeId, owned.id],
                  "Inactive subscription excludes feed-only titles without deleting installed or purchased games")
            check(LibraryGame.visible(all, query: "  RIDGE  ", filter: .all, sort: .title).map(\.id) == [owned.id],
                  "Library query trims whitespace and searches only titles in the current collection")
            check(LibraryGame.visible(all, query: "", filter: .installed, sort: .recentlyPlayed).map(\.id) == [installed.storeId],
                  "Installed and last-played filtering uses local registry evidence only")
            let joined = LibraryGame.collection(installed: [installed],
                owned: [PCGame(id: installed.storeId, title: "Account title", artwork: nil)],
                products: [], gamePass: [try product(installed.storeId)], active: true)
            check(joined.count == 1 && joined[0].owned && joined[0].gamePass && joined[0].installed != nil,
                  "One exact title can retain independent installation, purchase and subscription facets")
            let square = PCGamesClient.artwork(uri: "https://store-images.s-microsoft.com/image/apps.fixture",
                                              width: 400, height: 400, role: .boxArt)
            let squareGame = LibraryGame(id: owned.id, title: owned.title, installed: nil,
                pc: PCGame(id: owned.id, title: owned.title, artwork: square), product: nil, owned: true, gamePass: false)
            check(square != nil && squareGame.cover == nil, "Portrait Library covers do not stretch square Store icons")
            check(LibraryAccess(joined[0]) == .owned && LibraryAccess(all[0]) == nil &&
                  all.first(where: { $0.gamePass }).flatMap(LibraryAccess.init) == .gamePass,
                  "Access badges preserve purchase priority and never turn installation into entitlement")
            check(all[0].actionTitle == "Play" && all.filter { $0.installed == nil }.allSatisfy { $0.actionTitle == "Install" },
                  "Only installed entries say Play; uninstalled purchase/subscription cards say Install")
            let metadata = try JSONDecoder().decode(PCGamesCatalog.Product.self, from: Data("""
                {"ProductId":"FIXTURE00002","Properties":{
                 "Categories":[" Action & adventure ","Role playing","Action & adventure"],
                 "Attributes":[{"Name":"SinglePlayer","ApplicablePlatforms":["Desktop"]},
                   {"Name":"XblOnlineMultiPlayer"},{"Name":"XblOnlineCoop"},
                   {"Name":"XblCrossPlatformMultiPlayer"},{"Name":"XblAchievements"}]}}
                """.utf8))
            let facts = LibraryCatalogFacts(properties: metadata.Properties)
            check(facts.genres == ["Action & adventure", "Role playing"] &&
                  facts.capabilities == LibraryCapability.allCases,
                  "DisplayCatalog genre and four recognized capabilities decode without inferred achievements")
            let console = try JSONDecoder().decode(PCGamesCatalog.Product.self, from: Data("""
                {"ProductId":"FIXTURE00002","Properties":{"Category":"Games",
                 "Attributes":[{"Name":"SinglePlayer","ApplicablePlatforms":["Xbox"]},
                   {"Name":"XblOnlineMultiPlayer","ApplicablePlatforms":[]}]}}
                """.utf8))
            check(LibraryCatalogFacts(properties: console.Properties).capabilities.isEmpty &&
                  LibraryCatalogFacts(properties: console.Properties).genres.isEmpty,
                  "Console-only capabilities and a generic Games category never masquerade as PC metadata")
            let absent = LibraryCatalogFacts(properties: nil)
            let malformed = try JSONDecoder().decode(PCGamesCatalog.Product.self, from:
                Data(#"{"ProductId":"FIXTURE00002","Properties":"unusable optional metadata"}"#.utf8))
            check(absent.genres.isEmpty && absent.capabilities.isEmpty && malformed.Properties == nil,
                  "Missing or malformed optional presentation metadata hides rather than breaking game identity")
            let packages = try JSONDecoder().decode(PCGamesCatalog.Product.self, from: Data("""
                {"ProductId":"FIXTURE00002","DisplaySkuAvailabilities":[{"Sku":{"Properties":{"Packages":[
                 {"PlatformDependencies":[{"PlatformName":"Xbox"}],"MaxDownloadSizeInBytes":999999999999},
                 {"PlatformDependencies":[{"PlatformName":"Windows.Desktop"}],"MaxDownloadSizeInBytes":"5300000000"},
                 {"PlatformDependencies":[{"PlatformName":"Windows.Desktop"}],"MaxDownloadSizeInBytes":-1},
                 {"PlatformDependencies":[{"PlatformName":"Windows.Desktop"}],"MaxDownloadSizeInBytes":"unknown"}
                ]}}}]}
                """.utf8))
            check(packages.pcDownloadBytes == 5_300_000_000 && packages.isPC,
                  "Public size uses positive PC package maxima, not console sizes or malformed metadata")
            check(metadata.pcDownloadBytes == nil && malformed.pcDownloadBytes == nil,
                  "Missing public size stays unknown and never becomes a zero-byte download")
            check(LibraryGameInformation.playTimeLabel(seconds: 43_200)?.hasPrefix("12 h") == true &&
                  LibraryGameInformation.playTimeLabel(seconds: 120)?.hasPrefix("2 min") == true &&
                  LibraryGameInformation.playTimeLabel(seconds: nil) == nil &&
                  LibraryGameInformation.playTimeLabel(seconds: .infinity) == nil &&
                  LibraryGameInformation.playTimeLabel(seconds: -1) == nil,
                  "Local total-play-time labels are honest, bounded and absent without cumulative evidence")
            let statsData = Data("""
                {"friends":1,"checkedAt":"2026-10-08T00:00:00Z","games":{"FIXTURE00002":{
                 "achievementsUnlocked":14,"achievementsTotal":0,"gamerscore":215,"gamerscoreTotal":1000,
                 "genres":["Adventure"],"minutesPlayed":292,
                 "friendsWhoPlay":[{"gamertag":"OriginalFixtureGamer","online":false}]}}}
                """.utf8)
            let stats = try LibraryXboxStatsCache.decode(statsData)
            let detail = stats.games[owned.id]
            check(detail?.achievements == "\(14.formatted()) achievements · \(215.formatted()) / \(1000.formatted()) G" &&
                  detail?.playTime?.hasSuffix(" h on Xbox") == true &&
                  detail?.friends == "1 friend plays" && detail?.friendHelp == "OriginalFixtureGamer" &&
                  stats.games[installed.storeId] == nil,
                  "Cached Xbox stats preserve unknown totals, explicit Xbox time and exact-ID missing-game hiding")
            let invalidStats = Data(String(decoding: statsData, as: UTF8.self)
                .replacingOccurrences(of: #""minutesPlayed":292"#, with: #""minutesPlayed":-1"#).utf8)
            do {
                _ = try LibraryXboxStatsCache.decode(invalidStats)
                check(false, "Negative Xbox play time is never presented as a successful cache")
            } catch { check(true, "Negative Xbox play time is never presented as a successful cache") }
        } catch { check(false, "Library presentation fixture decoding completes without runtime or account access") }
    }
}
