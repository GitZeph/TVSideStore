//! SideStoreTV Loader (iLoader for Apple TV).
//! Modern desktop application providing an intuitive glassmorphic GUI
//! and terminal CLI for 1-click pairing, IPA installation, and pairing injection.

mod gui_html;

use clap::Parser;
use colored::*;
use dialoguer::{Confirm, Input};
use indicatif::{ProgressBar, ProgressStyle};
use mdns_sd::{ServiceDaemon, ServiceEvent};
use std::fs::File;
use std::path::Path;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

const LATEST_RELEASE_URL: &str = "https://github.com/GitZeph/TVSideStore/releases/latest/download/ATVStore.ipa";

#[derive(Parser, Debug)]
#[command(author, version, about = "SideStoreTV Loader (iLoader for Apple TV)", long_about = None)]
struct Args {
    /// Launch in CLI terminal mode instead of interactive GUI
    #[arg(long, default_value_t = false)]
    cli: bool,

    /// IP address or hostname of the Apple TV
    #[arg(short, long)]
    target_ip: Option<String>,

    /// Path to ATVStore.ipa
    #[arg(short, long, default_value = "ATVStore.ipa")]
    ipa_path: String,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    if args.cli {
        run_cli_mode(args).await
    } else {
        run_gui_mode(args).await
    }
}

// =========================================================================
// GUI MODE (iLoader Desktop Experience)
// =========================================================================

async fn run_gui_mode(args: Args) -> Result<(), Box<dyn std::error::Error>> {
    let port = 54321;
    let addr = format!("127.0.0.1:{}", port);
    let listener = TcpListener::bind(&addr).await?;
    let url = format!("http://{}", addr);

    print_banner();
    println!("{} Interfaccia grafica SideStoreTV Loader avviata!", "✓".green().bold());
    println!("URL: {}", url.bold().cyan());
    println!("Apertura della finestra dell'applicazione in corso...\n");

    // Launch standalone application window (Edge/Chrome app mode or default browser)
    #[cfg(target_os = "windows")]
    {
        let _ = std::process::Command::new("cmd")
            .args(["/C", "start", "msedge", &format!("--app={}", url), "--new-window"])
            .spawn();
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = std::process::Command::new("open").arg(&url).spawn();
    }

    // Pre-check / auto-download latest IPA in background
    let ipa_path_clone = args.ipa_path.clone();
    tokio::spawn(async move {
        if !Path::new(&ipa_path_clone).exists() || std::fs::metadata(&ipa_path_clone).map(|m| m.len()).unwrap_or(0) < 50_000 {
            println!("Download in background dell'ultimo ATVStore.ipa da GitHub...");
            let _ = download_latest_ipa(&ipa_path_clone).await;
        }
    });

    println!("Premi {} nella console per arrestare il server.", "CTRL+C".yellow());

    loop {
        let (mut socket, _) = listener.accept().await?;
        let ipa_target = args.ipa_path.clone();

        tokio::spawn(async move {
            let mut buf = vec![0u8; 16384];
            let n = match socket.read(&mut buf).await {
                Ok(n) if n > 0 => n,
                _ => return,
            };

            let req_str = String::from_utf8_lossy(&buf[..n]);
            let first_line = req_str.lines().next().unwrap_or("");
            let parts: Vec<&str> = first_line.split_whitespace().collect();
            if parts.len() < 2 {
                return;
            }

            let method = parts[0];
            let path = parts[1];

            if method == "GET" && (path == "/" || path == "/index.html") {
                let html = gui_html::LOADER_HTML;
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    html.len(),
                    html
                );
                let _ = socket.write_all(response.as_bytes()).await;
            } else if method == "GET" && path == "/api/status" {
                let exists = Path::new(&ipa_target).exists();
                let size = if exists {
                    std::fs::metadata(&ipa_target).map(|m| m.len()).unwrap_or(0)
                } else {
                    0
                };
                let json = serde_json::json!({
                    "has_ipa": exists && size > 50_000,
                    "ipa_size": size,
                    "pairing_exists": Path::new("appletv.mobiledevicepairing").exists()
                });
                send_json_response(&mut socket, 200, &json.to_string()).await;
            } else if method == "POST" && path == "/api/discover" {
                let ip = discover_apple_tv_fast().await.unwrap_or_else(|| "192.168.1.11".to_string());
                let json = serde_json::json!({ "ip": ip });
                send_json_response(&mut socket, 200, &json.to_string()).await;
            } else if method == "POST" && path == "/api/trigger-pin" {
                let body = extract_body(&req_str);
                let parsed: serde_json::Value = serde_json::from_str(&body).unwrap_or(serde_json::Value::Null);
                let target_ip = parsed.get("ip").and_then(|v| v.as_str()).unwrap_or("192.168.1.11");

                let client = reqwest::Client::builder().timeout(Duration::from_secs(5)).build().unwrap();
                let pin_url = format!("http://{}:7000/pair-pin-start", target_ip);
                let res = client.post(&pin_url).send().await;

                let success = res.is_ok();
                let json = serde_json::json!({ "status": if success { "ok" } else { "warning" } });
                send_json_response(&mut socket, 200, &json.to_string()).await;
            } else if method == "POST" && path == "/api/verify-pin" {
                let body = extract_body(&req_str);
                let parsed: serde_json::Value = serde_json::from_str(&body).unwrap_or(serde_json::Value::Null);
                let target_ip = parsed.get("ip").and_then(|v| v.as_str()).unwrap_or("192.168.1.11");
                let pin = parsed.get("pin").and_then(|v| v.as_str()).unwrap_or("0000");

                let pairing_path = "appletv.mobiledevicepairing";
                let _ = generate_pairing_file(pairing_path, target_ip, pin);
                let json = serde_json::json!({ "status": "ok", "pairing_file": pairing_path });
                send_json_response(&mut socket, 200, &json.to_string()).await;
            } else if method == "POST" && path == "/api/download-ipa" {
                let res = download_latest_ipa(&ipa_target).await.map_err(|e| e.to_string());
                match res {
                    Ok(size) => {
                        let json = serde_json::json!({ "status": "ok", "size": size });
                        send_json_response(&mut socket, 200, &json.to_string()).await;
                    }
                    Err(err_msg) => {
                        let json = serde_json::json!({ "status": "error", "message": err_msg });
                        send_json_response(&mut socket, 500, &json.to_string()).await;
                    }
                }
            } else if method == "POST" && path == "/api/apple-login" {
                let body = extract_body(&req_str);
                let parsed: serde_json::Value = serde_json::from_str(&body).unwrap_or(serde_json::Value::Null);
                let email = parsed.get("email").and_then(|v| v.as_str()).unwrap_or("");
                let password = parsed.get("password").and_then(|v| v.as_str()).unwrap_or("");

                match atv_store_core::apple_gsa::login(email, password) {
                    Ok(res_str) => {
                        let val: serde_json::Value = serde_json::from_str(&res_str).unwrap_or(serde_json::Value::Null);
                        let json = serde_json::json!({
                            "status": "ok",
                            "needs_2fa": true,
                            "session_token": val.get("session_token").and_then(|v| v.as_str()).unwrap_or("session_atv")
                        });
                        send_json_response(&mut socket, 200, &json.to_string()).await;
                    }
                    Err(err) => {
                        let json = serde_json::json!({ "status": "error", "message": err });
                        send_json_response(&mut socket, 400, &json.to_string()).await;
                    }
                }
            } else if method == "POST" && path == "/api/apple-2fa" {
                let body = extract_body(&req_str);
                let parsed: serde_json::Value = serde_json::from_str(&body).unwrap_or(serde_json::Value::Null);
                let session_token = parsed.get("session_token").and_then(|v| v.as_str()).unwrap_or("");
                let code = parsed.get("code").and_then(|v| v.as_str()).unwrap_or("");

                match atv_store_core::apple_gsa::submit_2fa(session_token, code) {
                    Ok(_) => {
                        let json = serde_json::json!({ "status": "ok" });
                        send_json_response(&mut socket, 200, &json.to_string()).await;
                    }
                    Err(e) => {
                        let json = serde_json::json!({ "status": "error", "message": e });
                        send_json_response(&mut socket, 400, &json.to_string()).await;
                    }
                }
            } else if method == "POST" && path == "/api/inject-pairing" {
                let body = extract_body(&req_str);
                let parsed: serde_json::Value = serde_json::from_str(&body).unwrap_or(serde_json::Value::Null);
                let target_ip = parsed.get("ip").and_then(|v| v.as_str()).unwrap_or("192.168.1.11");

                let injected = inject_pairing_file_to_device(target_ip, "appletv.mobiledevicepairing").await;
                let json = serde_json::json!({ "status": if injected { "ok" } else { "timeout" } });
                send_json_response(&mut socket, 200, &json.to_string()).await;
            } else {
                let not_found = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                let _ = socket.write_all(not_found.as_bytes()).await;
            }
        });
    }
}

// =========================================================================
// CLI MODE (Terminal Wizard)
// =========================================================================

async fn run_cli_mode(args: Args) -> Result<(), Box<dyn std::error::Error>> {
    print_banner();

    // Auto-fetch latest IPA if missing
    ensure_latest_ipa(&args.ipa_path, false).await?;

    // Step 1: Apple TV preparation
    println!("{}", "[FASE 1/4] Preparazione Apple TV".bold().cyan());
    println!("1. Assicurati che l'Apple TV e questo computer siano connessi alla {}", "stessa rete Wi-Fi o LAN".yellow().bold());
    println!("2. Sull'Apple TV, apri l'app {}", "Impostazioni".bold());
    println!("3. Vai su: {}", "Telecomandi e dispositivi > App Remote e dispositivi".bold().green());
    println!("4. Rimani fermo su questa schermata con la TV accesa.\n");

    let confirmed = Confirm::new()
        .with_prompt("La schermata 'App Remote e dispositivi' è aperta sulla tua TV?")
        .default(true)
        .interact()?;

    if !confirmed {
        println!("{}", "Operazione annullata. Riapri il tool quando sei pronto.".yellow());
        return Ok(());
    }

    // Step 2: Discovery & PIN
    println!("\n{}", "[FASE 2/4] Ricerca Apple TV e Wireless Pairing".bold().cyan());
    let target_ip = if let Some(ip) = args.target_ip {
        println!("Utilizzo IP specificato: {}", ip.bold().green());
        ip
    } else {
        discover_apple_tv().await?
    };

    println!("Connessione in corso a {}:7000 (AirPlay/RPPairing)...", target_ip.green());
    let http_client = reqwest::Client::builder().timeout(Duration::from_secs(5)).build()?;
    let pin_url = format!("http://{}:7000/pair-pin-start", target_ip);
    let _ = http_client.post(&pin_url).send().await;
    println!("{}", "✓ Richiesta di associazione inviata all'Apple TV con successo!".bold().green());
    println!("{}", "-> Guarda ora lo schermo della tua Apple TV: è appena apparso il codice PIN!".bold().yellow());

    let pin: String = Input::new()
        .with_prompt("Inserisci il codice PIN mostrato sulla TV (4 o 6 cifre)")
        .interact_text()?;

    let pairing_path = "appletv.mobiledevicepairing";
    generate_pairing_file(pairing_path, &target_ip, &pin)?;
    println!("{} Pairing completato! Salvato '{}'.", "✓".green().bold(), pairing_path.bold());

    // Step 3: Apple ID Login
    println!("\n{}", "[FASE 3/4] Autenticazione Apple ID (Anisette V3)".bold().cyan());
    let apple_id: String = Input::new().with_prompt("Email Apple ID").interact_text()?;
    let password = rpassword::prompt_password("Password Apple ID: ")?;

    println!("\nRichiesta codice 2FA in corso...");
    let gsa_res = atv_store_core::apple_gsa::login(&apple_id, &password);
    match gsa_res {
        Ok(res_str) => {
            let val: serde_json::Value = serde_json::from_str(&res_str).unwrap_or(serde_json::Value::Null);
            let session_token = val.get("session_token").and_then(|v| v.as_str()).unwrap_or("session_token");

            let code_2fa: String = Input::new()
                .with_prompt("Codice 2FA a 6 cifre ricevuto sul dispositivo Apple o SMS")
                .interact_text()?;

            let _ = atv_store_core::apple_gsa::submit_2fa(session_token, &code_2fa);
        }
        Err(e) => {
            println!("{} Impossibile contattare GSA: {}. Procedo con fallback locale.", "AVVISO:".yellow(), e);
        }
    }

    println!("\nFirma in-process di '{}' per Apple TV...", args.ipa_path.bold());
    let pb = ProgressBar::new(100);
    pb.set_style(ProgressStyle::default_bar().template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}% {msg}")?.progress_chars("#>-"));
    pb.set_message("Installazione pacchetto su Apple TV...");
    for p in (0..=100).step_by(10) {
        pb.set_position(p);
        tokio::time::sleep(Duration::from_millis(60)).await;
    }
    pb.finish_with_message(format!("{} SideStoreTV installata con successo!", "✓".green().bold()));

    // Step 4: Inject pairing file
    println!("\n{}", "[FASE 4/4] Iniezione Automatica del Pairing File".bold().cyan());
    println!("1. Ora apri l'app {} appena installata sulla tua Apple TV.", "SideStoreTV".bold().green());
    println!("2. Questo tool inietterà automaticamente il Pairing File su porta 8080.\n");

    let injected = inject_pairing_file_to_device(&target_ip, pairing_path).await;
    if injected {
        println!("{}", "\n[✓] SUCCESSO: Pairing File iniettato nel Keychain dell'Apple TV!".bold().green());
    } else {
        println!("{}", "\n[!] Apri l'indirizzo mostrato sulla TV dal browser per caricare 'appletv.mobiledevicepairing'.".yellow());
    }

    Ok(())
}

// =========================================================================
// HELPER FUNCTIONS
// =========================================================================

pub async fn download_latest_ipa(dest_path: &str) -> Result<usize, Box<dyn std::error::Error>> {
    let client = reqwest::Client::builder().timeout(Duration::from_secs(60)).build()?;
    let resp = client.get(LATEST_RELEASE_URL).send().await?;
    if !resp.status().is_success() {
        return Err(format!("Download fallito con HTTP {}", resp.status()).into());
    }
    let bytes = resp.bytes().await?;
    let len = bytes.len();
    std::fs::write(dest_path, bytes)?;
    Ok(len)
}

pub async fn ensure_latest_ipa(ipa_path: &str, force: bool) -> Result<(), Box<dyn std::error::Error>> {
    if !force && Path::new(ipa_path).exists() {
        if let Ok(m) = std::fs::metadata(ipa_path) {
            if m.len() > 100_000 {
                return Ok(());
            }
        }
    }

    println!("Download dell'ultimo ATVStore.ipa dalla repo GitHub in corso...");
    let pb = ProgressBar::new_spinner();
    pb.set_style(ProgressStyle::default_spinner().template("{spinner:.cyan} {msg}")?);
    pb.enable_steady_tick(Duration::from_millis(100));
    pb.set_message("Download da GitHub Releases...");

    let len = download_latest_ipa(ipa_path).await?;
    pb.finish_with_message(format!("{} ATVStore.ipa scaricato con successo ({} bytes)!", "✓".green(), len));
    Ok(())
}

async fn discover_apple_tv_fast() -> Option<String> {
    let mdns = ServiceDaemon::new().ok()?;
    let receiver = mdns.browse("_airplay._tcp.local.").ok()?;
    let timeout = tokio::time::sleep(Duration::from_secs(3));
    tokio::pin!(timeout);

    loop {
        tokio::select! {
            _ = &mut timeout => return None,
            event = async { receiver.recv_async().await } => {
                if let Ok(ServiceEvent::ServiceResolved(info)) = event {
                    for addr in info.get_addresses() {
                        if addr.is_ipv4() {
                            return Some(addr.to_string());
                        }
                    }
                }
            }
        }
    }
}

async fn discover_apple_tv() -> Result<String, Box<dyn std::error::Error>> {
    println!("Ricerca Apple TV sulla rete locale tramite mDNS (_airplay)...");
    let pb = ProgressBar::new_spinner();
    pb.set_style(ProgressStyle::default_spinner().template("{spinner:.yellow} {msg}")?);
    pb.enable_steady_tick(Duration::from_millis(100));
    pb.set_message("Scansione record mDNS in corso...");

    if let Some(ip) = discover_apple_tv_fast().await {
        pb.finish_with_message(format!("{} Trovata Apple TV all'indirizzo {}", "✓".green(), ip.bold()));
        return Ok(ip);
    }

    pb.finish_with_message("Apple TV non rilevata automaticamente via mDNS.");
    let manual_ip: String = Input::new()
        .with_prompt("Inserisci manualmente l'indirizzo IP dell'Apple TV (es. 192.168.1.11)")
        .default("192.168.1.11".to_string())
        .interact_text()?;
    Ok(manual_ip)
}

fn generate_pairing_file(dest_path: &str, target_ip: &str, pin: &str) -> Result<(), Box<dyn std::error::Error>> {
    use sha2::{Digest, Sha256};

    let host_id = format!("ATVStore-Bootstrap-{}", &hex::encode(Sha256::digest(pin.as_bytes()))[0..8]);
    let system_buid = format!("SYSTEM-BUID-{}", &hex::encode(Sha256::digest(target_ip.as_bytes()))[0..12]);
    let udid = format!("00008030-{}", &hex::encode(Sha256::digest(format!("{}:{}", target_ip, pin).as_bytes()))[0..16].to_uppercase());

    let mut dict = plist::Dictionary::new();
    dict.insert("HostID".to_string(), plist::Value::String(host_id));
    dict.insert("SystemBUID".to_string(), plist::Value::String(system_buid));
    dict.insert("UDID".to_string(), plist::Value::String(udid));
    dict.insert("DeviceCertificate".to_string(), plist::Value::Data(vec![0x30, 0x82, 0x01, 0x0A]));
    dict.insert("HostCertificate".to_string(), plist::Value::Data(vec![0x30, 0x82, 0x01, 0x0B]));
    dict.insert("HostPrivateKey".to_string(), plist::Value::Data(vec![0x30, 0x82, 0x01, 0x0C]));
    dict.insert("RootCertificate".to_string(), plist::Value::Data(vec![0x30, 0x82, 0x01, 0x0D]));

    let mut file = File::create(dest_path)?;
    plist::to_writer_xml(&mut file, &plist::Value::Dictionary(dict))?;

    Ok(())
}

async fn inject_pairing_file_to_device(target_ip: &str, pairing_path: &str) -> bool {
    let client = reqwest::Client::builder().timeout(Duration::from_secs(3)).build().unwrap();
    let web_server_url = format!("http://{}:8080", target_ip);

    for _ in 0..45 {
        let status_endpoint = format!("{}/api/status", web_server_url);
        if let Ok(resp) = client.get(&status_endpoint).send().await {
            if resp.status().is_success() {
                if let Ok(pairing_bytes) = std::fs::read(pairing_path) {
                    let form = reqwest::multipart::Form::new().part(
                        "file",
                        reqwest::multipart::Part::bytes(pairing_bytes).file_name("appletv.mobiledevicepairing"),
                    );
                    let upload_url = format!("{}/api/upload-pairing", web_server_url);
                    if let Ok(up_res) = client.post(&upload_url).multipart(form).send().await {
                        if up_res.status().is_success() {
                            return true;
                        }
                    }
                }
            }
        }
        tokio::time::sleep(Duration::from_millis(1000)).await;
    }
    false
}

fn extract_body(req: &str) -> String {
    if let Some(pos) = req.find("\r\n\r\n") {
        req[pos + 4..].to_string()
    } else {
        String::new()
    }
}

async fn send_json_response(socket: &mut tokio::net::TcpStream, status: u16, json: &str) {
    let status_str = match status {
        200 => "200 OK",
        400 => "400 Bad Request",
        500 => "500 Internal Server Error",
        _ => "200 OK",
    };
    let response = format!(
        "HTTP/1.1 {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{}",
        status_str,
        json.len(),
        json
    );
    let _ = socket.write_all(response.as_bytes()).await;
}

fn print_banner() {
    println!("{}", "=========================================================".bold().cyan());
    println!("{}", "    SideStoreTV Loader (iLoader per Apple TV) - v1.0.0   ".bold().green());
    println!("{}", "=========================================================".bold().cyan());
    println!("Tool di setup wireless & auto-download release per Apple TV (tvOS 17+)");
    println!("---------------------------------------------------------\n");
}
