import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// tvOS view rendering the local HTTP server status, real-time logs,
/// and a high-resolution QR code generated via CoreImage for phone/desktop access.
public struct WebUploadView: View {
    @ObservedObject private var webServer = LANWebServer.shared
    @ObservedObject private var tunnelMonitor = TunnelMonitor.shared
    @ObservedObject private var registry = AppRegistryStore.shared

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    public init() {}

    public var body: some View {
        HStack(spacing: 50) {
            // Left Column: QR Code and URL
            VStack(spacing: 24) {
                Text("Web Control Center")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Inquadra il QR Code con il tuo smartphone o apri l'indirizzo nel browser del computer:")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                if let qrImage = generateQRCode(from: webServer.serverURL) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 260, height: 260)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                }

                Text(webServer.serverURL)
                    .font(.headline)
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(10)

                HStack(spacing: 12) {
                    Circle()
                        .fill(webServer.isRunning ? Color.green : Color.red)
                        .frame(width: 14, height: 14)
                    Text(webServer.isRunning ? "Server Attivo sulla porta 8080" : "Server Fermo")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 500)

            // Right Column: Live Event Logs & Quick Status
            VStack(alignment: .leading, spacing: 20) {
                Text("Stato Sistema & Log in Tempo Reale")
                    .font(.title3)
                    .fontWeight(.semibold)

                // Quick Status Badges
                HStack(spacing: 16) {
                    StatusPill(
                        label: "Tunnel utun",
                        isActive: tunnelMonitor.isTunnelActive,
                        detail: tunnelMonitor.activeInterface ?? "Inattivo"
                    )
                    StatusPill(
                        label: "Pairing File",
                        isActive: KeychainVault.shared.hasPairingFile(),
                        detail: KeychainVault.shared.hasPairingFile() ? "Presente" : "Mancante"
                    )
                    StatusPill(
                        label: "App Gestite",
                        isActive: true,
                        detail: "\(registry.apps.count) installate"
                    )
                }

                // Log Window
                VStack(alignment: .leading) {
                    Text("Attività Server:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                if webServer.logs.isEmpty {
                                    Text("In attesa di connessioni HTTP...")
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(Array(webServer.logs.enumerated()), id: \.offset) { idx, log in
                                        Text(log)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.green.opacity(0.9))
                                            .id(idx)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        }
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .frame(maxHeight: 380)
                        .onChange(of: webServer.logs.count) {
                            if let last = webServer.logs.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }

                Button(action: {
                    webServer.start()
                }) {
                    Label("Riavvia Web Server", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.card)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(40)
        .onAppear {
            webServer.start()
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            // Scale up the CIImage to prevent blurriness
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)

            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}

private struct StatusPill: View {
    let label: String
    let isActive: Bool
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(isActive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(detail)
                    .font(.caption)
                    .fontWeight(.bold)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }
}

