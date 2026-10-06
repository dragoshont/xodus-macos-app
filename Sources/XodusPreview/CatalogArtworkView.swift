// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ImageIO
import SwiftUI
import XodusManagement

enum ArtworkLoadError: Error, Equatable {
    case unavailable, oversized, invalidImage
}

enum CatalogImagePolicy {
    static let maximumBytes = 8 * 1024 * 1024

    static func validatePixels(width: Int, height: Int) throws {
        guard (1...8192).contains(width), (1...8192).contains(height),
              width * height <= 16_777_216 else { throw ArtworkLoadError.oversized }
    }

    static func decode(_ data: Data) throws -> CGImage {
        guard data.count <= maximumBytes else { throw ArtworkLoadError.oversized }
        guard let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ArtworkLoadError.invalidImage
        }
        try validatePixels(width: width, height: height)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw ArtworkLoadError.invalidImage }
        return image
    }
}

private final class ArtworkRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}

@MainActor
final class CatalogArtworkStore {
    static let shared = CatalogArtworkStore()
    private let cache = NSCache<NSURL, NSImage>()
    private var pending: [URL: Task<NSImage, Error>] = [:]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration, delegate: ArtworkRedirectPolicy(),
                             delegateQueue: nil)
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 40
    }

    func image(for reference: CatalogArtworkReference) async throws -> NSImage {
        let url = try reference.validatedURL()
        if let image = cache.object(forKey: url as NSURL) { return image }
        if let task = pending[url] { return try await task.value }
        let session = session
        let task = Task {
            let image = try await Task.detached(priority: .utility) {
                var request = URLRequest(url: url)
                request.httpShouldHandleCookies = false
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                let (stream, response) = try await session.bytes(for: request)
                defer { stream.task.cancel() }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      response.url == url, http.mimeType?.hasPrefix("image/") == true else {
                    throw ArtworkLoadError.unavailable
                }
                guard response.expectedContentLength <= CatalogImagePolicy.maximumBytes else {
                    throw ArtworkLoadError.oversized
                }
                var data = Data()
                for try await byte in stream {
                    guard data.count < CatalogImagePolicy.maximumBytes else { throw ArtworkLoadError.oversized }
                    data.append(byte)
                }
                return try CatalogImagePolicy.decode(data)
            }.value
            return NSImage(cgImage: image, size: .zero)
        }
        pending[url] = task
        defer { pending[url] = nil }
        let image = try await task.value
        cache.setObject(image, forKey: url as NSURL,
                        cost: Int(image.size.width * image.size.height) * 4)
        return image
    }

    func preload(_ references: [CatalogArtworkReference]) async -> Int {
        let tasks = references.map { reference in
            Task {
                do { _ = try await image(for: reference); return true }
                catch { return false }
            }
        }
        var failures = 0
        for task in tasks { if !(await task.value) { failures += 1 } }
        return failures
    }
}

@MainActor
private final class ArtworkPresentation: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var loadID = UUID()

    func load(_ reference: CatalogArtworkReference?) async {
        let token = UUID()
        loadID = token
        image = nil
        failed = false
        guard let reference else { loading = false; return }
        loading = true
        defer { if loadID == token { loading = false } }
        do {
            let loaded = try await CatalogArtworkStore.shared.image(for: reference)
            try Task.checkCancellation()
            guard loadID == token else { return }
            image = loaded
        } catch is CancellationError { }
        catch { if loadID == token { failed = true } }
    }
}

struct CatalogArtworkView: View {
    let reference: CatalogArtworkReference?
    var status: CatalogArtworkStatus = .absent
    var contentMode: ContentMode = .fill
    @StateObject private var presentation = ArtworkPresentation()

    private var fallbackMessage: String {
        if presentation.failed { return "Artwork couldn't be loaded" }
        switch status {
        case .available: return "Loading artwork"
        case .absent: return "No artwork provided"
        case .rejected: return "Artwork isn't available from an approved source"
        case .notQueried: return "Artwork hasn't been checked"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = presentation.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor)
                        if presentation.loading { ProgressView().controlSize(.small) }
                        else {
                            Image(systemName: presentation.failed ? "photo.badge.exclamationmark" : "gamecontroller")
                                .font(.title2).foregroundStyle(.secondary)
                        }
                    }
                    .help(fallbackMessage)
                }
            }
        }
        .accessibilityHidden(true)
        .task(id: reference) { await presentation.load(reference) }
    }
}
