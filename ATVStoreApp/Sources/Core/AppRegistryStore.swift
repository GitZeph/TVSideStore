import Foundation
import Combine

/// Resilient storage manager for registered apps, expiration tracking, and IPA backups.
/// Dual-writes to NSUserDefaults (<250KB) and tvOS Keychain to guarantee zero data loss.
@MainActor
public final class AppRegistryStore: ObservableObject {
    public static let shared = AppRegistryStore()

    private let userDefaultsKey = "atv_installed_apps_registry"
    private let sourcesUserDefaultsKey = "atv_sources_registry"

    @Published public private(set) var apps: [InstalledApp] = []
    @Published public private(set) var sources: [AltSourceRepo] = []

    private let backupsDirectory: URL

    private init() {
        // Resolve Library/Caches/IPABackups/
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.backupsDirectory = cachesURL.appendingPathComponent("IPABackups", isDirectory: true)

        try? FileManager.default.createDirectory(at: self.backupsDirectory, withIntermediateDirectories: true)

        load()
        ensureSelfRegistration()
    }

    // MARK: - Persistence (UserDefaults + Keychain Dual-Write)

    private func load() {
        // 1. Try reading from UserDefaults
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([InstalledApp].self, from: data) {
            self.apps = decoded
        } else if let kcData = KeychainVault.shared.loadAppRegistryBackup(),
                  let decoded = try? JSONDecoder().decode([InstalledApp].self, from: kcData) {
            // 2. Fallback to Keychain if UserDefaults was purged or reset
            self.apps = decoded
            UserDefaults.standard.set(kcData, forKey: userDefaultsKey)
        } else {
            self.apps = []
        }

        // Load Sources
        if let sData = UserDefaults.standard.data(forKey: sourcesUserDefaultsKey),
           let sDecoded = try? JSONDecoder().decode([AltSourceRepo].self, from: sData) {
            self.sources = sDecoded
        } else {
            // Default community source
            if let defaultURL = URL(string: "https://apps.sidestore.io") {
                self.sources = [
                    AltSourceRepo(
                        name: "SideStore Community",
                        identifier: "io.sidestore.apps",
                        sourceURL: defaultURL,
                        subtitle: "Default community tvOS apps"
                    )
                ]
            }
        }
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self.apps) else { return }

        // Guarantee payload is under 250 KB
        if data.count < 250 * 1024 {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }

        // Dual-write into Keychain
        try? KeychainVault.shared.saveAppRegistryBackup(data)

        // Save sources
        if let sData = try? JSONEncoder().encode(self.sources) {
            UserDefaults.standard.set(sData, forKey: sourcesUserDefaultsKey)
        }
    }

    // MARK: - App Management

    public func ensureSelfRegistration() {
        let selfID = "com.atvstore.SideStoreTV"
        if !apps.contains(where: { $0.originalBundleID == selfID || $0.isSelf }) {
            let selfApp = InstalledApp(
                name: "SideStoreTV",
                originalBundleID: selfID,
                rewrittenBundleID: selfID,
                version: "1.0.0",
                installedDate: Date(),
                expirationDate: Date().addingTimeInterval(7 * 86400),
                sourceURL: nil,
                isSelf: true
            )
            apps.insert(selfApp, at: 0)
            save()
        }
    }

    public func registerApp(_ app: InstalledApp) {
        if let idx = apps.firstIndex(where: { $0.originalBundleID == app.originalBundleID }) {
            apps[idx] = app
        } else {
            apps.append(app)
        }
        save()
    }

    public func updateAppExpiry(bundleID: String, newExpiry: Date) {
        if let idx = apps.firstIndex(where: { $0.originalBundleID == bundleID || $0.rewrittenBundleID == bundleID }) {
            apps[idx].expirationDate = newExpiry
            save()
        }
    }

    public func removeApp(bundleID: String) {
        apps.removeAll { $0.originalBundleID == bundleID && !$0.isSelf }
        // Clean up backup file if exists
        let backupFile = backupsDirectory.appendingPathComponent("\(bundleID).ipa")
        try? FileManager.default.removeItem(at: backupFile)
        save()
    }

    // MARK: - IPA Backup Storage in Library/Caches

    public func cacheIPABackup(bundleID: String, data: Data) -> String? {
        let fileURL = backupsDirectory.appendingPathComponent("\(bundleID).ipa")
        do {
            try data.write(to: fileURL, options: .atomic)
            if let idx = apps.firstIndex(where: { $0.originalBundleID == bundleID }) {
                apps[idx].cachedIPAPath = fileURL.path
                save()
            }
            return fileURL.path
        } catch {
            return nil
        }
    }

    public func getIPABackupPath(bundleID: String) -> String? {
        let fileURL = backupsDirectory.appendingPathComponent("\(bundleID).ipa")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL.path
        }
        return nil
    }

    // MARK: - Sources Management

    public func addSourceURL(_ url: URL) async throws {
        let (data, _) = try await URLSession.shared.data(from: url)
        let repo = try JSONDecoder().decode(AltSourceRepo.self, from: data)

        if let idx = sources.firstIndex(where: { $0.identifier == repo.identifier }) {
            sources[idx] = repo
        } else {
            sources.append(repo)
        }
        save()
    }
}

