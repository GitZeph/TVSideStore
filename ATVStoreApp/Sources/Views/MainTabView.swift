import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: Int = 0

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            MyAppsView()
                .tag(0)
                .tabItem {
                    Label("My Apps", systemImage: "square.grid.2x2.fill")
                }

            SourcesView()
                .tag(1)
                .tabItem {
                    Label("Sources", systemImage: "globe")
                }

            WebUploadView()
                .tag(2)
                .tabItem {
                    Label("Web Upload", systemImage: "arrow.up.doc.fill")
                }

            SettingsView()
                .tag(3)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

