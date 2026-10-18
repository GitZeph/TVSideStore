import SwiftUI

/// Settings view for tvOS Siri Remote navigation.
/// Manages Pairing File, LocalDevVPN diagnostics, Anisette server, Apple ID, and Auto-Refresh.
public struct SettingsView: View {
    @ObservedObject private var tunnel = TunnelMonitor.shared
    @AppStorage("autoRefreshOnLaunch") private var autoRefreshOnLaunch: Bool = true
    @AppStorage("anisetteServerURL") private var anisetteServerURL: String = "https://anisette.sidestore.io"

    @State private var hasPairing: Bool = KeychainVault.shared.hasPairingFile()
    @State private var loggedInAppleID: String? = nil
    @State private var showResetConfirmation: Bool = false
    @State private var statusFeedback: String? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Impostazioni")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 48)

                if let feedback = statusFeedback {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.cyan)
                        Text(feedback)
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(12)
                    .padding(.horizontal, 48)
                }

                // Section 1: Tunnel & Pairing Diagnostics
                SettingsSection(title: "DIAGNOSTICA & CONNESSIONI") {
                    SettingsRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Tunnel LocalDevVPN (utun)",
                        value: tunnel.isTunnelActive ? "Attivo (\(tunnel.activeInterface ?? "utun") - \(tunnel.tunnelIP ?? "10.7.0.1"))" : "Inattivo"
                    ) {
                        Button("Ricarica") {
                            Task {
                                await tunnel.refresh()
                                statusFeedback = tunnel.statusMessage
                            }
                        }
                    }

                    SettingsRow(
                        icon: "lock.shield",
                        title: "Pairing File (Keychain)",
                        value: hasPairing ? "Salvato nel Keychain" : "Mancante (Usa Web Upload)"
                    ) {
                        if hasPairing {
                            Button("Rimuovi") {
                                KeychainVault.shared.deletePairingFile()
                                hasPairing = false
                                statusFeedback = "Pairing File rimosso dal Keychain."
                            }
                        }
                    }

                    SettingsRow(
                        icon: "network",
                        title: "Porta Lockdownd (62078)",
                        value: tunnel.isLockdownReachable ? "Raggiungibile" : "Non raggiungibile"
                    ) {
                        Button("Verifica Porta") {
                            Task {
                                await tunnel.refresh()
                                statusFeedback = tunnel.isLockdownReachable ? "Porta 62078 raggiungibile con successo!" : "Porta 62078 chiusa. Verifica LocalDevVPN."
                            }
                        }
                    }
                }

                // Section 2: Account Apple & Anisette
                SettingsSection(title: "ACCOUNT APPLE & ANISETTE") {
                    SettingsRow(
                        icon: "person.crop.circle",
                        title: "Account Apple Connesso",
                        value: loggedInAppleID ?? "Nessun account autenticato"
                    ) {
                        if loggedInAppleID != nil {
                            Button("Esci") {
                                KeychainVault.shared.deleteGSASession()
                                loggedInAppleID = nil
                                statusFeedback = "Account Apple disconnesso."
                            }
                        }
                    }

                    SettingsRow(
                        icon: "server.rack",
                        title: "Server Anisette v3",
                        value: anisetteServerURL
                    ) {
                        Button("Ripristina Predefinito") {
                            anisetteServerURL = "https://anisette.sidestore.io"
                            statusFeedback = "Server Anisette reimpostato a: https://anisette.sidestore.io"
                        }
                    }
                }

                // Section 3: Automazione & Reset
                SettingsSection(title: "AUTOMAZIONE & STORAGE") {
                    SettingsRow(
                        icon: "bolt.fill",
                        title: "Refresh Automatico all'Avvio",
                        value: autoRefreshOnLaunch ? "Attivo (se mancano ≤ 3 giorni)" : "Disattivato"
                    ) {
                        Button(autoRefreshOnLaunch ? "Disattiva" : "Attiva") {
                            autoRefreshOnLaunch.toggle()
                        }
                    }

                    SettingsRow(
                        icon: "trash",
                        title: "Pulisci Cache IPA (Library/Caches)",
                        value: "Libera spazio di archiviazione"
                    ) {
                        Button("Svuota Cache") {
                            let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                            let backupsDir = cachesURL.appendingPathComponent("IPABackups")
                            try? FileManager.default.removeItem(at: backupsDir)
                            try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
                            statusFeedback = "Cache locale degli IPA svuotata."
                        }
                    }

                    SettingsRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Ripristina Impostazioni di Fabbrica",
                        value: "Cancella Keychain e registro app"
                    ) {
                        Button("Ripristina Tutto") {
                            KeychainVault.shared.clearAll()
                            hasPairing = false
                            loggedInAppleID = nil
                            statusFeedback = "Tutti i dati e le chiavi nel Keychain sono stati cancellati."
                        }
                    }
                }
            }
            .padding(.vertical, 32)
        }
        .onAppear {
            hasPairing = KeychainVault.shared.hasPairingFile()
            loggedInAppleID = KeychainVault.shared.loadGSASession()?.appleID
        }
    }
}

// MARK: - Subcomponents

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 48)

            VStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 48)
        }
    }
}

private struct SettingsRow<Action: View>: View {
    let icon: String
    let title: String
    let value: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.cyan)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            action()
                .buttonStyle(.card)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }
}

