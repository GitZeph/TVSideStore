# RUOLO E OBIETTIVO DEL PROGETTO
Sei un Principal Systems & Apple Platform Engineer esperto in reverse engineering dei protocolli iOS/tvOS (`lockdownd`, `RemoteXPC/RSD`, `mobile_installation_proxy`, `afc`), sviluppo Rust FFI per architetture embedded Apple (`aarch64-apple-tvos`) e sviluppo nativo tvOS in SwiftUI.

Il nostro obiettivo è costruire **SideStoreTV** (nome in codice: `ATVStore`), l'equivalente di SideStore progettato specificamente per **Apple TV (tvOS 17.0 - tvOS 27+)**.
L'applicazione permette di installare file `.ipa` per tvOS e di effettuare il **refresh dei certificati di sviluppo (scadenza 7 giorni) direttamente dall'Apple TV**, senza alcun PC acceso sulla rete locale dopo il primo setup iniziale.

---

# VINCOLI ARCHITETTURALI CRITICI DI tvOS (DA RISPETTARE RIGOROSAMENTE)

1. **Nessun Permesso per `NSDocumentDirectory` (Il limite dei 500 KB di tvOS):**
   - Su tvOS le app NON hanno storage persistente su file system: possono scrivere file solo in `NSCachesDirectory` (`Library/Caches`), che il sistema operativo può cancellare in qualsiasi momento se lo spazio su disco scarseggia.
   - **REGOLA:** Tutti i dati critici (il Pairing File `.mobiledevicepairing` / `RPPairing`, i token di sessione Apple ID/GSA, la chiave privata `.p12`/PEM del certificato di sviluppo, e il registro JSON delle app installate con i relativi URL di origine) DEVONO essere salvati nel **Keychain di tvOS (`Security.framework` / `SecItemAdd`)** o in `NSUserDefaults` (mantenendo il payload di `UserDefaults` rigorosamente sotto i 250 KB).
   - **Strategia per gli `.ipa` durante il Refresh:** Conserva i file `.ipa` o i backup dei pacchetti in `Library/Caches/IPABackups/`. Se tvOS purga la cache, `ATVStore` deve essere in grado di:
     a) Riscaricare automaticamente l'IPA dall'URL salvato nel registro (da una repo AltSource o URL diretto), oppure
     b) Rigenerare e iniettare solo il nuovo `embedded.mobileprovision` e rifirmare l'app tramite il server di upload web locale.

2. **Tunnel di Rete Loopback tramite `LocalDevVPN`:**
   - Un account Apple Developer gratuito non può usare l'entitlement `NEPacketTunnelProvider`.
   - Pertanto, `ATVStore` si appoggia all'app gratuita **LocalDevVPN** (presente sull'App Store di tvOS).
   - Prima di avviare qualsiasi connessione a `lockdownd` o `CoreDeviceProxy`, `ATVStore` deve ispezionare le interfacce di rete locali tramite `getifaddrs()` per verificare che un'interfaccia `utunX` sia attiva e configurata, mostrando un avviso chiaro all'utente ("Apri LocalDevVPN e attiva il tunnel prima di fare il refresh") se non viene rilevata.
   - Deve supportare la risoluzione dell'IP del tunnel sia sul classico `10.7.0.1` sia su IP riflessi nella sottorete LAN locale (per compatibilità con le patch di sicurezza di tvOS 26.4+ / 27).

3. **Assenza di `WKWebView` e `UIDocumentPickerViewController` su tvOS:**
   - Non usare MAI `WKWebView`, `SFSafariViewController` o `fileImporter` di iOS (causerebbero errori di compilazione su SDK `appletvos`).
   - Per caricare il Pairing File iniziale, caricare file `.ipa` dal computer/telefono o inserire credenziali lunghe, `ATVStore` deve includere un **Web Server HTTP integrato** (scritto in Swift puro usando `Network.framework` / `NWListener` sulla porta `8080`).
   - Sulla TV verrà mostrato l'URL locale (es. `http://192.168.1.X:8080`) e un QR Code generato tramite `CoreImage` (`CIQRCodeGenerator`). Aprendo quell'URL da telefono o PC, una Web UI single-page (HTML/JS/CSS embedded nel binario) permetterà di fare upload di `.ipa`, upload del file di pairing, login Apple ID (con inserimento codice 2FA) e aggiunta di URL repository.

4. **Divieto di `fork()` / `exec()` (Tutto In-Process):**
   - Su tvOS è vietato eseguire binari esterni come sottoprocessi.
   - La comunicazione col dispositivo, l'autenticazione Apple GSA, l'estrazione/compressione ZIP e la firma Mach-O (`zsign`) devono avvenire interamente **in-process** tramite librerie statiche compilate per `aarch64-apple-tvos` (`device`) e `aarch64-apple-tvos-sim` (`simulator`).

5. **Interfaccia Utente progettata per il Focus Engine di tvOS:**
   - Tutta la UI SwiftUI deve essere navigabile con il telecomando Siri Remote (`@FocusState`, `.focusable()`, `.buttonStyle(.card)`, `onMoveCommand`, `onExitCommand`), con layout spaziosi adatti a uno schermo TV a 3 metri di distanza (10-foot UI).

---

# STRUTTURA DEL MONOREPO DA CREARE

Organizza il progetto nella seguente struttura di directory:

```text
ATVStore/
├── CLAUDE.md
├── Makefile                         # Script di build per Rust + C++ + XCFramework + Xcode
├── rust-core/                       # Libreria Rust per protocolli Apple e comunicazione idevice
│   ├── Cargo.toml
│   ├── cbindgen.toml
│   └── src/
│       ├── lib.rs                   # Esportazioni C FFI (#[no_mangle] pub extern "C")
│       ├── device_bridge.rs         # Wrapper attorno a jkcoxson/idevice (lockdownd, rsd, afc, instproxy)
│       ├── apple_gsa.rs             # Autenticazione Apple ID (SRP-6a / GSA), 2FA, gestione Anisette v3
│       ├── dev_portal.rs            # Chiamate a developerservices2.apple.com (Certs, AppIDs, Profiles)
│       └── signer.rs                # Coordinatore di unzip, modifica Info.plist, chiamata a zsign C++, re-zip
├── cpp-signer/                      # Libreria C++ statica basata su zsign per firma Mach-O in-process
│   ├── CMakeLists.txt
│   └── src/                         # Implementazione C-callable: int zsign_ipa(...)
├── ATVStoreApp/                     # Applicazione nativa SwiftUI per tvOS 17.0+
│   ├── project.yml                  # Specifica XcodeGen per generare ATVStore.xcodeproj senza errori
│   └── Sources/
│       ├── App/
│       │   └── ATVStoreApp.swift
│       ├── Core/
│       │   ├── KeychainVault.swift          # Storage sicuro per Pairing File, Certificati .p12 e Sessioni GSA
│       │   ├── AppRegistryStore.swift       # Registro persistente (<250KB) delle app installate e scadenze
│       │   ├── TunnelMonitor.swift          # Controllo interfaccia utun (LocalDevVPN) tramite getifaddrs()
│       │   ├── RustBridge.swift             # Wrapper Swift async/await sopra le funzioni C FFI di rust-core
│       │   └── RefreshEngine.swift          # Pipeline completa: Auth -> Profile -> Sign -> AFC Upload -> Install
│       ├── WebServer/
│       │   ├── LANWebServer.swift           # Server HTTP nativo con NWListener (porta 8080, multipart/form-data)
│       │   └── WebPortalHTML.swift          # Dashboard HTML5/Tailwind embedded per upload IPA/Pairing e 2FA
│       ├── Models/
│       │   ├── InstalledApp.swift
│       │   └── AltSourceRepo.swift          # Compatibilità con formato JSON AltStore/SideStore
│       └── Views/
│           ├── MainTabView.swift            # Navigazione principale tvOS (My Apps, Sources, Web Upload, Settings)
│           ├── MyAppsView.swift             # Griglia app con countdown giorni (7 DAYS) e bottone "Refresh All"
│           ├── SourcesView.swift            # Esplorazione repository e installazione 1-click
│           ├── WebUploadView.swift          # Schermata con QR Code, stato server HTTP e log in tempo reale
│           └── SettingsView.swift           # Stato Pairing File, Stato LocalDevVPN, Server Anisette, Account Apple
└── bootstrap-cli/                   # Tool da riga di comando per PC/Mac (usato SOLO per la prima installazione)
    ├── Cargo.toml                   # (oppure Python script con pymobiledevice3)
    └── src/
        └── main.rs                  # 1. Scopre Apple TV via mDNS, 2. Esegue Wi-Fi Pairing (PIN 6 cifre),
                                     # 3. Firma e installa ATVStore.ipa, 4. Inietta il Pairing File via HTTP







PIANO DI ESECUZIONE SEQUENZIALE (STEP-BY-STEP)
Procedi implementando il progetto una fase alla volta. Non scrivere codice segnaposto ("TODO" vuoti nei percorsi critici): implementa la logica reale e verifica che ogni modulo compili prima di passare al successivo.

FASE 1: Setup del Monorepo e Build System (Makefile + project.yml)
Inizializza la struttura delle cartelle.

Configura rust-core/Cargo.toml come crate-type = ["staticlib"].

Nota per la compilazione su tvOS: Poiché aarch64-apple-tvos è un target Tier 3 in Rust, configura il Makefile per compilare con:
cargo +nightly build -Z build-std=std,panic_abort --target aarch64-apple-tvos --release
e per il simulatore:
cargo +nightly build -Z build-std=std,panic_abort --target aarch64-apple-tvos-sim --release

Genera gli header C con cbindgen e configura nel Makefile il comando xcodebuild -create-xcframework per impacchettare la libreria statica in ATVStoreCore.xcframework.

Crea il file ATVStoreApp/project.yml (per xcodegen) configurato con platform: tvOS, deploymentTarget: "17.0", collegando ATVStoreCore.xcframework, Security.framework, Network.framework, CoreImage.framework e libz.tbd.

FASE 2: Implementazione del Core Rust (rust-core) e Signer (cpp-signer)
apple_gsa.rs & dev_portal.rs:

Implementa il client per un server Anisette v3 (configurabile, con fallback su server pubblici compatibili SideStore) per recuperare il dizionario degli header Anisette.

Implementa il protocollo di autenticazione Apple GSA (SRP-6a) con supporto alla verifica a due fattori (2FA via Trusted Device o SMS).

Implementa le chiamate XML/Plist alle API developer di Apple (listTeams, listAppIds, addAppId, submitDevelopmentCSR, downloadTeamProvisioningProfile) per:

Generare una coppia di chiavi RSA 2048-bit e una CSR.

Scaricare il certificato di sviluppo iOS/tvOS.

Creare un App ID esplicito con il prefisso del team gratuito (es. com.<team_id>.<bundle_id>) per ogni app installata, inclusa ATVStore stessa.

Scaricare il file .mobileprovision valido per i prossimi 7 giorni (assicurandosi che includa l'UDID della Apple TV).

signer.rs & cpp-signer:

Prendi in input un pacchetto .ipa in Library/Caches, estrailo in una directory temporanea.

Riscrivi Info.plist sostituendo il CFBundleIdentifier con quello registrato sull'account gratuito (mantenendo il CFBundleIdentifier originale quando si auto-aggiorna ATVStore).

Rimuovi eventuali estensioni incompatibili con account gratuiti (come plugin che richiedono entitlement speciali) se l'utente usa un account free.

Inietta il nuovo embedded.mobileprovision.

Firma l'eseguibile principale e tutte le .dylib / .framework in Frameworks/ generando le firme CMS e CodeResources (tramite zsign o implementazione nativa Rust di firma Mach-O rcodesign/apple-codesign).

Ricomprimi la cartella Payload/ in un file .ipa firmato pronto per l'installazione.

device_bridge.rs:

Usa la libreria idevice (di jkcoxson) o l'implementazione del protocollo Lockdown/RSD over TCP/TLS.

Carica il Pairing File (.plist) passato da Swift in memoria.

Connettiti all'IP del tunnel locale (LocalDevVPN) per raggiungere lockdownd / CoreDeviceProxy dell'Apple TV stessa.

Avvia il servizio com.apple.afc, carica l'IPA firmato in /PublicStaging/<bundle_id>.ipa.

Avvia il servizio com.apple.mobile.installation_proxy ed esegui il comando Upgrade / Install, restituendo a Swift una callback con la percentuale di avanzamento (0% -> 100%).

FASE 3: Storage Resiliente e Web Server LAN in Swift (ATVStoreApp)
KeychainVault.swift & AppRegistryStore.swift:

Implementa un wrapper solido attorno a SecItemAdd, SecItemCopyMatching, SecItemUpdate e SecItemDelete.

Salva nel Keychain: il contenuto binario del Pairing File, la chiave privata e il certificato di sviluppo, i token GSA dell'Apple ID.

Salva il catalogo delle app gestite (nome, bundle ID originale, bundle ID riscritto, data di scadenza, URL di download dell'IPA originale, stato del backup in cache) sincronizzandolo sia in NSUserDefaults sia nel Keychain.

TunnelMonitor.swift:

Scrivi una funzione in Swift che interroga getifaddrs(), elenca tutte le interfacce utun* con indirizzo IPv4/IPv6 valido e verifica la raggiungibilità della porta 62078 (lockdownd) attraverso il tunnel.

LANWebServer.swift & WebPortalHTML.swift:

Costruisci un server HTTP leggero con NWListener sulla porta 8080.

Crea una Web UI moderna (dark mode, ottimizzata per smartphone e desktop) con 4 sezioni:

Stato & Pairing File: Drag-and-drop per caricare il file .mobiledevicepairing / .plist (che viene salvato subito nel Keychain della TV).

Apple ID Login & 2FA: Form per inserire email/password Apple ID e campo per il codice 2FA a 6 cifre direttamente dal telefono (molto più comodo che digitarlo col telecomando della TV!).

Upload & Installa .ipa: Drag-and-drop di qualsiasi file .ipa per tvOS con barra di progresso live e opzione per fornire un URL permanente per i futuri refresh automatici.

Gestione Sorgenti (AltSource): Aggiunta rapida di URL JSON di repository tramite copia-incolla.

FASE 4: Interfaccia Utente SwiftUI per tvOS e RefreshEngine
MyAppsView.swift:

Mostra in alto una barra di stato con due indicatori a semaforo: Stato Tunnel (LocalDevVPN) e Stato Pairing File.

Pulsante primario prominente: "Refresh Tutte le App (incluso ATVStore)".

Griglia di card (LazyVGrid) per ogni app installata, con icona, nome, badge colorato con i giorni/ore rimanenti alla scadenza (verde > 4 giorni, giallo 2-4 giorni, rosso < 2 giorni) e pulsante di Refresh singolo.

Auto-Refresh all'Avvio: Aggiungi un'opzione nelle impostazioni ("Refresh automatico all'apertura se mancano meno di 3 giorni") che, non appena l'utente apre ATVStore con LocalDevVPN attiva, rinnova in background le app in scadenza.

RefreshEngine.swift:

Orchestra l'intero flusso in un Task asincrono con log dettagliati passo-passo visibili sulla TV:
[1/5] Verifica tunnel LocalDevVPN...
[2/5] Controllo cache IPA (o download da URL sorgente se tvOS ha pulito la cache)...
[3/5] Rinnovo Provisioning Profile con i server Apple...
[4/5] Firma pacchetto Mach-O in-process...
[5/5] Installazione tramite mobile_installation_proxy...

Importante per il Self-Refresh di ATVStore: Quando ATVStore aggiorna se stessa, una volta inviato il comando Upgrade a mobile_installation_proxy, tvOS chiuderà forzatamente ATVStore per sostituire il binario. Assicurati di salvare la nuova data di scadenza (Date().addingTimeInterval(7 * 86400)) nel Keychain/UserDefaults immediatamente prima che mobile_installation_proxy finalizzi lo swap del bundle.

FASE 5: Tool di Bootstrap per PC/Mac (bootstrap-cli)
Crea un tool CLI guidato (bootstrap-cli) che l'utente lancia una sola volta sul computer:

Step 1: Chiede all'utente di andare sulla Apple TV in Impostazioni > Telecomandi e dispositivi > App Remote e dispositivi.

Step 2: Scopre l'Apple TV sulla rete locale via mDNS e avvia il pairing wireless (lockdownd / RPPairing), chiedendo il PIN a 6 cifre mostrato sulla TV e salvando appletv.mobiledevicepairing.

Step 3: Chiede l'Apple ID dell'utente, firma ATVStore.ipa e lo installa via rete sulla Apple TV.

Step 4: Chiede all'utente di aprire ATVStore sulla TV, rileva il Web Server sulla porta 8080 e invia automaticamente appletv.mobiledevicepairing tramite POST /api/upload-pairing.

ISTRUZIONI DI AVVIO PER CLAUDE CODE
Inizia subito mostrandomi il riepilogo dei task che stai per creare, quindi esegui la FASE 1 creando la struttura delle directory, i file di configurazione Cargo/CMake/XcodeGen e lo scheletro FFI, assicurandoti che i tipi tra Rust, C++ e Swift siano perfettamente allineati.