import Foundation
import Network
import Combine

/// Lightweight native HTTP server built with Network.framework on port 8080.
/// Solves tvOS's absence of WKWebView and file importer by providing a LAN web interface.
@MainActor
public final class LANWebServer: ObservableObject {
    public static let shared = LANWebServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var serverURL: String = "http://127.0.0.1:8080"
    @Published public private(set) var localIP: String = "127.0.0.1"
    @Published public private(set) var logs: [String] = []

    public let port: UInt16 = 8080
    private var listener: NWListener?

    private init() {
        self.localIP = resolveLANIPAddress()
        self.serverURL = "http://\(self.localIP):\(self.port)"
    }

    public func start() {
        guard !isRunning else { return }

        self.localIP = resolveLANIPAddress()
        self.serverURL = "http://\(self.localIP):\(self.port)"

        do {
            let parameters = NWParameters.tcp
            self.listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: self.port)!)

            self.listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.addLog("LAN Web Server listening on \(self.serverURL)")
                    case .failed(let err):
                        self.isRunning = false
                        self.addLog("LAN Web Server failed: \(err)")
                    case .cancelled:
                        self.isRunning = false
                        self.addLog("LAN Web Server stopped.")
                    default:
                        break
                    }
                }
            }

            self.listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            self.listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            addLog("Error initializing NWListener: \(error)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    public func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 40 {
            logs.removeFirst()
        }
    }

    // MARK: - HTTP Connection & Request Routing

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        readNextHTTPChunk(connection: connection, accumulatedData: Data())
    }

    private func readNextHTTPChunk(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            var buffer = accumulatedData
            if let content = content {
                buffer.append(content)
            }

            // Check if full HTTP headers received (\r\n\r\n)
            if let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
                let headerString = String(data: headerData, encoding: .utf8) ?? ""
                let bodyStartIndex = headerEndRange.upperBound

                // Parse Content-Length
                var contentLength = 0
                for line in headerString.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let parts = line.split(separator: ":")
                        if parts.count == 2 {
                            contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                        }
                    }
                }

                let currentBodyLength = buffer.count - bodyStartIndex
                if currentBodyLength < contentLength && !isComplete {
                    // Need more body data
                    self.readNextHTTPChunk(connection: connection, accumulatedData: buffer)
                    return
                }

                let bodyData = buffer.subdata(in: bodyStartIndex..<buffer.count)
                Task { @MainActor in
                    self.dispatchRequest(headerString: headerString, bodyData: bodyData, connection: connection)
                }
            } else if !isComplete && error == nil {
                self.readNextHTTPChunk(connection: connection, accumulatedData: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    private func dispatchRequest(headerString: String, bodyData: Data, connection: NWConnection) {
        let firstLine = headerString.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, contentType: "text/plain", body: Data("Bad Request".utf8))
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        addLog("\(method) \(path)")

        if method == "GET" && (path == "/" || path == "/index.html") {
            let htmlData = Data(WebPortalHTML.fullHTML.utf8)
            sendResponse(connection: connection, statusCode: 200, contentType: "text/html; charset=utf-8", body: htmlData)
        } else if method == "GET" && path == "/api/status" {
            handleGetStatus(connection: connection)
        } else if method == "POST" && path == "/api/upload-pairing" {
            handleUploadPairing(bodyData: bodyData, connection: connection)
        } else if method == "POST" && path == "/api/auth-login" {
            handleAuthLogin(bodyData: bodyData, connection: connection)
        } else if method == "POST" && path == "/api/auth-2fa" {
            handleAuth2FA(bodyData: bodyData, connection: connection)
        } else if method == "POST" && path == "/api/upload-ipa" {
            handleUploadIPA(headerString: headerString, bodyData: bodyData, connection: connection)
        } else if method == "POST" && path == "/api/add-source" {
            handleAddSource(bodyData: bodyData, connection: connection)
        } else {
            sendResponse(connection: connection, statusCode: 404, contentType: "text/plain", body: Data("Not Found".utf8))
        }
    }

    // MARK: - Route Handlers

    private func handleGetStatus(connection: NWConnection) {
        let statusDict: [String: Any] = [
            "has_pairing": KeychainVault.shared.hasPairingFile(),
            "tunnel_active": TunnelMonitor.shared.isTunnelActive,
            "tunnel_ip": TunnelMonitor.shared.tunnelIP ?? "",
            "lockdown_reachable": TunnelMonitor.shared.isLockdownReachable,
            "installed_apps_count": AppRegistryStore.shared.apps.count,
            "server_url": self.serverURL
        ]

        if let json = try? JSONSerialization.data(withJSONObject: statusDict) {
            sendResponse(connection: connection, statusCode: 200, contentType: "application/json", body: json)
        }
    }

    private func handleUploadPairing(bodyData: Data, connection: NWConnection) {
        // Extract binary data (either direct or multipart)
        var pairingBytes = bodyData
        if let boundaryRange = bodyData.range(of: Data("filename=".utf8)) {
            let sub = bodyData.subdata(in: boundaryRange.lowerBound..<bodyData.count)
            if let start = sub.range(of: Data("\r\n\r\n".utf8)) {
                let payloadStart = start.upperBound
                if let end = sub.range(of: Data("\r\n--".utf8)) {
                    pairingBytes = sub.subdata(in: payloadStart..<end.lowerBound)
                }
            }
        }

        do {
            try KeychainVault.shared.savePairingFile(pairingBytes)
            addLog("Successfully saved pairing file to Keychain (\(pairingBytes.count) bytes)")
            let resp = try JSONSerialization.data(withJSONObject: ["status": "SUCCESS", "bytes": pairingBytes.count])
            sendResponse(connection: connection, statusCode: 200, contentType: "application/json", body: resp)
        } catch {
            let resp = try? JSONSerialization.data(withJSONObject: ["status": "ERROR", "message": error.localizedDescription])
            sendResponse(connection: connection, statusCode: 500, contentType: "application/json", body: resp ?? Data())
        }
    }

    private func handleAuthLogin(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String],
              let appleID = json["apple_id"],
              let password = json["password"] else {
            sendResponse(connection: connection, statusCode: 400, contentType: "application/json", body: Data("{\"status\":\"ERROR\",\"message\":\"Missing credentials\"}".utf8))
            return
        }

        Task {
            do {
                let res = try await RustBridge.shared.login(appleID: appleID, password: password)
                try KeychainVault.shared.saveGSASession(token: res["session_token"] as? String ?? "", appleID: appleID)
                self.addLog("Apple ID login initiated for \(appleID)")
                let out = try JSONSerialization.data(withJSONObject: res)
                self.sendResponse(connection: connection, statusCode: 200, contentType: "application/json", body: out)
            } catch {
                let errData = Data("{\"status\":\"ERROR\",\"message\":\"\(error.localizedDescription)\"}".utf8)
                self.sendResponse(connection: connection, statusCode: 401, contentType: "application/json", body: errData)
            }
        }
    }

    private func handleAuth2FA(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String],
              let sessionToken = json["session_token"],
              let code = json["code"] else {
            sendResponse(connection: connection, statusCode: 400, contentType: "application/json", body: Data("{\"status\":\"ERROR\",\"message\":\"Missing 2FA code\"}".utf8))
            return
        }

        Task {
            do {
                let res = try await RustBridge.shared.submit2FA(sessionToken: sessionToken, code: code)
                self.addLog("Apple ID 2FA verified successfully")
                let out = try JSONSerialization.data(withJSONObject: res)
                self.sendResponse(connection: connection, statusCode: 200, contentType: "application/json", body: out)
            } catch {
                let errData = Data("{\"status\":\"ERROR\",\"message\":\"\(error.localizedDescription)\"}".utf8)
                self.sendResponse(connection: connection, statusCode: 401, contentType: "application/json", body: errData)
            }
        }
    }

    private func handleUploadIPA(headerString: String, bodyData: Data, connection: NWConnection) {
        // Extract optional source URL from custom headers
        var sourceURL: URL? = nil
        for line in headerString.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("x-source-url:") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    sourceURL = URL(string: parts[1].trimmingCharacters(in: .whitespaces))
                }
            }
        }

        let appID = "uploaded_app_\(Int(Date().timeIntervalSince1970))"
        _ = AppRegistryStore.shared.cacheIPABackup(bundleID: appID, data: bodyData)

        let app = InstalledApp(
            name: "Uploaded App",
            originalBundleID: appID,
            rewrittenBundleID: appID,
            version: "1.0",
            installedDate: Date(),
            expirationDate: Date().addingTimeInterval(7 * 86400),
            sourceURL: sourceURL
        )
        AppRegistryStore.shared.registerApp(app)

        addLog("Received IPA (\(bodyData.count / 1024) KB), saved to Caches/IPABackups")

        let out = Data("{\"status\":\"SUCCESS\",\"bundle_id\":\"\(appID)\"}".utf8)
        sendResponse(connection: connection, statusCode: 200, contentType: "application/json", body: out)
    }

    private func handleAddSource(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String],
              let urlStr = json["url"],
              let url = URL(string: urlStr) else {
            sendResponse(connection: connection, statusCode: 400, contentType: "application/json", body: Data("{\"status\":\"ERROR\"}".utf8))
            return
        }

        Task {
            do {
                try await AppRegistryStore.shared.addSourceURL(url)
                self.addLog("Added AltSource: \(urlStr)")
                self.sendResponse(connection: connection, statusCode: 200, contentType: "application/json", body: Data("{\"status\":\"SUCCESS\"}".utf8))
            } catch {
                let out = Data("{\"status\":\"ERROR\",\"message\":\"\(error.localizedDescription)\"}".utf8)
                self.sendResponse(connection: connection, statusCode: 400, contentType: "application/json", body: out)
            }
        }
    }

    private func sendResponse(connection: NWConnection, statusCode: Int, contentType: String, body: Data) {
        let statusText = (statusCode == 200) ? "OK" : (statusCode == 404 ? "Not Found" : "Error")
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        var responseData = Data(header.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    // MARK: - Local IP Address Resolution

    private func resolveLANIPAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return address
        }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ptr = cursor {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            let name = String(cString: ifa.ifa_name)

            // Look for Wi-Fi (en0) or Ethernet (en1) on Apple TV
            if (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0 && (flags & IFF_LOOPBACK) == 0 {
                if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let ip = String(cString: hostname)
                        if name == "en0" || name == "en1" {
                            return ip
                        }
                        address = ip
                    }
                }
            }
            cursor = ifa.ifa_next
        }
        return address
    }
}

