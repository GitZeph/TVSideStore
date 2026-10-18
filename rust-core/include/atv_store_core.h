#ifndef ATV_STORE_CORE_H
#define ATV_STORE_CORE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Result structure returned by all FFI functions.
 * Memory allocated in error_message or data_json MUST be freed via atv_free_result().
 */
typedef struct {
    int32_t code;           /* 0 = SUCCESS, non-zero = ERROR */
    char* error_message;    /* Nullable error description (owned by caller) */
    char* data_json;        /* Nullable JSON-formatted output string (owned by caller) */
} ATVResult;

/**
 * Progress callback prototype.
 * percent: 0 to 100
 * stage: description of current step (e.g., "Uploading IPA", "Installing")
 * user_data: context pointer passed in by the caller
 */
typedef void (*ATVProgressCallback)(uint32_t percent, const char* stage, void* user_data);

/* Memory deallocation functions */
void atv_free_result(ATVResult* result);
void atv_free_string(char* s);

/* ========================================================================= */
/* Anisette & Apple GSA Authentication                                       */
/* ========================================================================= */

ATVResult atv_anisette_set_url(const char* url);
ATVResult atv_anisette_fetch_headers(void);
ATVResult atv_auth_login(const char* apple_id, const char* password);
ATVResult atv_auth_submit_2fa(const char* session_token, const char* code);

/* ========================================================================= */
/* Apple Developer Portal APIs                                               */
/* ========================================================================= */

ATVResult atv_dev_list_teams(const char* session_token);
ATVResult atv_dev_register_app_id(
    const char* session_token,
    const char* team_id,
    const char* bundle_id,
    const char* app_name
);
ATVResult atv_dev_provision_certificate(
    const char* session_token,
    const char* team_id,
    const char* machine_name
);
ATVResult atv_dev_provision_profile(
    const char* session_token,
    const char* team_id,
    const char* bundle_id,
    const char* device_udid
);

/* ========================================================================= */
/* IPA Resigning                                                             */
/* ========================================================================= */

ATVResult atv_sign_ipa(
    const char* input_ipa,
    const char* output_ipa,
    const char* p12_base64,
    const char* p12_password,
    const char* mobileprovision_base64,
    const char* new_bundle_id,
    const char* display_name,
    ATVProgressCallback progress_cb,
    void* user_data
);

/* ========================================================================= */
/* Apple TV Device Bridge (Lockdown / AFC / InstallationProxy)               */
/* ========================================================================= */

ATVResult atv_device_check_connection(
    const char* host,
    uint16_t port,
    const uint8_t* pairing_data,
    size_t pairing_data_len
);

ATVResult atv_device_install_ipa(
    const char* host,
    uint16_t port,
    const uint8_t* pairing_data,
    size_t pairing_data_len,
    const char* ipa_path,
    const char* bundle_id,
    ATVProgressCallback progress_cb,
    void* user_data
);

#ifdef __cplusplus
}
#endif

#endif /* ATV_STORE_CORE_H */

