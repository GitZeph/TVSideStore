use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::slice;

pub mod apple_gsa;
pub mod dev_portal;
pub mod device_bridge;
pub mod signer;

/// C-compatible result wrapper for Swift / Objective-C bridging.
#[repr(C)]
pub struct ATVResult {
    /// 0 on success, non-zero error code on failure.
    pub code: i32,
    /// Nullable heap-allocated C string describing error details.
    pub error_message: *mut c_char,
    /// Nullable heap-allocated C string containing JSON-encoded payload.
    pub data_json: *mut c_char,
}

impl ATVResult {
    pub fn ok(json: Option<String>) -> Self {
        let data_ptr = match json {
            Some(s) => match CString::new(s) {
                Ok(cs) => cs.into_raw(),
                Err(_) => std::ptr::null_mut(),
            },
            None => std::ptr::null_mut(),
        };
        Self {
            code: 0,
            error_message: std::ptr::null_mut(),
            data_json: data_ptr,
        }
    }

    pub fn err(code: i32, msg: &str) -> Self {
        let msg_ptr = match CString::new(msg) {
            Ok(cs) => cs.into_raw(),
            Err(_) => std::ptr::null_mut(),
        };
        Self {
            code: if code == 0 { -1 } else { code },
            error_message: msg_ptr,
            data_json: std::ptr::null_mut(),
        }
    }
}

/// Progress callback prototype: (percent 0-100, stage description, user context pointer).
pub type ATVProgressCallback = extern "C" fn(percent: u32, stage: *const c_char, user_data: *mut c_void);

unsafe fn cstr_to_str<'a>(ptr: *const c_char, param_name: &'static str) -> Result<&'a str, String> {
    if ptr.is_null() {
        return Err(format!("Parameter '{}' cannot be null", param_name));
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map_err(|e| format!("Parameter '{}' is invalid UTF-8: {}", param_name, e))
}

#[no_mangle]
pub extern "C" fn atv_free_result(result: *mut ATVResult) {
    if result.is_null() {
        return;
    }
    unsafe {
        let res = &mut *result;
        if !res.error_message.is_null() {
            let _ = CString::from_raw(res.error_message);
            res.error_message = std::ptr::null_mut();
        }
        if !res.data_json.is_null() {
            let _ = CString::from_raw(res.data_json);
            res.data_json = std::ptr::null_mut();
        }
    }
}

#[no_mangle]
pub extern "C" fn atv_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

// ==========================================
// ANISETTE & APPLE GSA AUTHENTICATION
// ==========================================

#[no_mangle]
pub extern "C" fn atv_anisette_set_url(url: *const c_char) -> ATVResult {
    let url_str = match unsafe { cstr_to_str(url, "url") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    apple_gsa::set_anisette_url(url_str);
    ATVResult::ok(None)
}

#[no_mangle]
pub extern "C" fn atv_anisette_fetch_headers() -> ATVResult {
    match apple_gsa::fetch_anisette_headers() {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-1, &e),
    }
}

#[no_mangle]
pub extern "C" fn atv_auth_login(apple_id: *const c_char, password: *const c_char) -> ATVResult {
    let apple_id_str = match unsafe { cstr_to_str(apple_id, "apple_id") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let password_str = match unsafe { cstr_to_str(password, "password") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    match apple_gsa::login(apple_id_str, password_str) {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-2, &e),
    }
}

#[no_mangle]
pub extern "C" fn atv_auth_submit_2fa(session_token: *const c_char, code: *const c_char) -> ATVResult {
    let token_str = match unsafe { cstr_to_str(session_token, "session_token") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let code_str = match unsafe { cstr_to_str(code, "code") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    match apple_gsa::submit_2fa(token_str, code_str) {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-3, &e),
    }
}

// ==========================================
// APPLE DEVELOPER PORTAL
// ==========================================

#[no_mangle]
pub extern "C" fn atv_dev_list_teams(session_token: *const c_char) -> ATVResult {
    let token_str = match unsafe { cstr_to_str(session_token, "session_token") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    match dev_portal::list_teams(token_str) {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-10, &e),
    }
}

#[no_mangle]
pub extern "C" fn atv_dev_register_app_id(
    session_token: *const c_char,
    team_id: *const c_char,
    bundle_id: *const c_char,
    app_name: *const c_char,
) -> ATVResult {
    let token_str = match unsafe { cstr_to_str(session_token, "session_token") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let team_str = match unsafe { cstr_to_str(team_id, "team_id") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let bundle_str = match unsafe { cstr_to_str(bundle_id, "bundle_id") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let name_str = match unsafe { cstr_to_str(app_name, "app_name") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    match dev_portal::register_app_id(token_str, team_str, bundle_str, name_str) {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-11, &e),
    }
}

#[no_mangle]
pub extern "C" fn atv_dev_provision_certificate(
    session_token: *const c_char,
    team_id: *const c_char,
    machine_name: *const c_char,
) -> ATVResult {
    let token_str = match unsafe { cstr_to_str(session_token, "session_token") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let team_str = match unsafe { cstr_to_str(team_id, "team_id") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let machine_str = match unsafe { cstr_to_str(machine_name, "machine_name") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    match dev_portal::provision_certificate(token_str, team_str, machine_str) {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-12, &e),
    }
}

#[no_mangle]
pub extern "C" fn atv_dev_provision_profile(
    session_token: *const c_char,
    team_id: *const c_char,
    bundle_id: *const c_char,
    device_udid: *const c_char,
) -> ATVResult {
    let token_str = match unsafe { cstr_to_str(session_token, "session_token") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let team_str = match unsafe { cstr_to_str(team_id, "team_id") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let bundle_str = match unsafe { cstr_to_str(bundle_id, "bundle_id") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let udid_str = match unsafe { cstr_to_str(device_udid, "device_udid") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    match dev_portal::provision_profile(token_str, team_str, bundle_str, udid_str) {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-13, &e),
    }
}

// ==========================================
// IPA RESIGNING
// ==========================================

#[no_mangle]
pub extern "C" fn atv_sign_ipa(
    input_ipa: *const c_char,
    output_ipa: *const c_char,
    p12_base64: *const c_char,
    p12_password: *const c_char,
    mobileprovision_base64: *const c_char,
    new_bundle_id: *const c_char,
    display_name: *const c_char,
    progress_cb: Option<ATVProgressCallback>,
    user_data: *mut c_void,
) -> ATVResult {
    let input_str = match unsafe { cstr_to_str(input_ipa, "input_ipa") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let output_str = match unsafe { cstr_to_str(output_ipa, "output_ipa") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let p12_str = match unsafe { cstr_to_str(p12_base64, "p12_base64") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };
    let p12_pass_str = if p12_password.is_null() {
        ""
    } else {
        match unsafe { cstr_to_str(p12_password, "p12_password") } {
            Ok(s) => s,
            Err(e) => return ATVResult::err(-1, &e),
        }
    };
    let prov_str = match unsafe { cstr_to_str(mobileprovision_base64, "mobileprovision_base64") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    let bundle_opt = if new_bundle_id.is_null() {
        None
    } else {
        match unsafe { cstr_to_str(new_bundle_id, "new_bundle_id") } {
            Ok(s) => Some(s),
            Err(e) => return ATVResult::err(-1, &e),
        }
    };

    let name_opt = if display_name.is_null() {
        None
    } else {
        match unsafe { cstr_to_str(display_name, "display_name") } {
            Ok(s) => Some(s),
            Err(e) => return ATVResult::err(-1, &e),
        }
    };

    match signer::sign_ipa(
        input_str,
        output_str,
        p12_str,
        p12_pass_str,
        prov_str,
        bundle_opt,
        name_opt,
        progress_cb,
        user_data,
    ) {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-20, &e),
    }
}

// ==========================================
// DEVICE BRIDGE (LOCKDOWN / AFC / INSTPROXY)
// ==========================================

#[no_mangle]
pub extern "C" fn atv_device_check_connection(
    host: *const c_char,
    port: u16,
    pairing_data: *const u8,
    pairing_data_len: usize,
) -> ATVResult {
    let host_str = match unsafe { cstr_to_str(host, "host") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    if pairing_data.is_null() || pairing_data_len == 0 {
        return ATVResult::err(-30, "Pairing data pointer cannot be null or empty");
    }

    let pairing_slice = unsafe { slice::from_raw_parts(pairing_data, pairing_data_len) };

    match device_bridge::check_connection(host_str, port, pairing_slice) {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-31, &e),
    }
}

#[no_mangle]
pub extern "C" fn atv_device_install_ipa(
    host: *const c_char,
    port: u16,
    pairing_data: *const u8,
    pairing_data_len: usize,
    ipa_path: *const c_char,
    bundle_id: *const c_char,
    progress_cb: Option<ATVProgressCallback>,
    user_data: *mut c_void,
) -> ATVResult {
    let host_str = match unsafe { cstr_to_str(host, "host") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    if pairing_data.is_null() || pairing_data_len == 0 {
        return ATVResult::err(-30, "Pairing data cannot be null or empty");
    }

    let pairing_slice = unsafe { slice::from_raw_parts(pairing_data, pairing_data_len) };

    let ipa_path_str = match unsafe { cstr_to_str(ipa_path, "ipa_path") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    let bundle_id_str = match unsafe { cstr_to_str(bundle_id, "bundle_id") } {
        Ok(s) => s,
        Err(e) => return ATVResult::err(-1, &e),
    };

    match device_bridge::install_ipa(
        host_str,
        port,
        pairing_slice,
        ipa_path_str,
        bundle_id_str,
        progress_cb,
        user_data,
    ) {
        Ok(json) => ATVResult::ok(Some(json)),
        Err(e) => ATVResult::err(-32, &e),
    }
}

