import SwiftUI

@main
struct ATVStoreApp: App {
    init() {
        Task { @MainActor in
            LANWebServer.shared.start()
            TunnelMonitor.shared.startPeriodicMonitoring()
            AppRegistryStore.shared.ensureSelfRegistration()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
