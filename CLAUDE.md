# SideStoreTV (ATVStore)

SideStoreTV is a standalone on-device IPA installer and certificate refresh engine designed specifically for **Apple TV (tvOS 17.0+)**, eliminating the need for a local PC after initial bootstrapping.

---

## Critical Architectural Constraints (tvOS)

1. **No Persistent Documents Directory (`NSDocumentDirectory`):**
   - tvOS apps can only write persistent data within the **Keychain (`Security.framework`)** or small payloads in `UserDefaults` (<250 KB).
   - Any files written to `Library/Caches` (`NSCachesDirectory`) may be purged by tvOS at any time under disk pressure.
   - All critical secrets (Pairing File `.mobiledevicepairing`, GSA session tokens, `.p12` development private keys, and the JSON app registry) MUST reside in Keychain or be reconstructible from remote source URLs.

2. **Network Loopback via LocalDevVPN:**
   - Free Apple Developer accounts cannot obtain the `NEPacketTunnelProvider` entitlement.
   - SideStoreTV leverages the free **LocalDevVPN** app to establish a local `utun*` tunnel interface.
   - `TunnelMonitor.swift` inspects network interfaces via `getifaddrs()` to ensure `utun` is active before attempting lockdown connections to `10.7.0.1:62078` or local subnet reflection.

3. **No `WKWebView` or `UIDocumentPickerViewController`:**
   - WebKit and document pickers are not available on `appletvos`.
   - SideStoreTV embeds a native HTTP server (`LANWebServer.swift` via `Network.framework` on port 8080) and renders a QR code on TV. Users manage pairing files, IPA uploads, and 2FA via their phone or desktop browser.

4. **Strict `fork()` / `exec()` Ban (Everything In-Process):**
   - tvOS forbids spawning child processes.
   - Lockdownd protocol, Apple GSA SRP-6a authentication, ZIP decompression, and Mach-O CMS codesigning run entirely in-process using static C/C++ and Rust libraries (`ATVStoreCore.xcframework`).

5. **10-Foot Focus Engine UI:**
   - All SwiftUI navigation is optimized for the Siri Remote using `@FocusState`, `.buttonStyle(.card)`, and high-contrast TV cards.

---

## Monorepo Layout

- **`rust-core/`**: Rust static library exposing C FFI for Apple GSA authentication, developer services, lockdown protocol, AFC staging, and mobile_installation_proxy client.
- **`cpp-signer/`**: C++ static library providing in-process Mach-O codesigning (`zsign_ipa`).
- **`ATVStoreApp/`**: Native SwiftUI tvOS application (XcodeGen project).
- **`bootstrap-cli/`**: Desktop tool for initial mDNS discovery, wireless pairing, and bootstrap IPA installation.
- **`Makefile`**: Multi-architecture build orchestration targeting `aarch64-apple-tvos` (physical Apple TV) and `aarch64-apple-tvos-sim` (Simulator).

---

## Build Commands

```bash
# Build Rust core for host testing
make rust-host

# Compile Rust core for tvOS (Nightly -Z build-std)
make rust-tvos
make rust-tvos-sim

# Generate ATVStoreCore.xcframework
make xcframework

# Generate Xcode Project
make project
```

