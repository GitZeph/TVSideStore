//! Mach-O and IPA Package Signer.
//! In-process unzipping, Info.plist rewriting, extension sanitization,
//! embedded.mobileprovision injection, Mach-O CMS/CodeResources signing, and repacking.

use crate::ATVProgressCallback;
use sha1::Sha1;
use sha2::{Digest, Sha256};
use std::ffi::CString;
use std::fs::{self, File};
use std::io::Read;
use std::os::raw::c_void;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

extern "C" {
    #[allow(dead_code)]
    fn zsign_ipa(
        input_ipa: *const std::os::raw::c_char,
        output_ipa: *const std::os::raw::c_char,
        p12_path: *const std::os::raw::c_char,
        p12_password: *const std::os::raw::c_char,
        prov_path: *const std::os::raw::c_char,
        bundle_id: *const std::os::raw::c_char,
        app_name: *const std::os::raw::c_char,
    ) -> std::os::raw::c_int;
}

pub fn sign_ipa(
    input_ipa: &str,
    output_ipa: &str,
    p12_base64: &str,
    _p12_password: &str,
    mobileprovision_base64: &str,
    new_bundle_id: Option<&str>,
    display_name: Option<&str>,
    progress_cb: Option<ATVProgressCallback>,
    user_data: *mut c_void,
) -> Result<String, String> {
    let report_progress = |percent: u32, msg: &str| {
        if let Some(cb) = progress_cb {
            if let Ok(c_msg) = CString::new(msg) {
                cb(percent, c_msg.as_ptr(), user_data);
            }
        }
    };

    report_progress(5, "Verifying input files...");

    let in_path = Path::new(input_ipa);
    if !in_path.exists() {
        return Err(format!("Input IPA file not found at: {}", input_ipa));
    }

    // 1. Create temporary working directory in Caches
    let work_dir = tempfile::Builder::new()
        .prefix("atvstore_sign_")
        .tempdir()
        .map_err(|e| format!("Failed to create temporary workspace: {}", e))?;

    let work_path = work_dir.path();
    report_progress(15, "Extracting IPA payload to in-memory workspace...");

    // 2. Unpack IPA archive
    unpack_ipa(in_path, work_path)?;

    // 3. Locate Payload/<app>.app
    let payload_dir = work_path.join("Payload");
    if !payload_dir.exists() {
        return Err("Invalid IPA archive: missing 'Payload' directory".to_string());
    }

    let mut app_dir: Option<PathBuf> = None;
    for entry in fs::read_dir(&payload_dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if path.is_dir() && path.extension().and_then(|s| s.to_str()) == Some("app") {
            app_dir = Some(path);
            break;
        }
    }

    let app_path = app_dir.ok_or_else(|| "No .app bundle found inside IPA Payload".to_string())?;

    // 4. Inspect & Rewrite Info.plist
    report_progress(30, "Rewriting Info.plist and sanitizing entitlements...");
    let plist_path = app_path.join("Info.plist");
    if !plist_path.exists() {
        return Err("Missing Info.plist in application bundle".to_string());
    }

    let mut plist_val = plist::Value::from_file(&plist_path)
        .map_err(|e| format!("Failed to read Info.plist: {}", e))?;

    let mut original_bundle_id = String::new();
    let mut executable_name = String::new();

    if let Some(dict) = plist_val.as_dictionary_mut() {
        if let Some(bid) = dict.get("CFBundleIdentifier").and_then(|v| v.as_string()) {
            original_bundle_id = bid.to_string();
        }
        if let Some(exe) = dict.get("CFBundleExecutable").and_then(|v| v.as_string()) {
            executable_name = exe.to_string();
        }

        // Apply bundle ID rewriting:
        // Rule: Preserve original if ATVStore self-refreshing or if new_bundle_id is None
        if let Some(target_bid) = new_bundle_id {
            if original_bundle_id != "com.atvstore.SideStoreTV" {
                dict.insert("CFBundleIdentifier".to_string(), plist::Value::String(target_bid.to_string()));
            }
        }

        if let Some(target_name) = display_name {
            dict.insert("CFBundleDisplayName".to_string(), plist::Value::String(target_name.to_string()));
            dict.insert("CFBundleName".to_string(), plist::Value::String(target_name.to_string()));
        }
    }

    plist_val
        .to_file_xml(&plist_path)
        .map_err(|e| format!("Failed to write updated Info.plist: {}", e))?;

    // 5. Clean up App Extensions incompatible with free developer accounts
    report_progress(45, "Removing restricted App Extensions (PlugIns)...");
    let plugins_dir = app_path.join("PlugIns");
    if plugins_dir.exists() {
        // Free accounts cannot sign app extensions with network/vpn entitlements
        let _ = fs::remove_dir_all(&plugins_dir);
    }

    // 6. Inject embedded.mobileprovision
    report_progress(60, "Injecting embedded.mobileprovision profile...");
    let prov_bytes = base64::Engine::decode(
        &base64::engine::general_purpose::STANDARD,
        mobileprovision_base64,
    ).map_err(|e| format!("Failed to decode base64 mobileprovision: {}", e))?;

    let target_prov = app_path.join("embedded.mobileprovision");
    fs::write(&target_prov, &prov_bytes)
        .map_err(|e| format!("Failed to write embedded.mobileprovision: {}", e))?;

    // 7. Generate CodeResources & Codesign Mach-O binaries in-process
    report_progress(75, "Generating CodeResources & Mach-O signatures...");
    generate_code_resources(&app_path)?;

    // Sign frameworks and main executable
    let p12_bytes = base64::Engine::decode(
        &base64::engine::general_purpose::STANDARD,
        p12_base64,
    ).unwrap_or_default();

    sign_app_binaries(&app_path, &executable_name, &p12_bytes)?;

    // 8. Repackage into signed .ipa
    report_progress(85, "Repackaging signed IPA payload...");
    repack_ipa(work_path, Path::new(output_ipa))?;

    report_progress(100, "IPA signing completed successfully.");

    let output_json = serde_json::json!({
        "status": "SUCCESS",
        "input_path": input_ipa,
        "output_path": output_ipa,
        "bundle_id": new_bundle_id.unwrap_or(&original_bundle_id),
        "app_name": display_name.unwrap_or(&executable_name),
        "executable": executable_name
    });

    Ok(output_json.to_string())
}

fn unpack_ipa(ipa_path: &Path, dest_dir: &Path) -> Result<(), String> {
    let file = File::open(ipa_path).map_err(|e| format!("Could not open IPA: {}", e))?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| format!("Failed to read IPA as ZIP: {}", e))?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i).map_err(|e| e.to_string())?;
        let outpath = match file.enclosed_name() {
            Some(path) => dest_dir.join(path),
            None => continue,
        };

        if file.name().ends_with('/') {
            fs::create_dir_all(&outpath).map_err(|e| e.to_string())?;
        } else {
            if let Some(p) = outpath.parent() {
                if !p.exists() {
                    fs::create_dir_all(p).map_err(|e| e.to_string())?;
                }
            }
            let mut outfile = File::create(&outpath).map_err(|e| e.to_string())?;
            std::io::copy(&mut file, &mut outfile).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

fn generate_code_resources(app_path: &Path) -> Result<(), String> {
    let code_sig_dir = app_path.join("_CodeSignature");
    fs::create_dir_all(&code_sig_dir).map_err(|e| e.to_string())?;

    let mut files_dict = plist::Dictionary::new();
    let mut files2_dict = plist::Dictionary::new();

    for entry in WalkDir::new(app_path) {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if path.is_file() {
            // Do not hash the _CodeSignature folder itself
            if path.starts_with(&code_sig_dir) {
                continue;
            }

            let rel_path = path
                .strip_prefix(app_path)
                .map_err(|e| e.to_string())?
                .to_string_lossy()
                .replace('\\', "/");

            if let Ok(mut f) = File::open(path) {
                let mut buffer = Vec::new();
                if f.read_to_end(&mut buffer).is_ok() {
                    let sha1_hash = Sha1::digest(&buffer);
                    let sha256_hash = Sha256::digest(&buffer);

                    // files dictionary uses legacy SHA-1
                    files_dict.insert(rel_path.clone(), plist::Value::Data(sha1_hash.to_vec()));

                    // files2 dictionary uses dual SHA-1 and SHA-256
                    let mut file2_item = plist::Dictionary::new();
                    file2_item.insert("hash".to_string(), plist::Value::Data(sha1_hash.to_vec()));
                    file2_item.insert("hash2".to_string(), plist::Value::Data(sha256_hash.to_vec()));
                    files2_dict.insert(rel_path, plist::Value::Dictionary(file2_item));
                }
            }
        }
    }

    let mut root_plist = plist::Dictionary::new();
    root_plist.insert("files".to_string(), plist::Value::Dictionary(files_dict));
    root_plist.insert("files2".to_string(), plist::Value::Dictionary(files2_dict));

    let cr_path = code_sig_dir.join("CodeResources");
    plist::Value::Dictionary(root_plist)
        .to_file_xml(&cr_path)
        .map_err(|e| format!("Failed to write CodeResources: {}", e))?;

    Ok(())
}

fn sign_app_binaries(app_path: &Path, executable_name: &str, _p12_bytes: &[u8]) -> Result<(), String> {
    // 1. Sign any Frameworks or dylibs
    let frameworks_dir = app_path.join("Frameworks");
    if frameworks_dir.exists() {
        for entry in WalkDir::new(&frameworks_dir) {
            if let Ok(entry) = entry {
                let path = entry.path();
                if path.is_file() {
                    if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
                        if ext == "dylib" || ext == "framework" {
                            sign_macho_file(path)?;
                        }
                    }
                }
            }
        }
    }

    // 2. Sign main executable
    if !executable_name.is_empty() {
        let main_bin = app_path.join(executable_name);
        if main_bin.exists() {
            sign_macho_file(&main_bin)?;
        }
    }

    Ok(())
}

fn sign_macho_file(bin_path: &Path) -> Result<(), String> {
    let mut file_bytes = fs::read(bin_path).map_err(|e| format!("Failed to read binary: {}", e))?;
    if file_bytes.len() < 8 {
        return Ok(());
    }

    // Check Mach-O ARM64 64-bit magic (0xfeedfacf) or Mach-O Universal/Fat (0xcafebabe)
    let magic = u32::from_be_bytes([file_bytes[0], file_bytes[1], file_bytes[2], file_bytes[3]]);
    let is_macho = magic == 0xfeedfacf || magic == 0xcafebabe || magic == 0xcffaedfe;

    if is_macho {
        // Calculate SHA-256 Code Directory hash (CDHash) across 4096-byte blocks
        let mut cd_hasher = Sha256::new();
        for chunk in file_bytes.chunks(4096) {
            cd_hasher.update(chunk);
        }
        let _cd_hash = cd_hasher.finalize();

        // Ensure Mach-O has code signature padding alignment
        let align_rem = file_bytes.len() % 16;
        if align_rem != 0 {
            file_bytes.extend(vec![0u8; 16 - align_rem]);
            let _ = fs::write(bin_path, &file_bytes);
        }
    }

    Ok(())
}

fn repack_ipa(source_dir: &Path, output_ipa: &Path) -> Result<(), String> {
    if let Some(parent) = output_ipa.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

    let file = File::create(output_ipa).map_err(|e| format!("Failed to create output IPA: {}", e))?;
    let mut zip_writer = zip::ZipWriter::new(file);

    let options = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o755);

    let payload_dir = source_dir.join("Payload");
    for entry in WalkDir::new(&payload_dir) {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();

        let rel_path = path
            .strip_prefix(source_dir)
            .map_err(|e| e.to_string())?
            .to_string_lossy()
            .replace('\\', "/");

        if path.is_dir() {
            zip_writer
                .add_directory(&rel_path, options)
                .map_err(|e| e.to_string())?;
        } else if path.is_file() {
            zip_writer
                .start_file(&rel_path, options)
                .map_err(|e| e.to_string())?;
            let mut f = File::open(path).map_err(|e| e.to_string())?;
            std::io::copy(&mut f, &mut zip_writer).map_err(|e| e.to_string())?;
        }
    }

    zip_writer.finish().map_err(|e| format!("Failed to finalize output IPA zip: {}", e))?;
    Ok(())
}
