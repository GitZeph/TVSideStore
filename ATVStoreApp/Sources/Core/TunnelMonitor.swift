import Foundation
import Network
import Combine

/// Monitors the local utun* network interface established by the free LocalDevVPN app on tvOS.
/// Verifies the interface state via getifaddrs() and tests reachability of lockdownd on port 62078.
@MainActor
public final class TunnelMonitor: ObservableObject {
    public static let shared = TunnelMonitor()

    @Published public private(set) var isTunnelActive: Bool = false
    @Published public private(set) var activeInterface: String? = nil
    @Published public private(set) var tunnelIP: String? = nil
    @Published public private(set) var isLockdownReachable: Bool = false
    @Published public private(set) var statusMessage: String = "Scanning network interfaces..."

    public private(set) var targetHost: String = "10.7.0.1"
    public let targetPort: UInt16 = 62078

    private var monitorTimer: AnyCancellable?

    private init() {
        Task {
            await refresh()
        }
        startPeriodicMonitoring()
    }

    public func startPeriodicMonitoring(interval: TimeInterval = 4.0) {
        monitorTimer?.cancel()
        monitorTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.refresh()
                }
            }
    }

    public func stopPeriodicMonitoring() {
        monitorTimer?.cancel()
        monitorTimer = nil
    }

    // MARK: - Interface Inspection via getifaddrs()

    public func refresh() async {
        let (foundTunnel, ifaceName, ifaceIP) = inspectUtunInterfaces()

        self.isTunnelActive = foundTunnel
        self.activeInterface = ifaceName
        self.tunnelIP = ifaceIP

        if foundTunnel {
            // Test port 62078 (lockdownd) reachability
            let reachable = await probeLockdownPort(host: self.targetHost, port: self.targetPort)
            self.isLockdownReachable = reachable
            if reachable {
                self.statusMessage = "Tunnel Active & Lockdown Reachable (\(ifaceName ?? "utun"))"
            } else {
                self.statusMessage = "Tunnel Active (\(ifaceName ?? "utun")), Waiting for lockdownd (62078)..."
            }
        } else {
            self.isLockdownReachable = false
            self.statusMessage = "LocalDevVPN Inactive. Please open LocalDevVPN and activate tunnel."
        }
    }

    private func inspectUtunInterfaces() -> (active: Bool, name: String?, ip: String?) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (false, nil, nil)
        }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ptr = cursor {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            let name = String(cString: ifa.ifa_name)

            // Look for active utun interfaces
            if name.hasPrefix("utun") && (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0 {
                if let addr = ifa.ifa_addr {
                    let family = addr.pointee.sa_family
                    if family == UInt8(AF_INET) { // IPv4
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
                            let ipStr = String(cString: hostname)
                            return (true, name, ipStr)
                        }
                    }
                }
            }
            cursor = ifa.ifa_next
        }

        return (false, nil, nil)
    }

    // MARK: - Non-blocking TCP Probe for port 62078

    private func probeLockdownPort(host: String, port: UInt16) async -> Bool {
        return await withCheckedContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)

            final class State: @unchecked Sendable {
                var hasResumed = false
                let lock = NSLock()
            }
            let stateBox = State()

            connection.stateUpdateHandler = { state in
                stateBox.lock.lock()
                guard !stateBox.hasResumed else {
                    stateBox.lock.unlock()
                    return
                }
                switch state {
                case .ready:
                    stateBox.hasResumed = true
                    stateBox.lock.unlock()
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    stateBox.hasResumed = true
                    stateBox.lock.unlock()
                    connection.cancel()
                    continuation.resume(returning: false)
                case .waiting:
                    stateBox.lock.unlock()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                        stateBox.lock.lock()
                        guard !stateBox.hasResumed else {
                            stateBox.lock.unlock()
                            return
                        }
                        stateBox.hasResumed = true
                        stateBox.lock.unlock()
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    stateBox.lock.unlock()
                }
            }

            connection.start(queue: .global())
        }
    }
}

