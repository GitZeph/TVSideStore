# ==============================================================================
# SideStoreTV (ATVStore) - Monorepo Build System
# Compiles Rust (Tier 3 tvOS), C++ Signer, packages XCFramework and Xcode project
# ==============================================================================

SHELL := /bin/bash
RUST_MANIFEST := rust-core/Cargo.toml
RUST_INCLUDE := rust-core/include
CPP_DIR := cpp-signer
FRAMEWORKS_DIR := Frameworks
XCFRAMEWORK := $(FRAMEWORKS_DIR)/ATVStoreCore.xcframework

# Target architectures
TVOS_TARGET := aarch64-apple-tvos
SIM_TARGET := aarch64-apple-tvos-sim

.PHONY: all help clean headers rust-host rust-tvos rust-tvos-sim cpp-tvos cpp-tvos-sim xcframework project

all: headers xcframework project

help:
	@echo "SideStoreTV Build Targets:"
	@echo "  make headers       - Regenerate C FFI headers using cbindgen"
	@echo "  make rust-host     - Build rust-core for host machine verification"
	@echo "  make rust-tvos     - Build rust-core for physical Apple TV (aarch64-apple-tvos)"
	@echo "  make rust-tvos-sim - Build rust-core for Apple TV Simulator (aarch64-apple-tvos-sim)"
	@echo "  make cpp-tvos      - Build cpp-signer static library for tvOS"
	@echo "  make cpp-tvos-sim  - Build cpp-signer static library for tvOS Simulator"
	@echo "  make xcframework   - Assemble ATVStoreCore.xcframework"
	@echo "  make project       - Generate ATVStore.xcodeproj via XcodeGen"
	@echo "  make clean         - Remove build artifacts"

# ------------------------------------------------------------------------------
# 1. C FFI Header Generation
# ------------------------------------------------------------------------------
headers:
	@which cbindgen > /dev/null 2>&1 && \
		cbindgen --config rust-core/cbindgen.toml --crate rust-core --output $(RUST_INCLUDE)/atv_store_core.h || \
		echo "[Notice] cbindgen not found; using pre-generated include/atv_store_core.h"

# ------------------------------------------------------------------------------
# 2. Rust Compilation (Nightly -Z build-std required for tvOS Tier 3 targets)
# ------------------------------------------------------------------------------
rust-host:
	cargo build --manifest-path $(RUST_MANIFEST) --release

rust-tvos:
	cargo +nightly build -Z build-std=std,panic_abort --target $(TVOS_TARGET) --release --manifest-path $(RUST_MANIFEST)

rust-tvos-sim:
	cargo +nightly build -Z build-std=std,panic_abort --target $(SIM_TARGET) --release --manifest-path $(RUST_MANIFEST)

# ------------------------------------------------------------------------------
# 3. C++ Mach-O Signer Compilation
# ------------------------------------------------------------------------------
cpp-tvos:
	mkdir -p $(CPP_DIR)/build-tvos
	cmake -B $(CPP_DIR)/build-tvos -S $(CPP_DIR) \
		-DCMAKE_SYSTEM_NAME=tvOS \
		-DCMAKE_OSX_SYSROOT=appletvos \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build $(CPP_DIR)/build-tvos --config Release

cpp-tvos-sim:
	mkdir -p $(CPP_DIR)/build-sim
	cmake -B $(CPP_DIR)/build-sim -S $(CPP_DIR) \
		-DCMAKE_SYSTEM_NAME=tvOS \
		-DCMAKE_OSX_SYSROOT=appletvsimulator \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build $(CPP_DIR)/build-sim --config Release

# ------------------------------------------------------------------------------
# 4. XCFramework Packaging
# ------------------------------------------------------------------------------
xcframework: rust-tvos rust-tvos-sim cpp-tvos cpp-tvos-sim
	mkdir -p $(FRAMEWORKS_DIR)
	rm -rf $(XCFRAMEWORK)
	
	# Combine Rust + C++ static archives for Device (appletvos)
	mkdir -p target/combined-tvos
	libtool -static -o target/combined-tvos/libATVStoreCore.a \
		target/$(TVOS_TARGET)/release/libatv_store_core.a \
		$(CPP_DIR)/build-tvos/libzsign_static.a

	# Combine Rust + C++ static archives for Simulator (appletvsimulator)
	mkdir -p target/combined-sim
	libtool -static -o target/combined-sim/libATVStoreCore.a \
		target/$(SIM_TARGET)/release/libatv_store_core.a \
		$(CPP_DIR)/build-sim/libzsign_static.a

	# Create unified multi-architecture XCFramework with public C headers
	xcodebuild -create-xcframework \
		-library target/combined-tvos/libATVStoreCore.a \
		-headers $(RUST_INCLUDE) \
		-library target/combined-sim/libATVStoreCore.a \
		-headers $(RUST_INCLUDE) \
		-output $(XCFRAMEWORK)
	@echo "Successfully generated $(XCFRAMEWORK)"

# ------------------------------------------------------------------------------
# 5. Xcode Project Generation
# ------------------------------------------------------------------------------
project:
	cd ATVStoreApp && xcodegen generate
	@echo "Generated ATVStore.xcodeproj successfully"

# ------------------------------------------------------------------------------
# 6. Clean
# ------------------------------------------------------------------------------
clean:
	cargo clean --manifest-path $(RUST_MANIFEST)
	rm -rf $(FRAMEWORKS_DIR) target $(CPP_DIR)/build* ATVStoreApp/ATVStore.xcodeproj

