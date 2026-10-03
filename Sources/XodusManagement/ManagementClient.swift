// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation

public struct BackendConfiguration: Sendable {
    public let executable: URL
    public let stateDirectory: URL

    public init(executable: URL, stateDirectory: URL) {
        self.executable = executable
        self.stateDirectory = stateDirectory
    }
}

public actor ManagementClient {
    public nonisolated let events: AsyncThrowingStream<ManagementEvent, Error>
    private let eventContinuation: AsyncThrowingStream<ManagementEvent, Error>.Continuation
    private let validator: ContractValidator
    private let writer = DispatchQueue(label: "Xodus.management.stdin")
    private var process: Process?
    private var stdin: FileHandle?
    private var outputTask: Task<Void, Never>?
    private var diagnosticTask: Task<Void, Never>?
    private var framer = JSONLineFramer()
    private var diagnosticBytes = 0
    private var stopped = false
    private var hello: ManagementHello?
    private var pending: [String: Pending] = [:]
    private var usedIDs = Set<String>()

    private struct Pending {
        let command: ManagementCommand
        let continuation: CheckedContinuation<JSONValue, Error>
        let deadline: Task<Void, Never>
    }

    public init() throws {
        validator = try ContractValidator()
        let channel = AsyncThrowingStream<ManagementEvent, Error>.makeStream(bufferingPolicy: .bufferingOldest(128))
        events = channel.stream
        eventContinuation = channel.continuation
    }

    public func connect(_ configuration: BackendConfiguration) async throws -> ManagementHello {
        guard process == nil, !stopped else { throw ManagementError.alreadyConnected }
        guard configuration.executable.isFileURL,
              FileManager.default.isExecutableFile(atPath: configuration.executable.path),
              configuration.stateDirectory.isFileURL,
              configuration.stateDirectory.path.hasPrefix("/"),
              configuration.stateDirectory.standardizedFileURL.pathComponents.count > 2 else {
            throw ManagementError.backendUnavailable
        }
        let input = Pipe(), output = Pipe(), diagnostics = Pipe()
        let child = Process()
        child.executableURL = configuration.executable
        child.arguments = ["manage", "--protocol", "1", "--state-dir", configuration.stateDirectory.path]
        // Inherit operational context, not unrelated application tokens or debug/proxy settings.
        child.environment = ProcessInfo.processInfo.environment.filter {
            ["HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "SSL_CERT_FILE", "SSL_CERT_DIR"].contains($0.key)
        }.merging(["RUST_LOG": "error"]) { _, value in value }
        child.standardInput = input
        child.standardOutput = output
        child.standardError = diagnostics
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw ManagementError.startFailed
        }
        child.terminationHandler = { [weak self] value in
            let status = value.terminationStatus
            Task { await self?.ended(status: status) }
        }
        do { try child.run() }
        catch { throw ManagementError.startFailed }
        process = child
        stdin = input.fileHandleForWriting

        let stdout = Self.chunks(output.fileHandleForReading, label: "Xodus.management.stdout")
        outputTask = Task { [weak self] in
            do {
                for try await bytes in stdout {
                    guard let self else { return }
                    try await self.consume(bytes)
                }
                await self?.outputEnded()
            } catch {
                await self?.fail(Self.safeError(error))
            }
        }
        let stderr = Self.chunks(diagnostics.fileHandleForReading, label: "Xodus.management.stderr")
        diagnosticTask = Task { [weak self] in
            do {
                for try await bytes in stderr {
                    guard let self else { return }
                    try await self.discardDiagnostics(count: bytes.count)
                }
            } catch { await self?.fail(Self.safeError(error)) }
        }
        do {
            let result = try await request(.hello, params: [
                "client": .string("xodus-macos-app"), "clientVersion": .string("0.2.0")
            ])
            return try result.decode(ManagementHello.self)
        } catch {
            fail(Self.safeError(error))
            throw error
        }
    }

    public func request(_ command: ManagementCommand, params: [String: JSONValue] = [:],
                        timeout: Duration = .seconds(30)) async throws -> JSONValue {
        guard !stopped, let child = process, child.isRunning, let stdin else {
            throw ManagementError.disconnected
        }
        if command != .hello {
            guard let hello else { throw ManagementError.disconnected }
            guard hello.supports(command) else { throw ManagementError.capabilityMissing(command.rawValue) }
        } else if hello != nil { throw ManagementError.alreadyConnected }
        guard pending.count < 64, usedIDs.count < 100_000 else { throw ManagementError.outputOverflow }
        let id = UUID().uuidString
        let frame = JSONValue.object([
            "kind": .string("request"), "protocol": .object(["major": .integer(1), "minor": .integer(0)]),
            "requestID": .string(id), "command": .string(command.rawValue), "params": .object(params)
        ])
        do { try validator.validate(frame) }
        catch { throw ManagementError.invalidRequest }
        var data = try JSONEncoder().encode(frame)
        guard data.count <= JSONLineFramer.maximumBytes else { throw ManagementError.frameTooLarge }
        data.append(10)
        let bytes = data
        usedIDs.insert(id)
        return try await withCheckedThrowingContinuation { continuation in
            let deadline = Task { [weak self] in
                do { try await Task.sleep(for: timeout) }
                catch { return }
                await self?.timedOut(id)
            }
            pending[id] = Pending(command: command, continuation: continuation, deadline: deadline)
            writer.async { [weak self] in
                do { try stdin.write(contentsOf: bytes) }
                catch { Task { await self?.fail(.writeFailed) } }
            }
        }
    }

    public func close() async {
        if !stopped {
            stopped = true
            resolveAll(.disconnected)
            eventContinuation.finish()
            stopProcess()
        }
        guard let child = process else { return }
        // Reconnect cannot race the previous process's private-directory lock or auth-child cleanup.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue(label: "Xodus.management.shutdown").async {
                child.waitUntilExit()
                continuation.resume()
            }
        }
    }

    private func consume(_ bytes: Data) throws {
        guard !stopped else { return }
        for line in try framer.append(bytes) {
            let value: JSONValue
            do { value = try JSONDecoder().decode(JSONValue.self, from: line) }
            catch { throw ManagementError.invalidFrame }
            try validator.validate(value)
            switch value["kind"]?.string {
            case "result": try receiveResult(value)
            case "event":
                guard let hello else { throw ManagementError.invalidEvent }
                let event = try value.decode(ManagementEvent.self)
                guard event.sessionID == hello.sessionID,
                      event.jobID == event.data.jobID, event.revision == event.data.revision,
                      event.requestID == event.data.requestID else { throw ManagementError.invalidEvent }
                if case .dropped = eventContinuation.yield(event) { throw ManagementError.outputOverflow }
            default: throw ManagementError.invalidFrame
            }
        }
    }

    private func receiveResult(_ value: JSONValue) throws {
        guard let id = value["requestID"]?.string, let waiter = pending[id] else {
            throw ManagementError.unexpectedResult
        }
        if value["ok"] == .bool(true) {
            guard let data = value["data"], let definition = waiter.command.resultDefinition else {
                throw ManagementError.invalidPayload
            }
            try validator.validate(data, definition: definition)
            if waiter.command == .hello {
                let negotiated = try data.decode(ManagementHello.self)
                guard Set(negotiated.capabilities.map(\.command)).count == negotiated.capabilities.count else {
                    throw ManagementError.invalidPayload
                }
                hello = negotiated
            }
            pending.removeValue(forKey: id)
            waiter.deadline.cancel()
            waiter.continuation.resume(returning: data)
        } else {
            guard let error = value["error"], let code = error["code"]?.string,
                  let retryable = error["retryable"]?.boolean else { throw ManagementError.invalidFrame }
            pending.removeValue(forKey: id)
            waiter.deadline.cancel()
            // The producer's human message/raw diagnostic text is deliberately not retained.
            waiter.continuation.resume(throwing: ManagementError.backendError(code, retryable: retryable))
        }
    }

    private func discardDiagnostics(count: Int) throws {
        guard !stopped else { return }
        guard count <= JSONLineFramer.maximumBytes - diagnosticBytes else { throw ManagementError.outputOverflow }
        diagnosticBytes += count
    }

    private func outputEnded() {
        guard !stopped else { return }
        do { try framer.finish() }
        catch { fail(Self.safeError(error)); return }
        // EOF never supplies a missing terminal result, even when the exit status is zero.
        fail(.disconnected)
    }

    private func ended(status: Int32) {
        guard !stopped else { return }
        if status != 0 { fail(.backendStopped(status)) }
        // A clean exit is drained by outputEnded(), so buffered terminal frames are not lost.
    }

    private func timedOut(_ id: String) {
        guard pending[id] != nil else { return }
        fail(.requestTimedOut)
    }

    private func fail(_ error: ManagementError) {
        guard !stopped else { return }
        stopped = true
        resolveAll(error)
        eventContinuation.finish(throwing: error)
        stopProcess()
    }

    private func resolveAll(_ error: ManagementError) {
        hello = nil
        let waiters = pending.values
        pending = [:]
        for waiter in waiters {
            waiter.deadline.cancel()
            waiter.continuation.resume(throwing: error)
        }
    }

    private func stopProcess() {
        try? stdin?.close()
        stdin = nil
        outputTask?.cancel()
        diagnosticTask?.cancel()
        guard let child = process else { return }
        child.terminationHandler = nil
        if child.isRunning {
            Task {
                try? await Task.sleep(for: .seconds(2))
                if child.isRunning { child.terminate() }
                try? await Task.sleep(for: .seconds(2))
                if child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    private static func safeError(_ error: Error) -> ManagementError {
        (error as? ManagementError) ?? .disconnected
    }

    private static func chunks(_ handle: FileHandle, label: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(128)) { continuation in
            DispatchQueue(label: label).async {
                defer { try? handle.close() }
                var buffer = [UInt8](repeating: 0, count: 8192)
                while true {
                    // One pipe read returns available bytes; read(upToCount:) may wait for a full buffer.
                    let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
                    if count == 0 { continuation.finish(); return }
                    if count < 0 {
                        if errno == EINTR { continue }
                        continuation.finish(throwing: ManagementError.disconnected)
                        return
                    }
                    switch continuation.yield(Data(buffer.prefix(count))) {
                    case .enqueued: break
                    case .dropped:
                        continuation.finish(throwing: ManagementError.outputOverflow)
                        return
                    case .terminated: return
                    @unknown default:
                        continuation.finish(throwing: ManagementError.outputOverflow)
                        return
                    }
                }
            }
        }
    }
}
