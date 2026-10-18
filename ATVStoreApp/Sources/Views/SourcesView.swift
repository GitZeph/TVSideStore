import SwiftUI

/// tvOS view for browsing AltStore / SideStore repositories and 1-click installation.
public struct SourcesView: View {
    @ObservedObject private var registry = AppRegistryStore.shared
    @ObservedObject private var refreshEngine = RefreshEngine.shared
    @State private var selectedSourceIndex: Int = 0
    @State private var installingBundleID: String? = nil

    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: 36) {
            // Left: Sources List
            VStack(alignment: .leading, spacing: 16) {
                Text("Sorgenti Configurate")
                    .font(.title3)
                    .fontWeight(.bold)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(registry.sources.enumerated()), id: \.element.id) { idx, source in
                            Button(action: {
                                selectedSourceIndex = idx
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.name)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text("\(source.apps.count) applicazioni")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedSourceIndex == idx {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.cyan)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
                .frame(width: 380)
            }

            // Right: Apps in selected source
            VStack(alignment: .leading, spacing: 16) {
                if registry.sources.indices.contains(selectedSourceIndex) {
                    let source = registry.sources[selectedSourceIndex]

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            if let desc = source.description {
                                Text(desc)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }

                    ScrollView {
                        LazyVStack(spacing: 20) {
                            if source.apps.isEmpty {
                                Text("Nessuna applicazione disponibile in questo repository.")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 40)
                            } else {
                                ForEach(source.apps) { item in
                                    SourceAppRow(
                                        app: item,
                                        isInstalling: installingBundleID == item.bundleIdentifier
                                    ) {
                                        installSourceApp(item)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(40)
    }

    private func installSourceApp(_ item: AltSourceApp) {
        installingBundleID = item.bundleIdentifier

        Task {
            do {
                // 1. Download IPA
                let (data, _) = try await URLSession.shared.data(from: item.downloadURL)
                let localPath = AppRegistryStore.shared.cacheIPABackup(bundleID: item.bundleIdentifier, data: data)

                // 2. Register
                let newApp = InstalledApp(
                    name: item.name,
                    originalBundleID: item.bundleIdentifier,
                    rewrittenBundleID: item.bundleIdentifier,
                    version: item.version,
                    installedDate: Date(),
                    expirationDate: Date().addingTimeInterval(7 * 86400),
                    sourceURL: item.downloadURL,
                    cachedIPAPath: localPath
                )
                AppRegistryStore.shared.registerApp(newApp)

                // 3. Trigger sign & install pipeline
                try await RefreshEngine.shared.refreshApp(newApp)
            } catch {
                RefreshEngine.shared.addLog("Errore installazione \(item.name): \(error.localizedDescription)")
            }
            installingBundleID = nil
        }
    }
}

private struct SourceAppRow: View {
    let app: AltSourceApp
    let isInstalling: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 64, height: 64)
                Image(systemName: "app.gift.fill")
                    .font(.title2)
                    .foregroundColor(.cyan)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(app.developerName ?? app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let desc = app.localizedDescription {
                    Text(desc)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onInstall) {
                HStack(spacing: 8) {
                    if isInstalling {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: "icloud.and.arrow.down")
                    }
                    Text(isInstalling ? "Installazione..." : "Installa")
                        .font(.footnote)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.card)
            .disabled(isInstalling)
        }
        .padding(18)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
    }
}

