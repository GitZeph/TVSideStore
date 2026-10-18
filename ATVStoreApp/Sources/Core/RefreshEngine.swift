import Foundation
import SwiftUI
import Combine

/// Orchestrates the 5-step certificate renewal and app refresh pipeline:
/// [1/5] Tunnel check -> [2/5] IPA cache check/download -> [3/5] Profile renewal ->
/// [4/5] In-process Mach-O resigning -> [5/5] Lockdown AFC upload & install.
@MainActor
public final class RefreshEngine: ObservableObject {
    public static let shared = RefreshEngine()

    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var currentApp: InstalledApp?
    @Published public private(set) var currentStepIndex: Int = 0
    @Published public private(set) var currentStepDescription: String = ""
    @Published public private(set) var progressPercent: Double = 0.0
    @Published public private(set) var logs: [String] = []
    @Published public private(set) var lastError: String?

    private init() {}

    public func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
    }

    // MARK: - Refresh All Pipeline

    public func refreshAllApps() async {
        guard !isRefreshing else { return }
        self.isRefreshing = true
        self.logs.removeAll()
        self.lastError = nil

        let appsToRefresh = AppRegistryStore.shared.apps

        addLog("Avvio del refresh per \(appsToRefresh.count) applicazioni...")

        for app in appsToRefresh {
            do {
                try await refreshApp(app)
            } catch {
                addLog("ERRORE durante il refresh di \(app.name): \(error.localizedDescription)")
                self.lastError = error.localizedDescription
            }
        }

        self.isRefreshing = false
        self.currentApp = nil
        self.currentStepIndex = 0
        self.currentStepDescription = "Operazione completata."
    }

    // MARK: - Single App Refresh Pipeline

    public func refreshApp(_ app: InstalledApp) async throws {
        self.currentApp = app
        self.progressPercent = 0.0

        // =====================================================================
        // STEP 1/5: Verifica tunnel LocalDevVPN
        // =====================================================================
        self.currentStepIndex = 1
        self.currentStepDescription = "[1/5] Verifica tunnel LocalDevVPN (utun)..."
        addLog("[1/5] Controllo interfaccia utun e porta 62078...")

        await TunnelMonitor.shared.refresh()

        guard TunnelMonitor.shared.isTunnelActive else {
            throw NSError(
                domain: "RefreshEngine",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "LocalDevVPN non è attivo. Apri l'app LocalDevVPN sulla Apple TV e attiva il tunnel."]
            )
        }

        guard let pairingData = KeychainVault.shared.loadPairingFile() else {
            throw NSError(
                domain: "RefreshEngine",
                code: 102,
                userInfo: [NSLocalizedDescriptionKey: "Pairing file mancante. Caricalo tramite il Web Server locale (porta 8080)."]
            )
        }

        self.progressPercent = 0.20

        // =====================================================================
        // STEP 2/5: Controllo cache IPA o riscaricamento da URL sorgente
        // =====================================================================
        self.currentStepIndex = 2
        self.currentStepDescription = "[2/5] Controllo cache IPA locale o download..."
        addLog("[2/5] Ispezione cache in Library/Caches/IPABackups/\(app.originalBundleID).ipa...")

        var ipaPath = AppRegistryStore.shared.getIPABackupPath(bundleID: app.originalBundleID)

        if ipaPath == nil || !FileManager.default.fileExists(atPath: ipaPath!) {
            if let downloadURL = app.sourceURL {
                addLog("IPA purgato da tvOS! Riscaricamento da sorgente: \(downloadURL.absoluteString)...")
                let (data, _) = try await URLSession.shared.data(from: downloadURL)
                ipaPath = AppRegistryStore.shared.cacheIPABackup(bundleID: app.originalBundleID, data: data)
            } else {
                throw NSError(
                    domain: "RefreshEngine",
                    code: 201,
                    userInfo: [NSLocalizedDescriptionKey: "File .ipa di '\(app.name)' non trovato in cache e nessun URL sorgente configurato. Ricarica l'IPA via Web Upload."]
                )
            }
        }

        guard let finalIPAPath = ipaPath else {
            throw NSError(domain: "RefreshEngine", code: 202, userInfo: [NSLocalizedDescriptionKey: "Percorso IPA non valido."])
        }

        self.progressPercent = 0.40

        // =====================================================================
        // STEP 3/5: Rinnovo Provisioning Profile con i server Apple
        // =====================================================================
        self.currentStepIndex = 3
        self.currentStepDescription = "[3/5] Rinnovo Provisioning Profile (7 giorni)..."
        addLog("[3/5] Richiesta profilo per bundle '\(app.rewrittenBundleID)' a Apple Developer...")

        let sessionInfo = KeychainVault.shared.loadGSASession()
        let sessionToken = sessionInfo?.token ?? "local_session"
        let teamID = "FREE_TEAM_LOCAL"
        let deviceUDID = "00008030-00123456789ABCDE"

        // 1. Ensure App ID exists
        _ = try await RustBridge.shared.registerAppID(
            sessionToken: sessionToken,
            teamID: teamID,
            bundleID: app.rewrittenBundleID,
            appName: app.name
        )

        // 2. Provision fresh 7-day mobileprovision
        let provResult = try await RustBridge.shared.provisionProfile(
            sessionToken: sessionToken,
            teamID: teamID,
            bundleID: app.rewrittenBundleID,
            deviceUDID: deviceUDID
        )

        let profileBase64 = provResult["profile_base64"] as? String ?? ""

        // Load development certificate from Keychain or provision new one
        var p12Base64 = KeychainVault.shared.loadCertificate() ?? ""
        if p12Base64.isEmpty {
            addLog("Generazione nuova chiave RSA 2048-bit e certificato...")
            let certResult = try await RustBridge.shared.provisionCertificate(
                sessionToken: sessionToken,
                teamID: teamID,
                machineName: "SideStoreTV-AppleTV"
            )
            p12Base64 = certResult["p12_base64"] as? String ?? ""
            try? KeychainVault.shared.saveCertificate(p12Base64)
        }

        self.progressPercent = 0.60

        // =====================================================================
        // STEP 4/5: Firma pacchetto Mach-O in-process
        // =====================================================================
        self.currentStepIndex = 4
        self.currentStepDescription = "[4/5] Firma pacchetto Mach-O in-process..."
        addLog("[4/5] Firma CMS e generazione CodeResources per '\(app.name)'...")

        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let signedIPAPath = cachesURL.appendingPathComponent("signed_\(app.originalBundleID).ipa").path

        _ = try await RustBridge.shared.signIPA(
            inputIPA: finalIPAPath,
            outputIPA: signedIPAPath,
            p12Base64: p12Base64,
            p12Password: "",
            mobileprovisionBase64: profileBase64,
            newBundleID: app.isSelf ? nil : app.rewrittenBundleID,
            displayName: app.name
        ) { [weak self] percent, stage in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.progressPercent = 0.60 + (Double(percent) * 0.20 / 100.0)
                self.addLog("Firma: \(stage) (\(percent)%)")
            }
        }

        self.progressPercent = 0.80

        // =====================================================================
        // STEP 5/5: Installazione tramite mobile_installation_proxy
        // =====================================================================
        self.currentStepIndex = 5
        self.currentStepDescription = "[5/5] Installazione via mobile_installation_proxy..."
        addLog("[5/5] Upload AFC su /PublicStaging e trigger installazione...")

        // CRITICO PER IL SELF-REFRESH DI ATVStore:
        // Quando SideStoreTV aggiorna se stessa, tvOS chiude forzatamente il processo
        // non appena mobile_installation_proxy scambia il bundle.
        // Salva la nuova data di scadenza (7 giorni) SUBITO prima del comando finale!
        let newExpirationDate = Date().addingTimeInterval(7 * 86400)
        AppRegistryStore.shared.updateAppExpiry(bundleID: app.originalBundleID, newExpiry: newExpirationDate)
        AppRegistryStore.shared.save()

        if app.isSelf {
            addLog("AVVISO: Self-Refresh di SideStoreTV in corso. Il processo verrà riavviato automaticamente da tvOS.")
        }

        _ = try await RustBridge.shared.installIPA(
            host: TunnelMonitor.shared.targetHost,
            port: TunnelMonitor.shared.targetPort,
            pairingData: pairingData,
            ipaPath: signedIPAPath,
            bundleID: app.rewrittenBundleID
        ) { [weak self] percent, stage in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.progressPercent = 0.80 + (Double(percent) * 0.20 / 100.0)
                self.addLog("Installazione: \(stage) (\(percent)%)")
            }
        }

        self.progressPercent = 1.0
        addLog("SUCCESSO: '\(app.name)' rinnovata con successo fino al \(DateFormatter.localizedString(from: newExpirationDate, dateStyle: .medium, timeStyle: .short))!")

        // Clean up temporary signed file
        try? FileManager.default.removeItem(atPath: signedIPAPath)
    }
}

