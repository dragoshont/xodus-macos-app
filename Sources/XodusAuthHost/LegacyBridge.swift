// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct LegacyDA: Equatable, Sendable {
    static let keys: Set<String> = ["sDAToken", "sDASessionKey", "sDAStartTime", "sDAExpires",
                                    "sSTSInlineFlowToken", "sSigninName", "K"]
    let fields: [String: String]

    init(_ value: PrivateValue) throws {
        let object = try value.object(keys: Self.keys)
        var fields: [String: String] = [:]
        for (key, value) in object {
            guard let string = value.string else { throw HostFailure.bridgeInvalid }
            fields[key] = string
        }
        self.fields = fields
    }

    var value: PrivateValue { .object(fields.mapValues(PrivateValue.string)) }
}

enum LegacyNotification: Equatable {
    case context(String)
    case da(LegacyDA)

    init(_ value: PrivateValue) throws {
        guard case .object(let object) = value else { throw HostFailure.bridgeInvalid }
        if Set(object.keys) == LegacyDA.keys {
            self = .da(try LegacyDA(value))
            return
        }
        if let property = object["DAProperty"] {
            self = .da(try LegacyDA(property))
            return
        }
        let invoke = try value.object(keys: ["type", "value"])
        guard invoke["type"]?.string == "invoke", let body = invoke["value"] else {
            throw HostFailure.bridgeInvalid
        }
        let fields = try body.object(keys: ["name", "context"])
        guard fields["name"]?.string == "CloudExperienceHost.getContext",
              let context = fields["context"]?.string else { throw HostFailure.bridgeInvalid }
        self = .context(context)
    }
}

enum LegacyBridge {
    static let handler = "xodusPrivateAuth"
    static let capabilities = #"{"PrivatePropertyBag":1,"PasswordlessConnect":1,"PreferAssociate":1,"ChromelessUI":0}"#
    static func injection(navigation: UInt64) -> String {
        """
    (() => {
      const id = crypto.randomUUID();
      Object.defineProperty(window, "__xodusAuthDocument", { value: id });
      window.external = { notify: raw => {
        if (typeof raw !== "string") throw new TypeError("Invalid native bridge input");
        window.webkit.messageHandlers.xodusPrivateAuth.postMessage(
          JSON.stringify({ navigation: \(navigation), document: id, message: raw }));
      }};
      if (typeof window.external.notify !== "function") throw new TypeError("Native bridge unavailable");
    })();
    """
    }
    static let dispatch = """
    if (window.__xodusAuthDocument !== document) return false;
    const dispatch = window["CloudExperienceHost.Bridge.dispatchMessage"];
    if (typeof dispatch !== "function") throw new TypeError("Native bridge unavailable");
    dispatch(callback);
    return true;
    """
    static let validateDocument = "return window.__xodusAuthDocument === document;"
    static let verifyBridge = """
    return typeof window.__xodusAuthDocument === "string"
        && typeof window.external.notify === "function";
    """
    static let extract = """
    const source = typeof ServerData === "object" && ServerData !== null ? ServerData.DAProperty : null;
    if (!source || typeof source !== "object") throw new TypeError("Native result unavailable");
    const keys = ["sDAToken", "sDASessionKey", "sDAStartTime", "sDAExpires",
                  "sSTSInlineFlowToken", "sSigninName", "K"];
    const result = {};
    for (const key of keys) {
      if (typeof source[key] !== "string") throw new TypeError("Invalid native result");
      result[key] = source[key];
    }
    return JSON.stringify(result);
    """

    static func callback(context: String) throws -> String {
        let value = PrivateValue.object([
            "type": .string("callback"),
            "value": .object([
                "name": .string("CloudExperienceHost.getContext"),
                "args": .array(["CloudExperienceHost", "TokenBroker", "TokenBroker", capabilities]
                    .map(PrivateValue.string)),
                "context": .string(context)
            ])
        ])
        let data = try value.encoded()
        guard data.count <= PrivateJSON.maximumBytes, let json = String(data: data, encoding: .utf8) else {
            throw HostFailure.bridgeInvalid
        }
        return json
    }
}
