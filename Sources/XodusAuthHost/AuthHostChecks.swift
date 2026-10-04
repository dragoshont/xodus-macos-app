// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation
import AppKit
import WebKit

@MainActor
enum AuthHostChecks {
    static let flow = "00000000-0000-0000-0000-000000000000"
    static let synthetic = PrivateValue.object(Dictionary(uniqueKeysWithValues:
        LegacyDA.keys.map { ($0, PrivateValue.string("synthetic-\($0)-\"\\\n")) }))

    static func frame(sequence: UInt64 = 1, flowID: String = flow, message: PrivateValue) throws -> Data {
        try PrivateValue.object([
            "version": .number("1"), "flowID": .string(flowID), "sessionID": .number("1"),
            "sequence": .number(String(sequence)), "message": message
        ]).encoded()
    }

    static func open(remaining: UInt64 = 5000) -> PrivateValue {
        var headers = HostPolicy.headers.mapValues(PrivateValue.string)
        headers["cxh-correlationid"] = .string(flow)
        return .object(["kind": .string("open"), "remainingMillis": .number(String(remaining)),
                        "url": .string(HostPolicy.initialURL), "headers": .object(headers),
                        "userAgent": .string(HostPolicy.userAgent)])
    }

    static func run() async -> Bool {
        var count = 0, failures = 0
        func check(_ condition: Bool, _ name: String) {
            count += 1
            if condition { print("PASS: \(name)") }
            else { failures += 1; print("FAIL: \(name)") }
        }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); check(false, name) }
            catch { check(true, name) }
        }
        do {
            guard let fixtureURL = Bundle.module.url(forResource: "native-auth-host-v1", withExtension: "json",
                                                     subdirectory: "Resources") else {
                throw HostFailure.protocolInvalid
            }
            let fixture = try PrivateJSON.parse(Data(contentsOf: fixtureURL))
            guard case .object(let corpus) = fixture, case .array(let commands) = corpus["commands"] else {
                throw HostFailure.protocolInvalid
            }
            for command in commands {
                _ = try CommandFrame(command.encoded())
                check(true, "Pinned public synthetic command decodes with exact fields")
            }
            let data = try frame(message: open())
            let decoded = try PrivateJSON.parse(data)
            guard case .object(let initial) = decoded else { throw HostFailure.protocolInvalid }
            for (key, value) in [
                ("version", PrivateValue.number("2")), ("sessionID", .number("2")),
                ("sequence", .number("0")), ("sequence", .number("9007199254740992")),
                ("flowID", .string(flow.uppercased().replacingOccurrences(of: "0000", with: "AAAA"))),
                ("providerPayload", .string("synthetic-forbidden"))
            ] {
                var malformed = initial
                malformed[key] = value
                rejects("Wrong version/session/sequence/flow or unknown envelope field is rejected") {
                    _ = try CommandFrame(PrivateValue.object(malformed).encoded())
                }
            }
            var pending = HostSession()
            try pending.accept(CommandFrame(data))
            rejects("A duplicate command sequence cannot replay open") {
                try pending.accept(CommandFrame(data))
            }
            rejects("Completed close cannot precede ready and issuer handoff") {
                try pending.accept(CommandFrame(frame(sequence: 2, message: .object([
                    "kind": .string("close"), "disposition": .string("completed")]))))
            }
            rejects("A helper-result frame cannot enter the worker-command direction") {
                var result = initial
                result["replyTo"] = .number("1")
                result["message"] = .object(["kind": .string("ready")])
                _ = try CommandFrame(PrivateValue.object(result).encoded())
            }
            check(try PrivateJSON.parse(decoded.encoded()) == decoded,
                  "Strict private JSON round trips without interpreting issuer strings")
            for text in [
                #"{"K":"a","\u004b":"b"}"#, #"{"x":1,"x":2}"#,
                #"{"x":{"y":1,"y":2}}"#, #"{"x":01}"#, #"{"x":NaN}"#,
                #"{"x":"\q"}"#, #"{"x":1} {}"#, #"{"x":1,}"#
            ] {
                rejects("Duplicate, malformed or trailing private JSON is rejected") {
                    _ = try PrivateJSON.parse(Data(text.utf8))
                }
            }
            rejects("Oversized entire JSON frame is rejected before parsing") {
                _ = try PrivateJSON.parse(Data(repeating: 32, count: PrivateJSON.maximumBytes + 1))
            }
            let maximum = Data(("\"" + String(repeating: "x", count: PrivateJSON.maximumBytes - 2) + "\"").utf8)
            check(try PrivateJSON.parse(maximum).string?.utf8.count == PrivateJSON.maximumBytes - 2,
                  "Exact maximum UTF8 JSON size is accepted without an off-by-envelope allowance")
            let da = try LegacyDA(synthetic)
            check(da.value == synthetic, "All seven synthetic issuer strings retain exact bytes and spelling")
            rejects("A private issuer property cannot have extra fields") {
                _ = try LegacyDA(.object(["extra": .string("synthetic")]))
            }
            var wrongType = da.fields.mapValues(PrivateValue.string)
            wrongType["K"] = .number("1")
            rejects("Issuer field number cannot become a string") { _ = try LegacyDA(.object(wrongType)) }
            let context = "opaque \"provider\" context\\\nnot-a-uuid"
            let callback = try PrivateJSON.parse(Data(LegacyBridge.callback(context: context).utf8))
            guard case .object(let object) = callback, case .object(let body) = object["value"] else {
                throw HostFailure.bridgeInvalid
            }
            check(body["context"]?.string == context
                  && body["args"] == .array(["CloudExperienceHost", "TokenBroker", "TokenBroker",
                                            LegacyBridge.capabilities].map(PrivateValue.string)),
                  "Legacy getContext callback preserves opaque context and exact four original arguments")
            check(try LegacyNotification(.object(["type": .string("invoke"),
                                                 "value": .object(["name": .string("CloudExperienceHost.getContext"),
                                                                    "context": .string(context)])])) == .context(context),
                  "Only the existing fixed context request is supported")
            rejects("Unknown bridge method cannot manufacture native capability") {
                _ = try LegacyNotification(.object(["type": .string("invoke"), "value": .object([
                    "name": .string("WindowsHello"), "context": .string(context)])]))
            }
            for raw in ["http://login.live.com/", "https://foreign.invalid/", "https://login.live.com:444/",
                        "https://user@login.live.com/", "https://login.live.com.foreign.invalid/"] {
                check(URL(string: raw).map { !HostPolicy.navigation($0) } == true,
                      "Production navigation rejects foreign scheme/host/port/userinfo")
            }
            check(HostPolicy.navigation(URL(string: "https://login.live.com:443/test")!),
                  "Explicit default HTTPS port retains Rust URL parity")
            check(!HostPolicy.finish(URL(string: "https://login.live.com/ppsecure/post.srf/extra")!)
                  && !HostPolicy.finish(URL(string: "https://login.live.com/ppsecure/%70ost.srf")!)
                  && HostPolicy.finish(URL(string: "https://login.live.com/ppsecure/post.srf?fixture=1")!),
                  "Finish extraction uses exact trusted path, with query allowed")
            var session = HostSession()
            try session.accept(CommandFrame(data))
            let originalDeadline = session.deadline
            rejects("DA cannot precede a ready acknowledgement") { _ = try session.encode(.da(da)) }
            _ = try session.encode(.ready)
            var large = da.fields.mapValues(PrivateValue.string)
            large["K"] = .string(String(repeating: "x", count: PrivateJSON.maximumBytes))
            rejects("Outbound maximum includes the result envelope, without promoting oversized data") {
                _ = try session.encode(.da(LegacyDA(.object(large))))
            }
            _ = try session.encode(.da(da))
            rejects("DA is one-shot per accepted navigation") { _ = try session.encode(.da(da)) }
            for index in 1...4 {
                try session.accept(CommandFrame(frame(sequence: UInt64(index + 1), message: .object([
                    "kind": .string("navigate"), "url": .string("https://login.live.com/synthetic")]))))
                _ = try session.encode(.ready)
                _ = try session.encode(.da(da))
            }
            check(session.deadline == originalDeadline, "Continuations never reset the original remaining budget")
            rejects("A fifth continuation is rejected") {
                try session.accept(CommandFrame(frame(sequence: 6, message: .object([
                    "kind": .string("navigate"), "url": .string("https://login.live.com/synthetic")]))))
            }
            rejects("Foreign flow cannot replace an active private session") {
                try session.accept(CommandFrame(frame(sequence: 6,
                    flowID: "00000000-0000-0000-0000-000000000001",
                    message: .object(["kind": .string("close"), "disposition": .string("completed")]))))
            }
            try session.accept(CommandFrame(frame(sequence: 6, message: .object([
                "kind": .string("close"), "disposition": .string("completed")]))))
            let closed = try PrivateJSON.parse(session.encode(.closed(.completed)))
            guard case .object(let terminal) = closed else { throw HostFailure.protocolInvalid }
            check(session.terminal && terminal["replyTo"]?.unsigned == 6 && terminal["sequence"]?.unsigned == 11,
                  "Matching terminal close is correlated after ordered ready/DA frames")
            rejects("A terminal host cannot forward late issuer data") { _ = try session.encode(.da(da)) }
            var expired = HostSession()
            let start = ContinuousClock.now
            try expired.accept(CommandFrame(frame(message: open(remaining: 1))), now: start)
            rejects("Expired remaining budget rejects readiness") {
                _ = try expired.encode(.ready, now: start.advanced(by: .milliseconds(2)))
            }
            _ = try expired.encode(.failed(.deadlineExpired), now: start.advanced(by: .milliseconds(2)))
            check(expired.terminal, "Expiry produces only a terminal failure, never an authorization-budget extension")
            try await channelChecks(check: check)
            try await browserChecks(check: check)
        } catch {
            check(false, "Bounded private host check setup or execution failed")
        }
        print("\(count) private native-host checks, \(failures) failures. Detached synthetic WebKit only; no provider request.")
        return failures == 0
    }

    private static func pair() throws -> [Int32] {
        var sockets: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { throw HostFailure.channelClosed }
        for fd in sockets {
            guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
                sockets.forEach { Darwin.close($0) }
                throw HostFailure.channelClosed
            }
        }
        return sockets
    }

    private static func channelChecks(check: (Bool, String) -> Void) async throws {
        let sockets = try pair()
        let channel = try PrivateChannel(descriptor: sockets[0])
        let peer = try PrivateChannel(descriptor: sockets[1])
        sockets.forEach { Darwin.close($0) }
        let data = try frame(message: open())
        try await channel.write(data, deadline: .now.advanced(by: .seconds(2)))
        check(try await peer.read(deadline: .now.advanced(by: .seconds(2))) == data,
              "Real anonymous duplex socket preserves the bounded BE4 JSON frame")
        await channel.stop()
        do {
            _ = try await peer.read(deadline: .now.advanced(by: .seconds(2)))
            check(false, "Peer EOF terminates the private channel")
        } catch { check(error as? HostFailure == .channelClosed, "Peer EOF terminates the private channel") }
        await peer.stop()

        for length: UInt32 in [0, UInt32(PrivateJSON.maximumBytes + 1)] {
            let descriptors = try pair()
            let reader = try PrivateChannel(descriptor: descriptors[0])
            Darwin.close(descriptors[0])
            let header: [UInt8] = [UInt8((length >> 24) & 255), UInt8((length >> 16) & 255),
                                   UInt8((length >> 8) & 255), UInt8(length & 255)]
            _ = header.withUnsafeBytes { Darwin.write(descriptors[1], $0.baseAddress, $0.count) }
            do {
                _ = try await reader.read(deadline: .now.advanced(by: .seconds(2)))
                check(false, "Anonymous framing rejects zero and oversized BE lengths")
            } catch {
                check(error as? HostFailure == .protocolInvalid,
                      "Anonymous framing rejects zero and oversized BE lengths")
            }
            await reader.stop()
            Darwin.close(descriptors[1])
        }

        for end in ["completed", "cancelled", "failed", "eof", "halfClosed"] {
            let descriptors = try pair()
            let parent = try PrivateChannel(descriptor: descriptors[0])
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--self-check-peer"]
            process.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
            process.standardInput = FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: false)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            Darwin.close(descriptors[1])
            defer { Darwin.close(descriptors[0]) }
            defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
            try await parent.write(data, deadline: .now.advanced(by: .seconds(2)))
            let ready = try await parent.read(deadline: .now.advanced(by: .seconds(2)))
            let issuer = try await parent.read(deadline: .now.advanced(by: .seconds(2)))
            check(try resultKind(ready) == "ready" && resultKind(issuer) == "da",
                  "Neutral owned child orders ready before one synthetic issuer result")
            let disposition = HostDisposition(rawValue: end)
            if let disposition {
                try await parent.write(frame(sequence: 2, message: .object([
                    "kind": .string("close"), "disposition": .string(disposition.rawValue)])),
                    deadline: .now.advanced(by: .seconds(2)))
                check(try resultKind(await parent.read(deadline: .now.advanced(by: .seconds(2)))) == "closed",
                      "Neutral child acknowledges the matching terminal disposition")
                do {
                    _ = try await parent.read(deadline: .now.advanced(by: .seconds(2)))
                    check(false, "Matching closed acknowledgement is followed by helper EOF")
                } catch {
                    check(error as? HostFailure == .channelClosed,
                          "Matching closed acknowledgement is followed by helper EOF")
                }
            } else if end == "halfClosed" { shutdown(descriptors[0], SHUT_WR) }
            else { await parent.stop() }
            let until = ContinuousClock.now.advanced(by: .seconds(3))
            while process.isRunning && ContinuousClock.now < until {
                try await Task.sleep(for: .milliseconds(10))
            }
            check(!process.isRunning && process.terminationStatus == (disposition?.exitCode ?? 1),
                  disposition != nil ? "Matching terminal frame/EOF and expected neutral child exit agree"
                                     : "Creator EOF or explicit write-half closure ends the child without orphan lifetime")
            await parent.stop()
        }
    }

    private static func browserChecks(check: (Bool, String) -> Void) async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        check(application.activationPolicy() == .prohibited,
              "Neutral fixture application prohibits activation")
        let windowCount = application.windows.count
        let base = URL(string: "https://auth-host-fixture.invalid/finish")!
        let trust = BrowserTrust(
            navigation: { $0.scheme == "https" && $0.host == "auth-host-fixture.invalid" },
            bridge: { $0.scheme == "https" && $0.host == "auth-host-fixture.invalid" },
            finish: { $0.host == "auth-host-fixture.invalid" && $0.path == "/finish" })
        var result: LegacyDA?
        var failure: HostFailure?
        let browser = NativeAuthBrowser(trust: trust, received: { result = $0 }, failed: { failure = $0 })
        defer { browser.close() }
        let data = String(decoding: try synthetic.encoded(), as: UTF8.self)
        let html = """
        <!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'">
        <script>const ServerData = {DAProperty: \(data)};</script><p>Neutral native host fixture.</p>
        """
        try browser.loadSyntheticDocument(html, baseURL: base)
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while result == nil && failure == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        check(result?.value == synthetic && failure == nil,
              "Detached WK finish extracts exactly seven untouched synthetic strings")
        check(!browser.view.configuration.websiteDataStore.isPersistent,
              "Each native browser uses a fresh nonpersistent WebKit store")
        browser.close()
        browser.webViewWebContentProcessDidTerminate(browser.view)
        check(failure == nil, "Closed browser fences stale renderer callbacks")

        var staticFailure: HostFailure?
        var failureCount = 0
        let failing = NativeAuthBrowser(trust: trust, received: { _ in },
            failed: { staticFailure = $0; failureCount += 1 })
        failing.webView(failing.view, didFailProvisionalNavigation: nil,
                        withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        failing.webViewWebContentProcessDidTerminate(failing.view)
        check(staticFailure == .navigationFailed && failureCount == 1,
              "An unrelated cancellation is a typed failure, not silently ignored or repeated")
        failing.close()
        var cancellation: HostFailure?
        let cancelled = NativeAuthBrowser(trust: trust, received: { _ in }, failed: { cancellation = $0 })
        cancelled.webViewDidClose(cancelled.view)
        check(cancellation == .cancelled, "Native WebKit close callback has an explicit terminal cancellation")
        cancelled.close()
        let visible = application.windows.filter(\.isVisible).count
        print("NEUTRAL OWN PROCESS: initialWindows=\(windowCount) finalWindows=\(application.windows.count) visible=\(visible) active=\(application.isActive) policy=\(application.activationPolicy().rawValue)")
        check(visible == 0 && !application.isActive && application.activationPolicy() == .prohibited,
              "Detached WebKit fixtures show no window and do not activate their own application")
    }

    private static func resultKind(_ data: Data) throws -> String {
        let frame = try PrivateJSON.parse(data).object(
            keys: ["version", "flowID", "sessionID", "sequence", "replyTo", "message"])
        guard frame["version"]?.unsigned == 1, frame["sessionID"]?.unsigned == 1,
              frame["flowID"]?.string == flow, case .object(let body) = frame["message"],
              let kind = body["kind"]?.string else { throw HostFailure.protocolInvalid }
        return kind
    }

    static func peer() async -> Int32 {
        var session = HostSession()
        do {
            let channel = try PrivateChannel(descriptor: STDIN_FILENO)
            Darwin.close(STDIN_FILENO)
            while true {
                let data = try await channel.read(deadline: session.deadline ?? .now.advanced(by: .seconds(5)))
                let frame = try CommandFrame(data)
                try session.accept(frame)
                switch frame.command {
                case .open, .navigate:
                    try await channel.write(session.encode(.ready), deadline: .now.advanced(by: .seconds(2)))
                    try await channel.write(session.encode(.da(LegacyDA(synthetic))),
                                            deadline: .now.advanced(by: .seconds(2)))
                case .close(let disposition):
                    try await channel.write(session.encode(.closed(disposition)),
                                            deadline: .now.advanced(by: .seconds(2)))
                    await channel.stop()
                    return disposition.exitCode
                }
            }
        } catch { return 1 }
    }
}
