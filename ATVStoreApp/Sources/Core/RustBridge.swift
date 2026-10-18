import Foundation

/// Swift error domain for Rust Core FFI operations.
public enum RustBridgeError: LocalizedError {
    case ffiError(code: Int32, message: String)
    case nullPointer(String)
    case decodingError(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .ffiError(let code, let message):
            return "Core engine error [\(code)]: \(message)"
        case .nullPointer(let param):
            return "Null pointer error in parameter: \(param)"
        case .decodingError(let details):
            return "Failed to decode response payload: \(details)"
        case .invalidResponse:
            return "Core engine returned an empty or invalid response."
        }
    }
}

/// Helper context for passing Swift closures across the C FFI function pointer boundary.
private final class ProgressContext {
    let callback: (Int, String) -> Void
    init(callback: @escaping (Int, String) -> Void) {
        self.callback = callback
    }
}

private let cProgressBridge: ATVProgressCallback = { percent, stagePtr, userData in
    guard let userData = userData else { return }
    let context = Unmanaged<ProgressContext>.fromOpaque(userData).takeUnretainedValue()
    let stage = stagePtr != nil ? String(cString: stagePtr!) : ""
    context.callback(Int(percent), stage)
}

/// Thread-safe Swift actor bridging calls to the Rust core static library.
public actor RustBridge {
    public static let shared = RustBridge()

    private init() {}

    // MARK: - Generic Result Unwrapper

    private func unwrapResult(_ result: inout ATVResult) throws -> String {
        defer {
            atv_free_result(&result)
        }

        if result.code != 0 {
            let errorMsg = result.error_message != nil
                ? String(cString: result.error_message!)
                : "Unknown FFI error"
            throw RustBridgeError.ffiError(code: result.code, message: errorMsg)
        }

        guard let dataJson = result.data_json else {
            return "{}"
        }
        return String(cString: dataJson)
    }

    // MARK: - Anisette & Authentication

    public func setAnisetteURL(_ url: String) throws {
        var res = url.withCString { atv_anisette_set_url($0) }
        _ = try unwrapResult(&res)
    }

    public func fetchAnisetteHeaders() throws -> [String: String] {
        var res = atv_anisette_fetch_headers()
        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw RustBridgeError.decodingError("Invalid anisette headers JSON")
        }
        return dict
    }

    public func login(appleID: String, password: String) throws -> [String: Any] {
        var res = appleID.withCString { cAppleID in
            password.withCString { cPass in
                atv_auth_login(cAppleID, cPass)
            }
        }
        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RustBridgeError.decodingError("Invalid auth login JSON")
        }
        return dict
    }

    public func submit2FA(sessionToken: String, code: String) throws -> [String: Any] {
        var res = sessionToken.withCString { cToken in
            code.withCString { cCode in
                atv_auth_submit_2fa(cToken, cCode)
            }
        }
        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RustBridgeError.decodingError("Invalid 2FA submission JSON")
        }
        return dict
    }

    // MARK: - Apple Developer Portal

    public func listTeams(sessionToken: String) throws -> [[String: Any]] {
        var res = sessionToken.withCString { atv_dev_list_teams($0) }
        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw RustBridgeError.decodingError("Invalid teams list JSON")
        }
        return arr
    }

    public func registerAppID(
        sessionToken: String,
        teamID: String,
        bundleID: String,
        appName: String
    ) throws -> [String: Any] {
        var res = sessionToken.withCString { cToken in
            teamID.withCString { cTeam in
                bundleID.withCString { cBundle in
                    appName.withCString { cName in
                        atv_dev_register_app_id(cToken, cTeam, cBundle, cName)
                    }
                }
            }
        }
        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RustBridgeError.decodingError("Invalid app id registration JSON")
        }
        return dict
    }

    public func provisionCertificate(
        sessionToken: String,
        teamID: String,
        machineName: String
    ) throws -> [String: Any] {
        var res = sessionToken.withCString { cToken in
            teamID.withCString { cTeam in
                machineName.withCString { cMachine in
                    atv_dev_provision_certificate(cToken, cTeam, cMachine)
                }
            }
        }
        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RustBridgeError.decodingError("Invalid certificate provisioning JSON")
        }
        return dict
    }

    public func provisionProfile(
        sessionToken: String,
        teamID: String,
        bundleID: String,
        deviceUDID: String
    ) throws -> [String: Any] {
        var res = sessionToken.withCString { cToken in
            teamID.withCString { cTeam in
                bundleID.withCString { cBundle in
                    deviceUDID.withCString { cUDID in
                        atv_dev_provision_profile(cToken, cTeam, cBundle, cUDID)
                    }
                }
            }
        }
        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RustBridgeError.decodingError("Invalid provisioning profile JSON")
        }
        return dict
    }

    // MARK: - IPA Resigning

    public func signIPA(
        inputIPA: String,
        outputIPA: String,
        p12Base64: String,
        p12Password: String,
        mobileprovisionBase64: String,
        newBundleID: String?,
        displayName: String?,
        onProgress: ((Int, String) -> Void)? = nil
    ) throws -> [String: Any] {
        let context = onProgress != nil ? ProgressContext(callback: onProgress!) : nil
        let retainedContext = context != nil ? Unmanaged.passRetained(context!) : nil
        let contextPtr = retainedContext?.toOpaque()

        defer {
            retainedContext?.release()
        }

        var res = inputIPA.withCString { cInput in
            outputIPA.withCString { cOutput in
                p12Base64.withCString { cP12 in
                    p12Password.withCString { cPass in
                        mobileprovisionBase64.withCString { cProv in
                            Self.withOptionalCString(newBundleID) { cBundleID in
                                Self.withOptionalCString(displayName) { cName in
                                    atv_sign_ipa(
                                        cInput,
                                        cOutput,
                                        cP12,
                                        cPass,
                                        cProv,
                                        cBundleID,
                                        cName,
                                        context != nil ? cProgressBridge : nil,
                                        contextPtr
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RustBridgeError.decodingError("Invalid sign IPA JSON response")
        }
        return dict
    }

    // MARK: - Device Bridge (Installation)

    public func checkDeviceConnection(host: String, port: UInt16, pairingData: Data) throws -> [String: Any] {
        var res = host.withCString { cHost in
            pairingData.withUnsafeBytes { rawBuffer in
                let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
                return atv_device_check_connection(cHost, port, bytes, pairingData.count)
            }
        }
        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RustBridgeError.decodingError("Invalid device check JSON")
        }
        return dict
    }

    public func installIPA(
        host: String,
        port: UInt16,
        pairingData: Data,
        ipaPath: String,
        bundleID: String,
        onProgress: ((Int, String) -> Void)? = nil
    ) throws -> [String: Any] {
        let context = onProgress != nil ? ProgressContext(callback: onProgress!) : nil
        let retainedContext = context != nil ? Unmanaged.passRetained(context!) : nil
        let contextPtr = retainedContext?.toOpaque()

        defer {
            retainedContext?.release()
        }

        var res = host.withCString { cHost in
            ipaPath.withCString { cIPA in
                bundleID.withCString { cBundle in
                    pairingData.withUnsafeBytes { rawBuffer in
                        let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
                        return atv_device_install_ipa(
                            cHost,
                            port,
                            bytes,
                            pairingData.count,
                            cIPA,
                            cBundle,
                            context != nil ? cProgressBridge : nil,
                            contextPtr
                        )
                    }
                }
            }
        }

        let jsonStr = try unwrapResult(&res)
        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RustBridgeError.decodingError("Invalid device install JSON")
        }
        return dict
    }

    // MARK: - Helper C-string wrapper
    private static func withOptionalCString<R>(_ string: String?, _ body: (UnsafePointer<CChar>?) throws -> R) rethrows -> R {
        if let string = string {
            return try string.withCString { try body($0) }
        } else {
            return try body(nil)
        }
    }
}

