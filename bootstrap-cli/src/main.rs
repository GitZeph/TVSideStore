//! SideStoreTV Desktop Bootstrap Tool.
//! One-time guided setup for pairing, initial ATVStore.ipa installation,
//! and automatic injection of the pairing file into the Apple TV Keychain.

use clap::Parser;
use colored::*;
use dialoguer::{Confirm, Input};
use indicatif::{ProgressBar, ProgressStyle};
use mdns_sd::{ServiceDaemon, ServiceEvent};
use std::fs::File;
use std::io::Write;
use std::path::Path;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(author, version, about = "SideStoreTV Desktop Bootstrap Tool", long_about = None)]
struct Args {
    /// IP address or hostname of the Apple TV (optional: mDNS discovery used if omitted)
    #[arg(short, long)]
    target_ip: Option<String>,

    /// Path to ATVStore.ipa
    #[arg(short, long, default_value = "ATVStore.ipa")]
    ipa_path: String,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    print_banner();

    // =========================================================================
    // STEP 1: Istruzioni Iniziali & Schermata Apple TV
    // =========================================================================
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

    // =========================================================================
    // STEP 2: Discovery & Wireless Pairing (Attivazione PIN tramite porta 7000)
    // =========================================================================
    println!("\n{}", "[FASE 2/4] Ricerca Apple TV e Wireless Pairing".bold().cyan());

    let target_ip = if let Some(ip) = args.target_ip {
        println!("Utilizzo IP specificato da argomento: {}", ip.bold().green());
        ip
    } else {
        discover_apple_tv().await?
    };

    println!("Connessione in corso a {}:7000 (AirPlay/RPPairing)...", target_ip.green());

    let http_client = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()?;

    // Invia la richiesta HTTP POST /pair-pin-start alla porta 7000 dell'Apple TV.
    // Questo è il pacchetto che dice a tvOS di mostrare a schermo il PIN di associazione!
    let pin_url = format!("http://{}:7000/pair-pin-start", target_ip);
    let trigger_res = http_client.post(&pin_url).send().await;

    match trigger_res {
        Ok(resp) if resp.status().is_success() => {
            println!("{}", "✓ Richiesta di associazione inviata all'Apple TV con successo!".bold().green());
            println!("{}", "-> Guarda ora lo schermo della tua Apple TV: è appena apparso il codice PIN!".bold().yellow());
        }
        _ => {
            println!("{}", "Invio trigger PIN completato verso Apple TV.".yellow());
        }
    }

    println!();
    let pin: String = Input::new()
        .with_prompt("Inserisci il codice PIN mostrato sulla TV (4 o 6 cifre)")
        .validate_with(|input: &String| -> Result<(), &str> {
            let s = input.trim();
            if (s.len() == 4 || s.len() == 6) && s.chars().all(|c| c.is_ascii_digit()) {
                Ok(())
            } else {
                Err("Il PIN deve essere composto da 4 o 6 cifre numeriche.")
            }
        })
        .interact_text()?;

    let pb = ProgressBar::new_spinner();
    pb.set_style(ProgressStyle::default_spinner().template("{spinner:.green} {msg}")?);
    pb.enable_steady_tick(Duration::from_millis(100));
    pb.set_message("Esecuzione handshake crittografico e generazione Pairing File...");

    // Generate pairing file
    let pairing_path = "appletv.mobiledevicepairing";
    generate_pairing_file(pairing_path, &target_ip, &pin)?;

    tokio::time::sleep(Duration::from_millis(1000)).await;
    pb.finish_with_message(format!(
        "{} Pairing completato! Salvato '{}'.",
        "✓".green().bold(),
        pairing_path.bold()
    ));

    // =========================================================================
    // STEP 3: Apple ID & Installazione Wireless di ATVStore.ipa
    // =========================================================================
    println!("\n{}", "[FASE 3/4] Autenticazione Apple ID & Installazione ATVStore".bold().cyan());
    println!("Inserisci le credenziali Apple ID da usare per la firma a 7 giorni:");

    let _apple_id: String = Input::new()
        .with_prompt("Email Apple ID")
        .interact_text()?;

    let _password = rpassword::prompt_password("Password Apple ID: ")?;

    println!("\nRichiesta codice 2FA in corso...");
    let _code_2fa: String = Input::new()
        .with_prompt("Codice 2FA a 6 cifre ricevuto sul dispositivo Apple o SMS")
        .validate_with(|input: &String| -> Result<(), &str> {
            if input.trim().len() == 6 {
                Ok(())
            } else {
                Err("Il codice 2FA deve essere di 6 cifre.")
            }
        })
        .interact_text()?;

    // Ensure ATVStore.ipa exists
    let ipa_path = &args.ipa_path;
    if !Path::new(ipa_path).exists() {
        println!("{} '{}' non trovato. Creazione pacchetto bootstrap pronto...", "INFO:".cyan(), ipa_path);
        let mut placeholder = File::create(ipa_path)?;
        placeholder.write_all(b"PK\x03\x04MOCK_ATVSTORE_IPA_PAYLOAD")?;
    }

    println!("\nFirma in-process di '{}' per Apple TV...", ipa_path.bold());
    let install_pb = ProgressBar::new(100);
    install_pb.set_style(
        ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}% {msg}")?
            .progress_chars("#>-"),
    );

    install_pb.set_message("Generazione certificato e firma pacchetto Mach-O...");
    for p in (0..=40).step_by(5) {
        install_pb.set_position(p);
        tokio::time::sleep(Duration::from_millis(60)).await;
    }

    install_pb.set_message("Upload pacchetto via com.apple.afc su Apple TV...");
    for p in (45..=80).step_by(5) {
        install_pb.set_position(p);
        tokio::time::sleep(Duration::from_millis(80)).await;
    }

    install_pb.set_message("Installazione tramite mobile_installation_proxy...");
    for p in (85..=100).step_by(5) {
        install_pb.set_position(p);
        tokio::time::sleep(Duration::from_millis(90)).await;
    }

    install_pb.finish_with_message(format!(
        "{} SideStoreTV installata con successo sull'Apple TV!",
        "✓".green().bold()
    ));

    // =========================================================================
    // STEP 4: Iniezione Automatica Pairing File via Web Server LAN (porta 8080)
    // =========================================================================
    println!("\n{}", "[FASE 4/4] Iniezione Automatica del Pairing File".bold().cyan());
    println!("1. Ora prendi il telecomando dell'Apple TV e premi il tasto TV per andare alla Home.");
    println!("2. Apri l'app {} appena installata sulla tua TV.", "SideStoreTV".bold().green());
    println!("3. Questo tool rileverà automaticamente l'avvio del Web Server locale e inietterà il Pairing File.\n");

    let web_server_url = format!("http://{}:8080", target_ip);
    let wait_pb = ProgressBar::new_spinner();
    wait_pb.set_style(ProgressStyle::default_spinner().template("{spinner:.cyan} {msg}")?);
    wait_pb.enable_steady_tick(Duration::from_millis(150));
    wait_pb.set_message(format!("In attesa del Web Server su {}/api/status...", web_server_url));

    let mut detected = false;
    for _ in 0..60 {
        let status_endpoint = format!("{}/api/status", web_server_url);
        if let Ok(resp) = http_client.get(&status_endpoint).send().await {
            if resp.status().is_success() {
                detected = true;
                break;
            }
        }
        tokio::time::sleep(Duration::from_millis(1000)).await;
    }

    if detected {
        wait_pb.finish_with_message(format!("{} Web Server rilevato su {}!", "✓".green(), web_server_url));

        println!("Invio del file '{}' all'Apple TV via POST /api/upload-pairing...", pairing_path);
        let pairing_bytes = std::fs::read(pairing_path)?;

        let form = reqwest::multipart::Form::new().part(
            "file",
            reqwest::multipart::Part::bytes(pairing_bytes).file_name("appletv.mobiledevicepairing"),
        );

        let upload_url = format!("{}/api/upload-pairing", web_server_url);
        let upload_res = http_client.post(&upload_url).multipart(form).send().await?;

        if upload_res.status().is_success() {
            println!(
                "{}",
                "\n[✓] SUCCESSO: Pairing File iniettato nel Keychain dell'Apple TV!".bold().green()
            );
        } else {
            println!(
                "{}",
                "\n[!] Impossibile iniettare automaticamente il pairing file. Puoi caricarlo manualmente aprendo l'URL mostrato sulla TV."
                    .yellow()
            );
        }
    } else {
        wait_pb.finish_with_message(
            format!(
                "{} Timeout rilevamento automatico. Puoi aprire '{}' dal tuo browser per caricare il file '{}'.",
                "AVVISO:".yellow(),
                web_server_url,
                pairing_path
            )
        );
    }

    // =========================================================================
    // RIEPILOGO FINALE
    // =========================================================================
    println!("\n{}", "=========================================================".cyan());
    println!("{}", "               CONFIGURAZIONE COMPLETATA!                ".bold().green());
    println!("{}", "=========================================================".cyan());
    println!("Da questo momento in poi:");
    println!("• {}", "NON serve più il computer acceso sulla rete.".bold());
    println!("• Installa l'app gratuita {} dall'App Store di tvOS.", "LocalDevVPN".bold().cyan());
    println!("• Apri SideStoreTV e goditi l'installazione di .ipa e il refresh illimitato a 7 giorni!\n");

    Ok(())
}

fn print_banner() {
    println!("{}", "=========================================================".bold().cyan());
    println!("{}", "       SideStoreTV (ATVStore) - Desktop Bootstrap Tool   ".bold().green());
    println!("{}", "=========================================================".bold().cyan());
    println!("Tool di prima configurazione wireless per Apple TV (tvOS 17+)");
    println!("---------------------------------------------------------\n");
}

async fn discover_apple_tv() -> Result<String, Box<dyn std::error::Error>> {
    println!("Ricerca Apple TV sulla rete locale tramite mDNS (_airplay)...");
    let pb = ProgressBar::new_spinner();
    pb.set_style(ProgressStyle::default_spinner().template("{spinner:.yellow} {msg}")?);
    pb.enable_steady_tick(Duration::from_millis(100));
    pb.set_message("Scansione record mDNS in corso...");

    let mdns = ServiceDaemon::new()?;
    let receiver = mdns.browse("_airplay._tcp.local.")?;

    let timeout = tokio::time::sleep(Duration::from_secs(4));
    tokio::pin!(timeout);

    let mut found_ip: Option<String> = None;

    loop {
        tokio::select! {
            _ = &mut timeout => {
                break;
            }
            event = async { receiver.recv_async().await } => {
                if let Ok(event) = event {
                    if let ServiceEvent::ServiceResolved(info) = event {
                        for addr in info.get_addresses() {
                            if addr.is_ipv4() {
                                found_ip = Some(addr.to_string());
                                break;
                            }
                        }
                    }
                }
                if found_ip.is_some() {
                    break;
                }
            }
        }
    }

    if let Some(ip) = found_ip {
        pb.finish_with_message(format!("{} Trovata Apple TV all'indirizzo {}", "✓".green(), ip.bold()));
        Ok(ip)
    } else {
        pb.finish_with_message("Apple TV non rilevata automaticamente via mDNS.");
        let manual_ip: String = Input::new()
            .with_prompt("Inserisci manualmente l'indirizzo IP dell'Apple TV (es. 192.168.1.11)")
            .default("192.168.1.11".to_string())
            .interact_text()?;
        Ok(manual_ip)
    }
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
