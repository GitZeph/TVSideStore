import Foundation

/// Embedded modern dark-mode Web Portal HTML/CSS/JS served on port 8080.
/// Allows phone and desktop browsers to manage Pairing Files, Apple ID login & 2FA, IPA uploads, and sources.
public enum WebPortalHTML {
    public static let fullHTML = """
<!DOCTYPE html>
<html lang="it" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SideStoreTV - Web Control Center</title>
    <style>
        :root {
            --bg-primary: #0f172a;
            --bg-card: #1e293b;
            --bg-card-hover: #334155;
            --accent: #38bdf8;
            --accent-hover: #0284c7;
            --text-primary: #f8fafc;
            --text-secondary: #94a3b8;
            --success: #10b981;
            --warning: #f59e0b;
            --danger: #ef4444;
            --border: #334155;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
        body { background: var(--bg-primary); color: var(--text-primary); min-height: 100vh; display: flex; flex-direction: column; }
        header { background: #0b1120; border-bottom: 1px solid var(--border); padding: 1rem 1.5rem; display: flex; align-items: center; justify-content: space-between; }
        .logo { display: flex; align-items: center; gap: 0.75rem; font-size: 1.25rem; font-weight: 700; color: var(--accent); }
        .nav-tabs { display: flex; gap: 0.5rem; background: var(--bg-card); padding: 0.25rem; border-radius: 0.75rem; margin: 1.5rem auto; max-width: 720px; width: 92%; }
        .tab-btn { flex: 1; padding: 0.6rem 0.5rem; border: none; background: transparent; color: var(--text-secondary); font-weight: 600; font-size: 0.85rem; border-radius: 0.5rem; cursor: pointer; transition: all 0.2s; text-align: center; }
        .tab-btn.active { background: var(--accent); color: #000; }
        .container { max-width: 720px; width: 92%; margin: 0 auto 3rem auto; flex: 1; }
        .panel { display: none; background: var(--bg-card); border: 1px solid var(--border); border-radius: 1rem; padding: 1.5rem; }
        .panel.active { display: block; animation: fadeIn 0.2s ease-in; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }
        h2 { font-size: 1.3rem; margin-bottom: 0.5rem; color: var(--text-primary); }
        p.desc { font-size: 0.875rem; color: var(--text-secondary); margin-bottom: 1.25rem; line-height: 1.4; }
        .dropzone { border: 2px dashed var(--border); border-radius: 0.75rem; padding: 2rem 1rem; text-align: center; cursor: pointer; transition: all 0.2s; margin-bottom: 1.25rem; }
        .dropzone:hover, .dropzone.dragover { border-color: var(--accent); background: rgba(56, 189, 248, 0.05); }
        .dropzone svg { width: 42px; height: 42px; fill: var(--text-secondary); margin-bottom: 0.5rem; }
        .input-group { margin-bottom: 1rem; text-align: left; }
        label { display: block; font-size: 0.8rem; font-weight: 600; color: var(--text-secondary); margin-bottom: 0.35rem; }
        input[type="text"], input[type="password"], input[type="url"] { width: 100%; padding: 0.75rem; background: #0f172a; border: 1px solid var(--border); border-radius: 0.5rem; color: #fff; font-size: 0.95rem; }
        input:focus { outline: none; border-color: var(--accent); }
        .btn { display: block; width: 100%; padding: 0.75rem; background: var(--accent); color: #000; font-weight: 700; border: none; border-radius: 0.5rem; cursor: pointer; transition: background 0.2s; font-size: 0.95rem; }
        .btn:hover { background: var(--accent-hover); }
        .btn:disabled { opacity: 0.5; cursor: not-allowed; }
        .status-badge { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.25rem 0.6rem; border-radius: 1rem; font-size: 0.75rem; font-weight: 700; }
        .badge-green { background: rgba(16, 185, 129, 0.2); color: var(--success); }
        .badge-red { background: rgba(239, 68, 68, 0.2); color: var(--danger); }
        .badge-yellow { background: rgba(245, 158, 11, 0.2); color: var(--warning); }
        .status-row { display: flex; justify-content: space-between; align-items: center; padding: 0.75rem 0; border-bottom: 1px solid var(--border); font-size: 0.9rem; }
        .progress-box { margin-top: 1rem; display: none; }
        .progress-bar-bg { background: #0f172a; height: 10px; border-radius: 5px; overflow: hidden; margin-top: 0.3rem; }
        .progress-bar-fill { background: var(--accent); height: 100%; width: 0%; transition: width 0.2s; }
        .toast { position: fixed; bottom: 20px; right: 20px; max-width: 340px; padding: 1rem; border-radius: 0.75rem; background: #1e293b; border: 1px solid var(--border); box-shadow: 0 10px 25px rgba(0,0,0,0.5); display: none; z-index: 100; font-size: 0.85rem; }
    </style>
</head>
<body>
    <header>
        <div class="logo">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect width="20" height="15" x="2" y="7" rx="2" ry="2"/><polyline points="17 2 12 7 7 2"/></svg>
            SideStoreTV
        </div>
        <div id="topStatus"><span class="status-badge badge-green">Connesso</span></div>
    </header>

    <div class="nav-tabs">
        <button class="tab-btn active" onclick="switchTab('pairing')">📶 Pairing</button>
        <button class="tab-btn" onclick="switchTab('auth')">🍎 Apple ID</button>
        <button class="tab-btn" onclick="switchTab('upload')">🚀 Upload IPA</button>
        <button class="tab-btn" onclick="switchTab('sources')">🌐 Sorgenti</button>
    </div>

    <div class="container">
        <!-- TAB 1: PAIRING FILE -->
        <div id="tab-pairing" class="panel active">
            <h2>Stato & File di Pairing</h2>
            <p class="desc">Carica il file <code>.mobiledevicepairing</code> o <code>.plist</code> generato dal tool di bootstrap o scaricato da Mac/PC. Viene salvato istantaneamente nel Keychain dell'Apple TV.</p>

            <div class="status-row">
                <span>Stato Pairing File</span>
                <span id="pairingStatusBadge" class="status-badge badge-yellow">Verifica in corso...</span>
            </div>
            <div class="status-row">
                <span>Tunnel LocalDevVPN (utun)</span>
                <span id="tunnelStatusBadge" class="status-badge badge-yellow">Verifica in corso...</span>
            </div>
            <div class="status-row">
                <span>Porta Lockdown (62078)</span>
                <span id="lockdownStatusBadge" class="status-badge badge-yellow">Verifica in corso...</span>
            </div>

            <div class="dropzone" id="pairingDropzone" onclick="document.getElementById('pairingInput').click()">
                <svg viewBox="0 0 24 24"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM14 13v4h-4v-4H7l5-5 5 5h-3z"/></svg>
                <div style="font-weight:600; margin-bottom:0.25rem;">Trascina qui il file di Pairing</div>
                <div style="font-size:0.75rem; color:var(--text-secondary);">oppure tocca per selezionare (.mobiledevicepairing o .plist)</div>
                <input type="file" id="pairingInput" accept=".mobiledevicepairing,.plist" style="display:none" onchange="handlePairingFile(this.files[0])">
            </div>
        </div>

        <!-- TAB 2: APPLE ID & 2FA -->
        <div id="tab-auth" class="panel">
            <h2>Apple ID & Autenticazione 2FA</h2>
            <p class="desc">Inserisci le credenziali del tuo Apple ID gratuito comodamente dalla tastiera del telefono o PC, inclusa la verifica a due fattori.</p>

            <div id="loginSection">
                <div class="input-group">
                    <label>Email Apple ID</label>
                    <input type="text" id="appleIdInput" placeholder="nome@icloud.com">
                </div>
                <div class="input-group">
                    <label>Password Apple ID (o Password per app)</label>
                    <input type="password" id="applePassInput" placeholder="••••••••••••">
                </div>
                <button class="btn" id="loginBtn" onclick="submitLogin()">Accedi con Apple ID</button>
            </div>

            <div id="twoFactorSection" style="display:none; margin-top:1.5rem; padding-top:1.5rem; border-top:1px solid var(--border);">
                <h3 style="margin-bottom:0.5rem; color:var(--accent);">Codice di Verifica a Due Fattori</h3>
                <p class="desc">Inserisci il codice a 6 cifre comparso sui tuoi dispositivi Apple o via SMS.</p>
                <div class="input-group">
                    <input type="text" id="twoFactorCode" maxlength="6" placeholder="123456" style="font-size:1.5rem; letter-spacing:0.4rem; text-align:center;">
                </div>
                <button class="btn" onclick="submit2FA()">Conferma Codice 2FA</button>
            </div>
        </div>

        <!-- TAB 3: UPLOAD IPA -->
        <div id="tab-upload" class="panel">
            <h2>Carica & Installa IPA</h2>
            <p class="desc">Trascina un file <code>.ipa</code> per Apple TV. SideStoreTV lo firmerà in-process e lo installerà via local tunnel.</p>

            <div class="dropzone" id="ipaDropzone" onclick="document.getElementById('ipaInput').click()">
                <svg viewBox="0 0 24 24"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>
                <div style="font-weight:600; margin-bottom:0.25rem;">Trascina qui il file .ipa</div>
                <div style="font-size:0.75rem; color:var(--text-secondary);">Tocca per selezionare dal dispositivo</div>
                <input type="file" id="ipaInput" accept=".ipa" style="display:none" onchange="uploadIPA(this.files[0])">
            </div>

            <div class="input-group">
                <label>URL Origine Permanente (Opzionale: per refresh automatico se la cache viene svuotata)</label>
                <input type="url" id="sourceUrlInput" placeholder="https://example.com/app.ipa">
            </div>

            <div class="progress-box" id="uploadProgressBox">
                <div style="display:flex; justify-content:space-between; font-size:0.8rem;">
                    <span id="progressStage">Caricamento in corso...</span>
                    <span id="progressPercent">0%</span>
                </div>
                <div class="progress-bar-bg">
                    <div class="progress-bar-fill" id="progressBarFill"></div>
                </div>
            </div>
        </div>

        <!-- TAB 4: SORGENTI REPOSITORY -->
        <div id="tab-sources" class="panel">
            <h2>Sorgenti Applicazioni (AltSource)</h2>
            <p class="desc">Aggiungi repository di community incollando l'URL JSON compatibile con AltStore o SideStore.</p>

            <div class="input-group">
                <label>URL Repository (JSON)</label>
                <input type="url" id="repoUrlInput" placeholder="https://apps.sidestore.io">
            </div>
            <button class="btn" onclick="addSource()">Aggiungi Sorgente</button>
        </div>
    </div>

    <div class="toast" id="toast"></div>

    <script>
        let currentSessionToken = "";

        function switchTab(tabId) {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
            event.target.classList.add('active');
            document.getElementById('tab-' + tabId).classList.add('active');
        }

        function showToast(msg, isSuccess = true) {
            const t = document.getElementById('toast');
            t.innerText = msg;
            t.style.display = 'block';
            t.style.borderColor = isSuccess ? 'var(--success)' : 'var(--danger)';
            setTimeout(() => { t.style.display = 'none'; }, 4000);
        }

        async function fetchStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                
                const pBadge = document.getElementById('pairingStatusBadge');
                if (data.has_pairing) {
                    pBadge.className = 'status-badge badge-green';
                    pBadge.innerText = 'Configurato';
                } else {
                    pBadge.className = 'status-badge badge-red';
                    pBadge.innerText = 'Assente (Richiesto)';
                }

                const tBadge = document.getElementById('tunnelStatusBadge');
                if (data.tunnel_active) {
                    tBadge.className = 'status-badge badge-green';
                    tBadge.innerText = 'Attivo (' + (data.tunnel_ip || '10.7.0.1') + ')';
                } else {
                    tBadge.className = 'status-badge badge-red';
                    tBadge.innerText = 'Inattivo (Apri LocalDevVPN)';
                }

                const lBadge = document.getElementById('lockdownStatusBadge');
                if (data.lockdown_reachable) {
                    lBadge.className = 'status-badge badge-green';
                    lBadge.innerText = 'Raggiungibile';
                } else {
                    lBadge.className = 'status-badge badge-yellow';
                    lBadge.innerText = 'In attesa...';
                }
            } catch (e) {}
        }
        setInterval(fetchStatus, 3000);
        fetchStatus();

        async function handlePairingFile(file) {
            if (!file) return;
            showToast('Invio pairing file all\\'Apple TV...');
            const formData = new FormData();
            formData.append('file', file);

            try {
                const res = await fetch('/api/upload-pairing', { method: 'POST', body: formData });
                const json = await res.json();
                if (json.status === 'SUCCESS') {
                    showToast('Pairing File salvato con successo nel Keychain!');
                    fetchStatus();
                } else {
                    showToast(json.message || 'Errore salvataggio pairing file', false);
                }
            } catch (e) {
                showToast('Errore di connessione: ' + e, false);
            }
        }

        async function submitLogin() {
            const apple_id = document.getElementById('appleIdInput').value.trim();
            const password = document.getElementById('applePassInput').value;
            if (!apple_id || !password) {
                showToast('Inserisci email e password', false);
                return;
            }
            const btn = document.getElementById('loginBtn');
            btn.disabled = true;
            btn.innerText = 'Autenticazione in corso...';

            try {
                const res = await fetch('/api/auth-login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ apple_id, password })
                });
                const data = await res.json();
                btn.disabled = false;
                btn.innerText = 'Accedi con Apple ID';

                if (data.status === '2FA_REQUIRED') {
                    currentSessionToken = data.session_token;
                    document.getElementById('twoFactorSection').style.display = 'block';
                    showToast('Codice 2FA richiesto. Controlla il tuo dispositivo.');
                } else if (data.status === 'SUCCESS') {
                    showToast('Accesso effettuato con successo!');
                } else {
                    showToast(data.message || 'Errore di login', false);
                }
            } catch (e) {
                btn.disabled = false;
                btn.innerText = 'Accedi con Apple ID';
                showToast('Errore di rete durante il login', false);
            }
        }

        async function submit2FA() {
            const code = document.getElementById('twoFactorCode').value.trim();
            if (code.length !== 6) {
                showToast('Il codice 2FA deve essere di 6 cifre', false);
                return;
            }

            try {
                const res = await fetch('/api/auth-2fa', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ session_token: currentSessionToken, code: code })
                });
                const data = await res.json();
                if (data.status === 'SUCCESS') {
                    showToast('Verifica 2FA completata! Sessione salvata nel Keychain.');
                    document.getElementById('twoFactorSection').style.display = 'none';
                } else {
                    showToast(data.message || 'Codice 2FA non valido', false);
                }
            } catch (e) {
                showToast('Errore durante la verifica 2FA', false);
            }
        }

        function uploadIPA(file) {
            if (!file) return;
            const sourceUrl = document.getElementById('sourceUrlInput').value.trim();
            const progressBox = document.getElementById('uploadProgressBox');
            const fill = document.getElementById('progressBarFill');
            const percentText = document.getElementById('progressPercent');
            const stageText = document.getElementById('progressStage');

            progressBox.style.display = 'block';
            stageText.innerText = 'Caricamento IPA verso Apple TV...';

            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/api/upload-ipa', true);
            if (sourceUrl) xhr.setRequestHeader('X-Source-URL', sourceUrl);
            xhr.setRequestHeader('X-File-Name', encodeURIComponent(file.name));

            xhr.upload.onprogress = function(e) {
                if (e.lengthComputable) {
                    const percent = Math.round((e.loaded / e.total) * 100);
                    fill.style.width = percent + '%';
                    percentText.innerText = percent + '%';
                    if (percent === 100) {
                        stageText.innerText = 'Firma in-process e installazione via lockdown...';
                    }
                }
            };

            xhr.onload = function() {
                if (xhr.status === 200) {
                    showToast('App caricata e installata con successo!');
                    stageText.innerText = 'Installazione completata!';
                } else {
                    showToast('Errore durante l\\'installazione dell\\'IPA', false);
                }
            };

            xhr.onerror = function() {
                showToast('Errore di connessione durante l\\'upload', false);
            };

            const formData = new FormData();
            formData.append('file', file);
            xhr.send(formData);
        }

        async function addSource() {
            const url = document.getElementById('repoUrlInput').value.trim();
            if (!url) return;
            try {
                const res = await fetch('/api/add-source', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ url })
                });
                const data = await res.json();
                if (data.status === 'SUCCESS') {
                    showToast('Sorgente aggiunta con successo!');
                    document.getElementById('repoUrlInput').value = '';
                } else {
                    showToast(data.message || 'Impossibile aggiungere sorgente', false);
                }
            } catch (e) {
                showToast('Errore durante l\\'aggiunta della sorgente', false);
            }
        }
    </script>
</body>
</html>
"""
}

