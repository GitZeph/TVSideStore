#ifndef ZSIGN_BRIDGE_H
#define ZSIGN_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Signs an IPA archive in-process using zsign engine.
 *
 * @param input_ipa Path to input unsigned or expired .ipa
 * @param output_ipa Path where signed .ipa should be output
 * @param p12_path Path to PKCS#12 (.p12) certificate file
 * @param p12_password Password for .p12 certificate (or empty string)
 * @param prov_path Path to .mobileprovision file
 * @param bundle_id Custom bundle identifier override (or NULL to preserve)
 * @param app_name Custom app display name override (or NULL to preserve)
 * @return 0 on success, non-zero on error.
 */
int zsign_ipa(
    const char* input_ipa,
    const char* output_ipa,
    const char* p12_path,
    const char* p12_password,
    const char* prov_path,
    const char* bundle_id,
    const char* app_name
);

#ifdef __cplusplus
}
#endif

#endif // ZSIGN_BRIDGE_H

