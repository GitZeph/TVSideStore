import SwiftUI

/// Primary dashboard view for Apple TV 10-foot UI.
/// Displays status semaphores, "Refresh All" button, and card grid with expiration countdowns.
public struct MyAppsView: View {
    @ObservedObject private var registry = AppRegistryStore.shared
    @ObservedObject private var tunnel = TunnelMonitor.shared
    @ObservedObject private var refreshEngine = RefreshEngine.shared

    @AppStorage("autoRefreshOnLaunch") private var autoRefreshOnLaunch: Bool = true
    @FocusState private var focusedAppID: String?

    private let columns = [
        GridItem(.adaptive(minimum: 340, maximum: 420), spacing: 32)
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Top Status Bar (Semaphores & Actions)
                HStack(alignment: .center, spacing: 24) {
                    // Semaphores
                    HStack(spacing: 16) {
                        SemaphoreIndicator(
                            title: "Tunnel LocalDevVPN",
                            subtitle: tunnel.isTunnelActive ? "Attivo (\(tunnel.activeInterface ?? "utun"))" : "Inattivo (Apri VPN)",
                            isGreen: tunnel.isTunnelActive
                        )

                        SemaphoreIndicator(
                            title: "Pairing File",
                            subtitle: KeychainVault.shared.hasPairingFile() ? "Configurato" : "Mancante (Web Upload)",
                            isGreen: KeychainVault.shared.hasPairingFile()
                        )
                    }

                    Spacer()

                    // Prominent Primary Button: "Refresh Tutte le App"
                    Button(action: {
                        Task {
                            await refreshEngine.refreshAllApps()
                        }
                    }) {
                        HStack(spacing: 12) {
                            if refreshEngine.isRefreshing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Refresh Tutte le App (incluso ATVStore)")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.card)
                    .disabled(refreshEngine.isRefreshing || !tunnel.isTunnelActive || !KeychainVault.shared.hasPairingFile())
                }
                .padding(.horizontal, 48)
                .padding(.top, 24)

                // Live Refresh Pipeline Banner
                if refreshEngine.isRefreshing {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(refreshEngine.currentStepDescription)
                                .font(.headline)
                                .foregroundColor(.cyan)
                            Spacer()
                            Text("\(Int(refreshEngine.progressPercent * 100))%")
                                .font(.headline)
                                .fontWeight(.bold)
                        }

                        ProgressView(value: refreshEngine.progressPercent, total: 1.0)
                            .tint(.cyan)

                        if let lastLog = refreshEngine.logs.last {
                            Text(lastLog)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(16)
                    .padding(.horizontal, 48)
                }

                if let err = refreshEngine.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(err)
                            .font(.callout)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.red.opacity(0.3))
                    .cornerRadius(10)
                    .padding(.horizontal, 48)
                }

                // Header
                HStack {
                    Text("Applicazioni Gestite")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Text("\(registry.apps.count) installate")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 48)

                // Apps Grid
                LazyVGrid(columns: columns, spacing: 32) {
                    ForEach(registry.apps) { app in
                        AppCardView(app: app) {
                            Task {
                                try? await refreshEngine.refreshApp(app)
                            }
                        }
                        .focused($focusedAppID, equals: app.originalBundleID)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            checkAutoRefreshOnLaunch()
        }
    }

    private func checkAutoRefreshOnLaunch() {
        guard autoRefreshOnLaunch else { return }
        guard tunnel.isTunnelActive && KeychainVault.shared.hasPairingFile() else { return }

        // Trigger automatic refresh for apps with 3 days or less remaining
        let needsRenewal = registry.apps.contains { $0.needsRefresh }
        if needsRenewal && !refreshEngine.isRefreshing {
            Task {
                await refreshEngine.refreshAllApps()
            }
        }
    }
}

// MARK: - Subcomponents

private struct SemaphoreIndicator: View {
    let title: String
    let subtitle: String
    let isGreen: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isGreen ? Color.green : Color.red)
                .frame(width: 14, height: 14)
                .shadow(color: isGreen ? Color.green.opacity(0.6) : Color.red.opacity(0.6), radius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(subtitle)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}

private struct AppCardView: View {
    let app: InstalledApp
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                // App Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(app.isSelf ? LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)

                    Image(systemName: app.isSelf ? "tv.fill" : "app.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(app.rewrittenBundleID)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Text("v\(app.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Expiration Badge Row
            HStack {
                Text("SCADENZA CERTIFICATO:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                Text(app.formattedCountdown)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(app.statusBadgeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(app.statusBadgeColor.opacity(0.2))
                    .cornerRadius(8)
            }

            // Action Button
            Button(action: onRefresh) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Rinnova Certificato (7 Giorni)")
                        .font(.footnote)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.card)
        }
        .padding(22)
        .background(Color.white.opacity(0.06))
        .cornerRadius(22)
    }
}

