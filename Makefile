SHELL := /bin/sh

.DEFAULT_GOAL := help
.NOTPARALLEL:

# Native macOS build-tool defaults. Override these with make variables or
# exported environment variables; no .env file is loaded.
CMAKE ?= cmake
CMAKE_GENERATOR ?= Unix Makefiles
MPV_ROOT ?= /opt/homebrew/opt/mpv
BUILD_JOBS ?= 4

LOCAL_BUILD_DIR := build/macos-arm64
RELEASE_BUILD_DIR := build/macos-arm64-release
RELEASE_DIR := release/macos-arm64
APP := bin/OpenFunscripter.app
ENTITLEMENTS := cmake/OpenFunscripter.entitlements.plist
PRE_NOTARY_ZIP := $(RELEASE_DIR)/OpenFunscripter-macos-arm64-pre-notarization.zip
FINAL_ZIP := $(RELEASE_DIR)/OpenFunscripter-macos-arm64-notarized.zip
PREP_STATE := $(RELEASE_DIR)/.prepared

# Required by prepare-release and release. SIGNING_IDENTITY must match an
# installed Developer ID Application identity. NOTARY_PROFILE is required by
# notarize and release and must name an existing Keychain-stored profile.
SIGNING_IDENTITY ?=
NOTARY_PROFILE ?=

.PHONY: help check-platform validate-build-vars validate-signing validate-notary \
	local-config adhoc local clean-release release-config prepare-release notarize release

help:
	@printf '%s\n' \
		'OpenFunscripter native macOS (Apple Silicon) targets:' \
		'  make adhoc          Build Release arm64 with bundled libmpv and local ad-hoc signing.' \
		'  make local          Alias for adhoc.' \
		'  make prepare-release Clean/rebuild Release arm64, Developer ID sign, verify, and create the pre-notary ZIP.' \
		'  make notarize        Revalidate the prepared app/ZIP, submit, staple, validate, and create the final ZIP.' \
		'  make release         Run prepare-release, then notarize, sequentially.' \
		'' \
		'Required variables by workflow:' \
		'  prepare-release: SIGNING_IDENTITY=... (Developer ID Application identity).' \
		'  notarize:        NOTARY_PROFILE=... (existing Keychain-stored profile).' \
		'  release:         both variables; they are preflighted before cleaning/building.' \
		'' \
		'Overrides:' \
		'  MPV_ROOT=...           libmpv installation root (default: /opt/homebrew/opt/mpv).' \
		'  BUILD_JOBS=...         CMake parallel jobs (default: 4).' \
		'  CMAKE=...              CMake executable (default: cmake).' \
		'  CMAKE_GENERATOR=...     CMake generator (default: Unix Makefiles).' \
		'' \
		'Credentials are never read from a file or stored by this Makefile.'

check-platform:
	@test "$$(uname -s)" = Darwin || { \
		echo 'This Makefile supports native macOS builds only.' >&2; exit 2; \
	}
	@test "$$(uname -m)" = arm64 || { \
		echo 'This Makefile supports verified Apple Silicon (arm64) builds only.' >&2; exit 2; \
	}

validate-build-vars: check-platform
	@case "$(BUILD_JOBS)" in \
		''|*[!0-9]*|0) echo 'BUILD_JOBS must be a positive integer.' >&2; exit 2;; \
	esac
	@test -n "$(MPV_ROOT)" || { \
		echo 'MPV_ROOT must name the libmpv installation root.' >&2; exit 2; \
	}

validate-signing: validate-build-vars
	@test -n "$(SIGNING_IDENTITY)" || { \
		echo 'SIGNING_IDENTITY is required; run security find-identity -v -p codesigning.' >&2; \
		echo 'Installed signing identities:' >&2; \
		security find-identity -v -p codesigning >&2 || true; \
		echo 'SIGNING_IDENTITY must select a Developer ID Application identity; Apple Development certificates are not accepted.' >&2; \
		echo "Example: export SIGNING_IDENTITY='<CERTIFICATE_SHA1>'" >&2; \
		echo "    or: export SIGNING_IDENTITY='Developer ID Application: <NAME> (<TEAM_ID>)'" >&2; \
		exit 2; \
	}
	@if ! security find-identity -v -p codesigning | grep -F 'Developer ID Application:' | grep -F -- "$(SIGNING_IDENTITY)" >/dev/null; then \
		echo "No installed Developer ID Application identity matched: $(SIGNING_IDENTITY)" >&2; \
		echo 'Installed signing identities:' >&2; \
		security find-identity -v -p codesigning >&2 || true; \
		echo 'SIGNING_IDENTITY must select a Developer ID Application identity; Apple Development certificates are not accepted.' >&2; \
		echo "Example: export SIGNING_IDENTITY='<CERTIFICATE_SHA1>'" >&2; \
		echo "    or: export SIGNING_IDENTITY='Developer ID Application: <NAME> (<TEAM_ID>)'" >&2; \
		exit 2; \
	fi

validate-notary: check-platform
	@test -n "$(NOTARY_PROFILE)" || { \
		echo 'NOTARY_PROFILE is required; supported notarytool commands do not enumerate Keychain profile names.' >&2; \
		echo "Choose a known profile with: export NOTARY_PROFILE='<KNOWN_PROFILE_NAME>'" >&2; \
		echo "Create a named profile once with: xcrun notarytool store-credentials OpenFunscripter --apple-id '<APPLE_ID>' --team-id '<TEAM_ID>'" >&2; \
		echo 'notarytool prompts for the password; never put credentials in the environment or repository.' >&2; \
		exit 2; \
	}

local-config: validate-build-vars
	@printf '%s\n' 'Configuring local Release arm64 build...'
	$(CMAKE) -S . -B "$(LOCAL_BUILD_DIR)" -G "$(CMAKE_GENERATOR)" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DHAVE_GCC_WERROR_DECLARATION_AFTER_STATEMENT=OFF \
		-DOFS_MPV_ROOT="$(MPV_ROOT)" \
		-DOFS_BUNDLE_MACOS_LIBMPV=ON \
		-DOFS_MACOS_ADHOC_SIGN=ON

adhoc: local-config
	@test "$(APP)" = 'bin/OpenFunscripter.app' || { echo 'Refusing to clean an unexpected app path.' >&2; exit 2; }
	rm -rf "$(APP)"
	@printf '%s\n' 'Building and locally ad-hoc signing bin/OpenFunscripter.app...'
	$(CMAKE) --build "$(LOCAL_BUILD_DIR)" --config Release --parallel "$(BUILD_JOBS)"
	@printf '%s\n' 'Verifying the local ad-hoc bundle...'
	codesign --verify --deep --strict --verbose=2 "$(APP)"
	@printf '%s\n' 'Local ad-hoc build complete: $(APP) (not Developer ID signed or notarized).'

local: adhoc

clean-release: check-platform
	@printf '%s\n' 'Removing the separate release build and artifact directories...'
	@test "$(RELEASE_BUILD_DIR)" = 'build/macos-arm64-release' || { echo 'Refusing to clean an unexpected release build path.' >&2; exit 2; }
	@test "$(RELEASE_DIR)" = 'release/macos-arm64' || { echo 'Refusing to clean an unexpected release artifact path.' >&2; exit 2; }
	@test "$(APP)" = 'bin/OpenFunscripter.app' || { echo 'Refusing to clean an unexpected app path.' >&2; exit 2; }
	rm -rf "$(RELEASE_BUILD_DIR)" "$(RELEASE_DIR)" "$(APP)"

release-config: clean-release validate-build-vars
	@printf '%s\n' 'Configuring clean Developer ID Release arm64 build...'
	$(CMAKE) -S . -B "$(RELEASE_BUILD_DIR)" -G "$(CMAKE_GENERATOR)" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DHAVE_GCC_WERROR_DECLARATION_AFTER_STATEMENT=OFF \
		-DOFS_MPV_ROOT="$(MPV_ROOT)" \
		-DOFS_BUNDLE_MACOS_LIBMPV=ON \
		-DOFS_MACOS_ADHOC_SIGN=OFF

prepare-release: validate-signing release-config
	@printf '%s\n' 'Building the clean Developer ID Release bundle...'
	$(CMAKE) --build "$(RELEASE_BUILD_DIR)" --config Release --parallel "$(BUILD_JOBS)"
	@set -eu; \
		frameworks="$(APP)/Contents/Frameworks"; \
		test -d "$$frameworks" || { \
			echo "Bundled Frameworks directory is missing: $$frameworks" >&2; exit 2; \
		}; \
		find "$$frameworks" -depth -type f -name '*.dylib' -exec sh -c 'identity="$$1"; shift; for dylib do if file "$$dylib" | grep -q "Mach-O"; then codesign --force --options runtime --timestamp --sign "$$identity" "$$dylib"; fi; done' sh "$(SIGNING_IDENTITY)" {} +
	@set -eu; \
		frameworks="$(APP)/Contents/Frameworks"; \
		find "$$frameworks" -depth -type f -name '*.dylib' -exec sh -c 'for dylib do if file "$$dylib" | grep -q "Mach-O"; then codesign --verify --strict --verbose=2 "$$dylib"; fi; done' sh {} +
	@printf '%s\n' 'Signing the outer app with the checked-in LuaJIT entitlement...'
	codesign --force --options runtime --timestamp --entitlements "$(ENTITLEMENTS)" --sign "$(SIGNING_IDENTITY)" "$(APP)"
	codesign --verify --deep --strict --verbose=2 "$(APP)"
	@mkdir -p "$(RELEASE_DIR)"
	@printf '%s\n' 'Creating the pre-notarization ZIP (no upload is performed)...'
	ditto -c -k --keepParent "$(APP)" "$(PRE_NOTARY_ZIP)"
	@set -eu; \
		manifest_tmp="$$(mktemp "$(RELEASE_DIR)/.app-manifest.XXXXXX")"; \
		state_tmp="$$(mktemp "$(RELEASE_DIR)/.prepared.XXXXXX")"; \
		trap 'rm -f "$$manifest_tmp" "$$state_tmp"' EXIT HUP INT TERM; \
		find "$(APP)" -type f -print | LC_ALL=C sort | while IFS= read -r path; do shasum -a 256 "$$path"; done > "$$manifest_tmp"; \
		app_hash="$$(shasum -a 256 "$$manifest_tmp" | awk '{print $$1}')"; \
		zip_hash="$$(shasum -a 256 "$(PRE_NOTARY_ZIP)" | awk '{print $$1}')"; \
		{ \
			printf 'APP_SHA256 %s\n' "$$app_hash"; \
			printf 'PRE_NOTARY_SHA256 %s\n' "$$zip_hash"; \
			printf 'SIGNING_IDENTITY %s\n' "$(SIGNING_IDENTITY)"; \
		} > "$$state_tmp"; \
		mv "$$state_tmp" "$(PREP_STATE)"; \
		rm -f "$$manifest_tmp"; \
		trap - EXIT HUP INT TERM
	@printf '%s\n' 'Prepared release: $(PRE_NOTARY_ZIP)'


notarize: validate-notary
	@set -eu; \
		test -d "$(APP)" || { echo 'Prepared app is missing; run make prepare-release first.' >&2; exit 2; }; \
		test -f "$(PRE_NOTARY_ZIP)" || { echo 'Pre-notary ZIP is missing; run make prepare-release first.' >&2; exit 2; }; \
		test -f "$(PREP_STATE)" || { echo 'Preparation state is missing or stale; run make prepare-release first.' >&2; exit 2; }; \
		manifest_tmp="$$(mktemp "$(RELEASE_DIR)/.verify-manifest.XXXXXX")"; \
		trap 'rm -f "$$manifest_tmp"' EXIT HUP INT TERM; \
		find "$(APP)" -type f -print | LC_ALL=C sort | while IFS= read -r path; do shasum -a 256 "$$path"; done > "$$manifest_tmp"; \
		app_hash="$$(shasum -a 256 "$$manifest_tmp" | awk '{print $$1}')"; \
		zip_hash="$$(shasum -a 256 "$(PRE_NOTARY_ZIP)" | awk '{print $$1}')"; \
		expected_app_hash="$$(awk '$$1 == "APP_SHA256" {print $$2}' "$(PREP_STATE)")"; \
		expected_zip_hash="$$(awk '$$1 == "PRE_NOTARY_SHA256" {print $$2}' "$(PREP_STATE)")"; \
		expected_identity="$$(sed -n 's/^SIGNING_IDENTITY //p' "$(PREP_STATE)")"; \
		test -n "$$expected_app_hash" && test "$$app_hash" = "$$expected_app_hash" || { echo 'Prepared app hash does not match the local preparation state.' >&2; exit 2; }; \
		test -n "$$expected_zip_hash" && test "$$zip_hash" = "$$expected_zip_hash" || { echo 'Pre-notary ZIP hash does not match the local preparation state.' >&2; exit 2; }; \
		test -n "$$expected_identity" || { echo 'Preparation state does not contain the signing identity recorded during prepare-release.' >&2; exit 2; }; \
		rm -f "$$manifest_tmp"; \
		trap - EXIT HUP INT TERM
	@set -eu; \
		frameworks="$(APP)/Contents/Frameworks"; \
		find "$$frameworks" -depth -type f -name '*.dylib' -exec sh -c 'for dylib do if file "$$dylib" | grep -q "Mach-O"; then codesign --verify --strict --verbose=2 "$$dylib"; fi; done' sh {} +
	codesign --verify --deep --strict --verbose=2 "$(APP)"
	@printf '%s\n' 'Prepared app, nested signatures, outer signature, and hashes are valid.'
	@rm -f "$(FINAL_ZIP)"
	@printf '%s\n' 'Submitting the existing pre-notarization ZIP and waiting for the result...'
	xcrun notarytool submit "$(PRE_NOTARY_ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@printf '%s\n' 'Stapling and validating the accepted notarization...'
	xcrun stapler staple "$(APP)"
	xcrun stapler validate "$(APP)"
	@set -eu; \
		spctl_output="$$(spctl --assess --type execute --verbose=4 "$(APP)" 2>&1)" || { \
			printf '%s\n' "$$spctl_output" >&2; exit 1; \
		}; \
		printf '%s\n' "$$spctl_output"; \
		printf '%s\n' "$$spctl_output" | grep -F 'source=Notarized Developer ID' >/dev/null || { \
			echo 'spctl did not report source=Notarized Developer ID.' >&2; exit 1; \
		}
	@printf '%s\n' 'Creating and hashing the final notarized ZIP...'
	ditto -c -k --keepParent "$(APP)" "$(FINAL_ZIP)"
	shasum -a 256 "$(FINAL_ZIP)"
	@printf '%s\n' 'Notarized release complete: $(FINAL_ZIP)'

release: check-platform
	@$(MAKE) validate-signing
	@$(MAKE) validate-notary
	@$(MAKE) prepare-release
	@$(MAKE) notarize
