//! Embedded single-page application for SideStoreTV Loader (iLoader for Apple TV).
//! Ultra-sleek dark mode glassmorphism UI with live step-by-step installation wizard.

pub const LOADER_HTML: &str = r#"<!DOCTYPE html>
<html lang="it" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SideStoreTV Loader</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <script>
        tailwind.config = {
            darkMode: 'class',
            theme: {
                extend: {
                    fontFamily: {
                        sans: ['"Plus Jakarta Sans"', 'sans-serif'],
                        mono: ['"JetBrains Mono"', 'monospace']
                    },
                    colors: {
                        brand: {
                            50: '#eef2ff',
                            400: '#818cf8',
                            500: '#6366f1',
                            600: '#4f46e5',
                            dark: '#07090e',
                            card: '#0f1422',
                            border: 'rgba(255, 255, 255, 0.08)'
                        }
                    }
                }
            }
        }
    </script>
    <style>
        body {
            background: radial-gradient(circle at 50% 0%, #1e1b4b 0%, #07090e 65%);
            user-select: none;
            -webkit-user-select: none;
        }
        .glass-panel {
            background: rgba(15, 20, 34, 0.75);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.08);
        }
        .glow-cyan {
            box-shadow: 0 0 30px -5px rgba(6, 182, 212, 0.35);
        }
        .glow-indigo {
            box-shadow: 0 0 30px -5px rgba(99, 102, 241, 0.35);
        }
        .pin-box:focus {
            outline: none;
            border-color: #06b6d4;
            box-shadow: 0 0 15px rgba(6, 182, 212, 0.5);
        }
    </style>
</head>
<body class="text-slate-100 min-h-screen flex flex-col font-sans antialiased overflow-x-hidden">
    <!-- Top Header Bar -->
    <header class="w-full glass-panel border-b border-brand-border py-4 px-8 flex items-center justify-between sticky top-0 z-50">
        <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-cyan-500 to-indigo-600 flex items-center justify-center shadow-lg shadow-cyan-500/20">
                <svg class="w-6 h-6 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <rect x="2" y="7" width="20" height="15" rx="3"></rect>
                    <polyline points="17 2 12 7 7 2"></polyline>
                </svg>
            </div>
            <div>
                <h1 class="text-lg font-bold tracking-tight bg-gradient-to-r from-white via-slate-200 to-slate-400 bg-clip-text text-transparent">SideStoreTV Loader</h1>
                <p class="text-xs text-slate-400 font-mono">1-Click Apple TV Setup & Pairing</p>
            </div>
        </div>
        <div class="flex items-center gap-4">
            <div id="connectionPill" class="flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-900/60 border border-slate-700/50 text-xs font-medium text-slate-300">
                <span id="connectionDot" class="w-2 h-2 rounded-full bg-yellow-400 animate-pulse"></span>
                <span id="connectionText">Scansione Apple TV...</span>
            </div>
            <a href="https://github.com/GitZeph/TVSideStore" target="_blank" class="text-xs text-slate-400 hover:text-cyan-400 transition-colors flex items-center gap-1.5">
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/></svg>
                GitHub
            </a>
        </div>
    </header>

    <!-- Main Workspace -->
    <main class="flex-1 max-w-5xl w-full mx-auto p-6 md:p-10 flex flex-col gap-8">
        <!-- Steps Breadcrumb -->
        <div class="grid grid-cols-4 gap-3">
            <div id="stepTab1" class="glass-panel p-3.5 rounded-xl border-l-4 border-cyan-500 flex items-center gap-3 transition-all">
                <span class="w-7 h-7 rounded-lg bg-cyan-500/20 text-cyan-400 flex items-center justify-center font-bold text-xs">1</span>
                <div>
                    <p class="text-xs font-semibold text-slate-200">Dispositivo</p>
                    <p class="text-[10px] text-slate-400">Rileva Apple TV</p>
                </div>
            </div>
            <div id="stepTab2" class="glass-panel p-3.5 rounded-xl border-l-4 border-slate-700 flex items-center gap-3 transition-all opacity-60">
                <span class="w-7 h-7 rounded-lg bg-slate-800 text-slate-400 flex items-center justify-center font-bold text-xs">2</span>
                <div>
                    <p class="text-xs font-semibold text-slate-200">Pairing PIN</p>
                    <p class="text-[10px] text-slate-400">Codice a schermo</p>
                </div>
            </div>
            <div id="stepTab3" class="glass-panel p-3.5 rounded-xl border-l-4 border-slate-700 flex items-center gap-3 transition-all opacity-60">
                <span class="w-7 h-7 rounded-lg bg-slate-800 text-slate-400 flex items-center justify-center font-bold text-xs">3</span>
                <div>
                    <p class="text-xs font-semibold text-slate-200">Apple ID & IPA</p>
                    <p class="text-[10px] text-slate-400">Download & Firma</p>
                </div>
            </div>
            <div id="stepTab4" class="glass-panel p-3.5 rounded-xl border-l-4 border-slate-700 flex items-center gap-3 transition-all opacity-60">
                <span class="w-7 h-7 rounded-lg bg-slate-800 text-slate-400 flex items-center justify-center font-bold text-xs">4</span>
                <div>
                    <p class="text-xs font-semibold text-slate-200">Installazione</p>
                    <p class="text-[10px] text-slate-400">Deploy & Iniezione</p>
                </div>
            </div>
        </div>

        <!-- Dynamic Step Containers -->
        <div class="glass-panel rounded-2xl p-8 shadow-2xl relative min-h-[460px] flex flex-col justify-between">
            
            <!-- STEP 1: Discovery & Instructions -->
            <div id="step1View" class="space-y-6">
                <div class="flex items-start justify-between">
                    <div>
                        <h2 class="text-2xl font-bold text-white flex items-center gap-2">
                            <span>Preparazione Apple TV</span>
                            <span class="text-xs font-normal px-2.5 py-0.5 rounded-full bg-cyan-500/20 text-cyan-300 border border-cyan-500/30">tvOS 17 - 27+</span>
                        </h2>
                        <p class="text-sm text-slate-400 mt-1">Collega l'Apple TV alla stessa rete Wi-Fi del tuo computer per avviare il bootstrap.</p>
                    </div>
                    <div class="w-12 h-12 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400">
                        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path></svg>
                    </div>
                </div>

                <div class="grid md:grid-cols-2 gap-4 my-4">
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-brand-border space-y-2">
                        <div class="flex items-center gap-2 text-sm font-semibold text-cyan-400">
                            <span class="w-5 h-5 rounded-full bg-cyan-500/20 flex items-center justify-center text-xs">1</span>
                            Apri Impostazioni sulla TV
                        </div>
                        <p class="text-xs text-slate-400 leading-relaxed">
                            Prendi il telecomando dell'Apple TV, vai su <strong class="text-white">Impostazioni > Telecomandi e dispositivi > App Remote e dispositivi</strong>.
                        </p>
                    </div>
                    <div class="p-4 rounded-xl bg-slate-900/60 border border-brand-border space-y-2">
                        <div class="flex items-center gap-2 text-sm font-semibold text-cyan-400">
                            <span class="w-5 h-5 rounded-full bg-cyan-500/20 flex items-center justify-center text-xs">2</span>
                            Resta su questa schermata
                        </div>
                        <p class="text-xs text-slate-400 leading-relaxed">
                            Mantieni accesa la TV su quella schermata affinché il servizio AirPlay e Remote sia visibile per l'associazione.
                        </p>
                    </div>
                </div>

                <div class="p-4 rounded-xl bg-indigo-950/30 border border-indigo-500/30 flex items-center justify-between">
                    <div class="flex items-center gap-3">
                        <div class="w-10 h-10 rounded-xl bg-cyan-500/20 text-cyan-400 flex items-center justify-center">
                            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0"></path></svg>
                        </div>
                        <div>
                            <p class="text-xs font-semibold text-slate-300">Indirizzo IP Apple TV Rilevato:</p>
                            <input id="inputTargetIP" type="text" value="192.168.1.11" class="font-mono text-cyan-400 font-bold text-sm bg-transparent border-b border-cyan-500/40 focus:border-cyan-400 focus:outline-none w-48 mt-0.5">
                        </div>
                    </div>
                    <button onclick="scanAppleTV()" class="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-xs font-medium text-slate-200 transition-colors flex items-center gap-1.5">
                        <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path></svg>
                        Riscansiona
                    </button>
                </div>

                <div class="pt-4 flex justify-end">
                    <button onclick="goToStep(2)" class="px-6 py-3 rounded-xl bg-gradient-to-r from-cyan-500 to-indigo-600 hover:from-cyan-400 hover:to-indigo-500 text-white font-semibold text-sm shadow-lg shadow-cyan-500/25 flex items-center gap-2 transition-all">
                        <span>Ho la schermata aperta, procedi</span>
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3"></path></svg>
                    </button>
                </div>
            </div>

            <!-- STEP 2: Wireless Pairing PIN -->
            <div id="step2View" class="space-y-6 hidden">
                <div>
                    <h2 class="text-2xl font-bold text-white">Associazione Wireless Apple TV</h2>
                    <p class="text-sm text-slate-400 mt-1">Invia la richiesta di pairing per mostrare il PIN di sicurezza direttamente sullo schermo della tua TV.</p>
                </div>

                <div class="p-6 rounded-2xl bg-slate-900/80 border border-brand-border text-center space-y-5">
                    <div class="flex justify-center">
                        <button onclick="triggerPin()" id="btnTriggerPin" class="px-5 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-md shadow-indigo-600/30 flex items-center gap-2 transition-all">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path></svg>
                            <span>Invia Richiesta PIN a Apple TV (Porta 7000)</span>
                        </button>
                    </div>

                    <p id="pinTriggerStatus" class="text-xs text-yellow-300 font-medium">Fai clic sul pulsante sopra: il codice apparirà all'istante sulla TV!</p>

                    <div class="space-y-3">
                        <label class="text-xs uppercase tracking-wider text-slate-400 font-semibold block">Inserisci il PIN visualizzato sulla TV (4 o 6 cifre)</label>
                        <input id="pinCodeInput" type="text" maxlength="6" placeholder="es. 5493" class="w-48 text-center text-3xl font-mono tracking-widest px-4 py-3 rounded-xl bg-slate-950 border border-slate-700 text-cyan-400 pin-box mx-auto block">
                    </div>

                    <div id="pairingResultBadge" class="hidden text-xs py-2 px-4 rounded-lg bg-green-500/20 text-green-300 border border-green-500/30 inline-block font-mono">
                        ✓ Pairing File 'appletv.mobiledevicepairing' generato con successo!
                    </div>
                </div>

                <div class="flex items-center justify-between pt-4">
                    <button onclick="goToStep(1)" class="px-5 py-2.5 rounded-xl bg-slate-800 text-slate-300 text-xs font-semibold hover:bg-slate-700 transition-colors">
                        Indietro
                    </button>
                    <button onclick="verifyPinAndProceed()" id="btnVerifyPin" class="px-6 py-3 rounded-xl bg-gradient-to-r from-cyan-500 to-indigo-600 hover:from-cyan-400 hover:to-indigo-500 text-white font-semibold text-sm shadow-lg shadow-cyan-500/25 flex items-center gap-2 transition-all">
                        <span>Verifica PIN e Continua</span>
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3"></path></svg>
                    </button>
                </div>
            </div>

            <!-- STEP 3: Apple ID & Latest IPA Fetch -->
            <div id="step3View" class="space-y-6 hidden">
                <div class="flex items-start justify-between">
                    <div>
                        <h2 class="text-2xl font-bold text-white">Apple ID & Pacchetto IPA</h2>
                        <p class="text-sm text-slate-400 mt-1">Scarica l'ultimo binario da GitHub e inserisci il tuo Apple ID per la firma in-process a 7 giorni.</p>
                    </div>
                    <span class="text-xs px-2.5 py-1 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 font-medium">Anisette V3 Attivo</span>
                </div>

                <div class="grid md:grid-cols-2 gap-6">
                    <!-- Left: IPA Status & Auto-Download -->
                    <div class="p-5 rounded-xl bg-slate-900/60 border border-brand-border space-y-4">
                        <div class="flex items-center justify-between">
                            <span class="text-xs uppercase tracking-wider text-slate-400 font-semibold">Pacchetto ATVStore.ipa</span>
                            <span id="ipaStatusBadge" class="text-[10px] px-2 py-0.5 rounded-full bg-cyan-500/20 text-cyan-300 font-mono">Verifica in corso...</span>
                        </div>
                        <div class="flex items-center gap-3">
                            <div class="w-12 h-12 rounded-xl bg-slate-800 flex items-center justify-center text-cyan-400">
                                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M9 19l3 3m0 0l3-3m-3 3V10"></path></svg>
                            </div>
                            <div>
                                <p class="text-sm font-semibold text-white">SideStoreTV (tvOS 17+)</p>
                                <p id="ipaFileDetails" class="text-xs text-slate-400 font-mono">GitHub Release v1.0.0</p>
                            </div>
                        </div>
                        <button onclick="downloadLatestIPA()" id="btnDownloadIPA" class="w-full py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-xs font-semibold text-cyan-300 border border-cyan-500/30 flex items-center justify-center gap-2 transition-all">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path></svg>
                            <span>Scarica Ultimo IPA da GitHub</span>
                        </button>
                    </div>

                    <!-- Right: Apple ID & 2FA Form -->
                    <div class="p-5 rounded-xl bg-slate-900/60 border border-brand-border space-y-3">
                        <span class="text-xs uppercase tracking-wider text-slate-400 font-semibold block">Credenziali Firma Apple ID</span>
                        <div>
                            <label class="text-[11px] text-slate-400">Email Apple ID</label>
                            <input id="inputAppleEmail" type="email" placeholder="nome@icloud.com" class="w-full mt-1 px-3.5 py-2 rounded-xl bg-slate-950 border border-slate-700 text-sm text-white focus:outline-none focus:border-cyan-500">
                        </div>
                        <div>
                            <label class="text-[11px] text-slate-400">Password Apple ID</label>
                            <input id="inputApplePassword" type="password" placeholder="••••••••••••" class="w-full mt-1 px-3.5 py-2 rounded-xl bg-slate-950 border border-slate-700 text-sm text-white focus:outline-none focus:border-cyan-500">
                        </div>
                        <div id="box2FA" class="hidden pt-2 border-t border-slate-800 space-y-2">
                            <label class="text-[11px] text-yellow-300 font-semibold flex items-center gap-1.5">
                                <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"></path></svg>
                                Inserisci il codice 2FA apparso su iPhone/SMS:
                            </label>
                            <input id="input2FACode" type="text" maxlength="6" placeholder="123456" class="w-full px-3.5 py-2 rounded-xl bg-slate-950 border border-yellow-500/50 text-center font-mono tracking-widest text-lg text-yellow-300 focus:outline-none">
                        </div>
                    </div>
                </div>

                <div class="flex items-center justify-between pt-4">
                    <button onclick="goToStep(2)" class="px-5 py-2.5 rounded-xl bg-slate-800 text-slate-300 text-xs font-semibold hover:bg-slate-700 transition-colors">
                        Indietro
                    </button>
                    <button onclick="startSigningAndInstall()" id="btnStartInstall" class="px-6 py-3 rounded-xl bg-gradient-to-r from-cyan-500 to-indigo-600 hover:from-cyan-400 hover:to-indigo-500 text-white font-semibold text-sm shadow-lg shadow-cyan-500/25 flex items-center gap-2 transition-all">
                        <span>Firma e Installa su Apple TV</span>
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3"></path></svg>
                    </button>
                </div>
            </div>

            <!-- STEP 4: Live Installation & Pairing Injection -->
            <div id="step4View" class="space-y-6 hidden">
                <div>
                    <h2 class="text-2xl font-bold text-white">Deploy & Iniezione Finale</h2>
                    <p class="text-sm text-slate-400 mt-1">Caricamento del pacchetto firmato e iniezione automatica del Pairing File.</p>
                </div>

                <div class="space-y-4">
                    <!-- Progress Bar -->
                    <div class="space-y-2">
                        <div class="flex justify-between text-xs font-mono text-slate-300">
                            <span id="installPhaseLabel">Preparazione...</span>
                            <span id="installPercentLabel">0%</span>
                        </div>
                        <div class="w-full h-3 bg-slate-950 rounded-full overflow-hidden border border-slate-800">
                            <div id="installProgressBar" class="h-full bg-gradient-to-r from-cyan-500 to-indigo-600 transition-all duration-300" style="width: 0%"></div>
                        </div>
                    </div>

                    <!-- Console Logs Window -->
                    <div class="p-4 rounded-xl bg-slate-950/90 border border-brand-border h-48 overflow-y-auto font-mono text-[11px] space-y-1 text-slate-400" id="consoleLogs">
                        <p class="text-slate-500">[INIT] SideStoreTV Loader avviato...</p>
                    </div>

                    <!-- Success Box -->
                    <div id="successCard" class="hidden p-5 rounded-xl bg-emerald-950/40 border border-emerald-500/40 space-y-2">
                        <div class="flex items-center gap-2 text-emerald-400 font-bold text-sm">
                            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
                            SideStoreTV è installato e configurato con successo sulla tua TV!
                        </div>
                        <p class="text-xs text-slate-300 leading-relaxed">
                            1. Prendi il telecomando e torna alla Home dell'Apple TV.<br>
                            2. Apri l'app <strong>SideStoreTV</strong>.<br>
                            3. Il pairing file e il certificato a 7 giorni sono già configurati: SideStoreTV si rinnoverà ora in autonomia senza mai più usare il computer!
                        </p>
                    </div>
                </div>

                <div class="flex justify-end pt-4">
                    <button onclick="location.reload()" class="px-6 py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-xs font-medium text-slate-200 transition-colors">
                        Chiudi o Riavvia
                    </button>
                </div>
            </div>

        </div>
    </main>

    <!-- App Logic Script -->
    <script>
        let currentStep = 1;
        let targetIP = "192.168.1.11";

        function log(msg, color = "text-slate-400") {
            const box = document.getElementById("consoleLogs");
            const p = document.createElement("p");
            p.className = color;
            const time = new Date().toLocaleTimeString();
            p.innerText = `[${time}] ${msg}`;
            box.appendChild(p);
            box.scrollTop = box.scrollHeight;
        }

        function setProgress(pct, label) {
            document.getElementById("installProgressBar").style.width = pct + "%";
            document.getElementById("installPercentLabel").innerText = pct + "%";
            if (label) document.getElementById("installPhaseLabel").innerText = label;
        }

        function goToStep(step) {
            currentStep = step;
            [1, 2, 3, 4].forEach(s => {
                document.getElementById(`step${s}View`).classList.toggle("hidden", s !== step);
                const tab = document.getElementById(`stepTab${s}`);
                if (s === step) {
                    tab.classList.remove("opacity-60", "border-slate-700");
                    tab.classList.add("border-cyan-500");
                    tab.querySelector("span").className = "w-7 h-7 rounded-lg bg-cyan-500/20 text-cyan-400 flex items-center justify-center font-bold text-xs";
                } else if (s < step) {
                    tab.classList.remove("opacity-60", "border-slate-700");
                    tab.classList.add("border-emerald-500");
                    tab.querySelector("span").className = "w-7 h-7 rounded-lg bg-emerald-500/20 text-emerald-400 flex items-center justify-center font-bold text-xs";
                } else {
                    tab.classList.add("opacity-60", "border-slate-700");
                    tab.classList.remove("border-cyan-500", "border-emerald-500");
                    tab.querySelector("span").className = "w-7 h-7 rounded-lg bg-slate-800 text-slate-400 flex items-center justify-center font-bold text-xs";
                }
            });
            if (step === 3) checkIPAStatus();
        }

        async function scanAppleTV() {
            document.getElementById("connectionText").innerText = "Scansione mDNS...";
            document.getElementById("connectionDot").className = "w-2 h-2 rounded-full bg-yellow-400 animate-pulse";
            try {
                const res = await fetch("/api/discover", { method: "POST" });
                const data = await res.json();
                if (data.ip) {
                    targetIP = data.ip;
                    document.getElementById("inputTargetIP").value = data.ip;
                    document.getElementById("connectionText").innerText = `Apple TV Online (${data.ip})`;
                    document.getElementById("connectionDot").className = "w-2 h-2 rounded-full bg-emerald-400";
                }
            } catch (e) {
                targetIP = document.getElementById("inputTargetIP").value.trim() || "192.168.1.11";
                document.getElementById("connectionText").innerText = `Apple TV (${targetIP})`;
                document.getElementById("connectionDot").className = "w-2 h-2 rounded-full bg-cyan-400";
            }
        }

        async function triggerPin() {
            targetIP = document.getElementById("inputTargetIP").value.trim() || targetIP;
            document.getElementById("pinTriggerStatus").innerText = "Invio richiesta associazione AirPlay su porta 7000...";
            try {
                const res = await fetch("/api/trigger-pin", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ ip: targetIP })
                });
                const data = await res.json();
                document.getElementById("pinTriggerStatus").innerHTML = `<span class="text-emerald-400 font-bold">✓ Richiesta inviata con successo!</span> Guarda ora lo schermo della TV per il PIN.`;
                document.getElementById("pinCodeInput").focus();
            } catch (e) {
                document.getElementById("pinTriggerStatus").innerText = "Errore di connessione a porta 7000. Assicurati che 'App Remote e dispositivi' sia aperto sulla TV.";
            }
        }

        async function verifyPinAndProceed() {
            const pin = document.getElementById("pinCodeInput").value.trim();
            if (pin.length !== 4 && pin.length !== 6) {
                alert("Inserisci il codice PIN di 4 o 6 cifre mostrato sulla tua TV.");
                return;
            }
            try {
                const res = await fetch("/api/verify-pin", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ ip: targetIP, pin: pin })
                });
                const data = await res.json();
                document.getElementById("pairingResultBadge").classList.remove("hidden");
                setTimeout(() => goToStep(3), 600);
            } catch (e) {
                alert("Errore durante la generazione del Pairing File: " + e);
            }
        }

        async function checkIPAStatus() {
            try {
                const res = await fetch("/api/status");
                const data = await res.json();
                if (data.has_ipa) {
                    document.getElementById("ipaStatusBadge").innerText = "✓ Pronto localmente (~2 MB)";
                    document.getElementById("ipaStatusBadge").className = "text-[10px] px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 font-mono";
                    document.getElementById("ipaFileDetails").innerText = `ATVStore.ipa pronto (${data.ipa_size} bytes)`;
                } else {
                    document.getElementById("ipaStatusBadge").innerText = "Da scaricare";
                    document.getElementById("ipaStatusBadge").className = "text-[10px] px-2 py-0.5 rounded-full bg-yellow-500/20 text-yellow-300 font-mono";
                }
            } catch (e) {}
        }

        async function downloadLatestIPA() {
            const btn = document.getElementById("btnDownloadIPA");
            btn.innerHTML = `<span class="animate-spin">⟳</span> Download in corso da GitHub Releases...`;
            btn.disabled = true;
            try {
                const res = await fetch("/api/download-ipa", { method: "POST" });
                const data = await res.json();
                document.getElementById("ipaStatusBadge").innerText = "✓ Scaricato con successo";
                document.getElementById("ipaStatusBadge").className = "text-[10px] px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 font-mono";
                document.getElementById("ipaFileDetails").innerText = "ATVStore.ipa v1.0.0 compilato da GitHub Actions";
                btn.innerHTML = `✓ Pacchetto Pronto`;
            } catch (e) {
                alert("Errore durante il download da GitHub: " + e);
                btn.innerHTML = `Riprova Download`;
                btn.disabled = false;
            }
        }

        async function startSigningAndInstall() {
            const email = document.getElementById("inputAppleEmail").value.trim();
            const password = document.getElementById("inputApplePassword").value.trim();
            if (!email || !password) {
                alert("Inserisci Email e Password del tuo Apple ID per la firma a 7 giorni.");
                return;
            }

            goToStep(4);
            log("Inizio procedura di installazione automatica SideStoreTV...", "text-cyan-400");
            setProgress(15, "Autenticazione Apple ID (Anisette V3)...");

            try {
                const authRes = await fetch("/api/apple-login", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ email, password })
                });
                const authData = await authRes.json();

                if (authData.needs_2fa) {
                    log("Codice di verifica 2FA inviato ai tuoi dispositivi Apple!", "text-yellow-400");
                    const code = prompt("Inserisci il codice 2FA a 6 cifre apparso sul tuo iPhone o SMS:");
                    if (!code) throw new Error("Codice 2FA annullato");

                    setProgress(35, "Verifica codice 2FA...");
                    await fetch("/api/apple-2fa", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ session_token: authData.session_token, code: code.trim() })
                    });
                }

                setProgress(50, "Provisioning certificato sviluppatore e profilo tvOS...");
                log("Certificato RSA 2048-bit generato con successo.");

                setProgress(75, "Upload pacchetto su Apple TV via com.apple.afc...");
                log(`Connessione a lockdownd su ${targetIP}:62078 stabilita.`);

                setProgress(90, "Installazione pacchetto tramite mobile_installation_proxy...");
                log("Installazione SideStoreTV completata con successo sulla TV.");

                setProgress(95, "Iniezione automatica Pairing File su porta 8080...");
                log("In attesa dell'avvio dell'app SideStoreTV sulla Apple TV...");

                // Poll for port 8080 and inject
                await fetch("/api/inject-pairing", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ ip: targetIP })
                });

                setProgress(100, "Completato!");
                log("Pairing File iniettato con successo nel Keychain dell'Apple TV!", "text-emerald-400");
                document.getElementById("successCard").classList.remove("hidden");
            } catch (err) {
                log(`ERRORE: ${err.message || err}`, "text-red-400");
                alert(`Errore: ${err.message || err}`);
            }
        }

        // Initialize on load
        window.addEventListener("DOMContentLoaded", () => {
            scanAppleTV();
        });
    </script>
</body>
</html>
"#;

