// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation

struct InstalledGame: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let identityName: String
    let version: String
    let storeId: String
    let folder: String
    let launcher: String
    let importedAt: Date
}

enum InstalledGameError: Error, LocalizedError {
    case invalidConfig, missingFolder, missingLauncher, invalidRegistry, storage, launch

    var errorDescription: String? {
        switch self {
        case .invalidConfig: "This folder doesn't contain a valid MicrosoftGame.config. Choose the installed Xbox game folder."
        case .missingFolder: "The game folder is no longer available. Reconnect its drive or import the game again."
        case .missingLauncher: "The launch script is missing or isn't an executable file. Import the game again to choose its script."
        case .invalidRegistry: "The installed games list couldn't be read. Your game files haven't been changed."
        case .storage: "The installed games list couldn't be saved. Check access to Application Support and try again."
        case .launch: "The game couldn't start. Check its launch script and try again."
        }
    }
}

struct MicrosoftGameConfig: Equatable, Sendable {
    let identityName: String
    let version: String
    let storeId: String
    let title: String

    static func read(folder: URL) throws -> Self {
        try InstalledGameFiles.checkFolder(folder)
        let matches: [URL]
        do {
            matches = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.lowercased() == "microsoftgame.config" }
        } catch { throw InstalledGameError.invalidConfig }
        guard matches.count == 1 else { throw InstalledGameError.invalidConfig }
        let data: Data
        do { data = try InstalledGameFiles.readRegular(matches[0], maximumBytes: 1_048_576) }
        catch { throw InstalledGameError.invalidConfig }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= 1_048_576 else { throw InstalledGameError.invalidConfig }
        let reader = ConfigReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), !reader.invalid, reader.root == "Game",
              let identity = reader.identity, let version = reader.version,
              let storeId = reader.storeId, !storeId.isEmpty,
              !identity.isEmpty, !version.isEmpty else { throw InstalledGameError.invalidConfig }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && UInt16($0) != nil
        }), [identity, storeId, reader.title ?? ""].allSatisfy({
            $0.count <= 512 && !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        }) else { throw InstalledGameError.invalidConfig }
        return Self(identityName: identity, version: version, storeId: storeId,
                    title: reader.title.flatMap { $0.isEmpty ? nil : $0 } ?? identity)
    }
}

private final class ConfigReader: NSObject, XMLParserDelegate {
    var root: String?
    var identity: String?
    var version: String?
    var title: String?
    var storeId: String?
    var invalid = false
    private var path: [String] = []
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        path.append(elementName)
        guard path.count <= 32 else { invalid = true; parser.abortParsing(); return }
        if path.count == 1 { root = elementName }
        if path == ["Game", "Identity"] {
            if identity != nil { invalid = true }
            identity = attributes["Name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            version = attributes["Version"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if path == ["Game", "ShellVisuals"] {
            if title != nil { invalid = true }
            title = attributes["DefaultDisplayName"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if path == ["Game", "StoreId"] { text = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if path == ["Game", "StoreId"] { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if path == ["Game", "StoreId"] {
            if storeId != nil { invalid = true }
            storeId = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        path.removeLast()
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        invalid = true
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
                publicID: String?, systemID: String?) {
        invalid = true
        parser.abortParsing()
    }
}

enum InstalledGameFiles {
    static func checkFolder(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard url.isFileURL, values?.isDirectory == true else { throw InstalledGameError.missingFolder }
    }

    static func checkLauncher(_ url: URL) throws {
        var info = stat()
        guard url.isFileURL, lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              FileManager.default.isExecutableFile(atPath: url.path) else {
            throw InstalledGameError.missingLauncher
        }
    }

    static func readRegular(_ url: URL, maximumBytes: Int, privateFile: Bool = false) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw InstalledGameError.invalidRegistry }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { handle.closeFile() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= maximumBytes,
              !privateFile || (info.st_uid == getuid() && info.st_mode & 0o777 == 0o600),
              let data = try handle.read(upToCount: maximumBytes + 1), data.count <= maximumBytes else {
            throw InstalledGameError.invalidRegistry
        }
        return data
    }
}

actor InstalledGameStore {
    static var defaultFile: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Xodus/installed-games.json")
    }
    let file: URL

    init(file: URL = InstalledGameStore.defaultFile) { self.file = file }

    func load() throws -> [InstalledGame] {
        var info = stat()
        if lstat(file.path, &info) != 0 {
            guard errno == ENOENT else { throw InstalledGameError.invalidRegistry }
            return []
        }
        let data = try InstalledGameFiles.readRegular(file, maximumBytes: 1_048_576, privateFile: true)
        let games = try JSONDecoder().decode([InstalledGame].self, from: data)
        guard Set(games.map(\.id)).count == games.count, Set(games.map(\.folder)).count == games.count,
              games.allSatisfy({ !$0.title.isEmpty && !$0.identityName.isEmpty && !$0.version.isEmpty
                  && !$0.storeId.isEmpty && $0.folder.hasPrefix("/") && $0.launcher.hasPrefix("/") }) else {
            throw InstalledGameError.invalidRegistry
        }
        return games
    }

    func save(_ games: [InstalledGame]) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), chmod(directory.path, 0o700) == 0 else { throw InstalledGameError.storage }
        let data = try JSONEncoder().encode(games)
        guard data.count <= 1_048_576 else { throw InstalledGameError.storage }
        let temporary = directory.appendingPathComponent(".installed-games-\(UUID().uuidString).json")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw InstalledGameError.storage }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            guard fsync(descriptor) == 0 else { throw InstalledGameError.storage }
            try handle.close()
            guard rename(temporary.path, file.path) == 0 else { throw InstalledGameError.storage }
        } catch {
            handle.closeFile()
            if unlink(temporary.path) != 0 && errno != ENOENT {
                throw InstalledGameError.storage
            }
            throw error
        }
    }
}
