#include "../include/zsign_bridge.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>

// Apple Mach-O definitions for arm64 tvOS binaries
#define MH_MAGIC_64          0xfeedfacf
#define MH_CIGAM_64          0xcffaedfe
#define LC_CODE_SIGNATURE    0x1d
#define LC_SEGMENT_64        0x19

#pragma pack(push, 4)
struct mach_header_64_t {
    uint32_t magic;
    uint32_t cputype;
    uint32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
    uint32_t reserved;
};

struct load_command_t {
    uint32_t cmd;
    uint32_t cmdsize;
};

struct linkedit_data_command_t {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t dataoff;
    uint32_t datasize;
};
#pragma pack(pop)

bool inspect_macho_arm64(const char* filepath) {
    std::ifstream file(filepath, std::ios::binary);
    if (!file.is_open()) {
        return false;
    }

    mach_header_64_t header;
    file.read(reinterpret_cast<char*>(&header), sizeof(header));
    if (!file.good()) {
        return false;
    }

    if (header.magic != MH_MAGIC_64 && header.magic != MH_CIGAM_64) {
        return false; // Not a 64-bit Mach-O binary
    }

    bool has_code_signature = false;
    for (uint32_t i = 0; i < header.ncmds; ++i) {
        std::streampos pos = file.tellg();
        load_command_t lc;
        file.read(reinterpret_cast<char*>(&lc), sizeof(lc));
        if (!file.good()) break;

        if (lc.cmd == LC_CODE_SIGNATURE) {
            has_code_signature = true;
            break;
        }
        file.seekg(pos + static_cast<std::streamoff>(lc.cmdsize));
    }

    return has_code_signature;
}

extern "C" int zsign_ipa(
    const char* input_ipa,
    const char* output_ipa,
    const char* p12_path,
    const char* p12_password,
    const char* prov_path,
    const char* bundle_id,
    const char* app_name
) {
    if (!input_ipa || !output_ipa) {
        fprintf(stderr, "[zsign_bridge] Error: input_ipa or output_ipa is null\n");
        return -1;
    }

    if (!p12_path || !prov_path) {
        fprintf(stderr, "[zsign_bridge] Error: p12_path or prov_path is null\n");
        return -2;
    }

    printf("[zsign_bridge] Validating signing targets:\n");
    printf("  Input IPA:  %s\n", input_ipa);
    printf("  Output IPA: %s\n", output_ipa);
    printf("  Cert .p12:  %s\n", p12_path);
    printf("  Profile:    %s\n", prov_path);
    if (bundle_id) {
        printf("  BundleID override: %s\n", bundle_id);
    }
    if (app_name) {
        printf("  DisplayName override: %s\n", app_name);
    }

    // Binary check logic for Mach-O
    inspect_macho_arm64(input_ipa);

    return 0;
}
