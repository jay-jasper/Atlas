#!/usr/bin/env ruby
# Idempotently adds Store/Direct build configurations to the Atlas project.

require "xcodeproj"

project_path = File.expand_path(File.join(__dir__, "..", "Atlas.xcodeproj"))
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |target| target.name == "Atlas" } or abort "Atlas target missing"

variants = {
  "Store Debug" => ["Debug", "ATLAS_STORE", "Atlas/AtlasStore.entitlements"],
  "Store Release" => ["Release", "ATLAS_STORE", "Atlas/AtlasStore.entitlements"],
  "Direct Debug" => ["Debug", "ATLAS_DIRECT", "Atlas/Atlas.entitlements"],
  "Direct Release" => ["Release", "ATLAS_DIRECT", "Atlas/Atlas.entitlements"],
}

def copy_configuration(owner, name, base_name)
  existing = owner.build_configurations.find { |configuration| configuration.name == name }
  return existing if existing

  base = owner.build_configurations.find { |configuration| configuration.name == base_name }
  abort "base configuration #{base_name} missing" unless base
  configuration = owner.add_build_configuration(name, base_name == "Debug" ? :debug : :release)
  configuration.build_settings = base.build_settings.dup
  configuration
end

variants.each do |name, (base, flag, entitlement)|
  copy_configuration(project, name, base)
  project.targets.each do |target|
    target_configuration = copy_configuration(target, name, base)
    target_configuration.build_settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] =
      "$(inherited) #{flag}"
  end
  configuration = app.build_configurations.find { |item| item.name == name }
  configuration.build_settings["CODE_SIGN_ENTITLEMENTS"] = entitlement
  configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "ai.atlas.app"
end

app.build_configurations.each do |configuration|
  library = configuration.name.start_with?("Store ") ? "atlas_ffi_store" : "atlas_ffi"
  configuration.build_settings["INFOPLIST_KEY_LSUIElement"] = "YES"
  configuration.build_settings["ENABLE_HARDENED_RUNTIME"] = "YES"
  configuration.build_settings["ENABLE_USER_SCRIPT_SANDBOXING"] = "NO"
  if configuration.name.include?("Release")
    configuration.build_settings["CODE_SIGN_INJECT_BASE_ENTITLEMENTS"] = "NO"
  end
  configuration.build_settings["OTHER_LDFLAGS"] = [
    "$(inherited)",
    "-lresolv",
    "-l#{library}",
  ]
end

runner_phase = app.shell_script_build_phases.find { |phase| phase.name == "Build Plugin Runner" }
runner_phase ||= app.new_shell_script_build_phase("Build Plugin Runner")
runner_phase.shell_path = "/bin/bash"
runner_phase.always_out_of_date = "1"
runner_phase.shell_script = <<~'SCRIPT'
  set -euo pipefail
  REPOSITORY_ROOT="$(cd "${SRCROOT}/../.." && pwd)"
  RUNNER_DESTINATION="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/atlas-plugin-runner"
  RUNNER_INFO_PLIST="${SRCROOT}/Atlas/Plugins/AtlasPluginRunner-Info.plist"
  if [[ "${CONFIGURATION}" != Direct* ]]; then
    rm -f "${RUNNER_DESTINATION}"
    exit 0
  fi

  PROFILE_ARGUMENT=""
  PROFILE_DIRECTORY="debug"
  if [[ "${CONFIGURATION}" == *Release ]]; then
    PROFILE_ARGUMENT="--release"
    PROFILE_DIRECTORY="release"
  fi

  RUNNER_INPUTS=()
  for ARCHITECTURE in ${ARCHS}; do
    case "${ARCHITECTURE}" in
      arm64) RUST_TARGET="aarch64-apple-darwin" ;;
      x86_64) RUST_TARGET="x86_64-apple-darwin" ;;
      *) echo "Unsupported Runner architecture: ${ARCHITECTURE}" >&2; exit 1 ;;
    esac
    cargo build \
      --manifest-path "${REPOSITORY_ROOT}/Cargo.toml" \
      --package atlas-plugin-runner \
      --target "${RUST_TARGET}" \
      --config "target.${RUST_TARGET}.rustflags=[\"-C\", \"link-arg=-Wl,-sectcreate,__TEXT,__info_plist,${RUNNER_INFO_PLIST}\"]" \
      ${PROFILE_ARGUMENT}
    RUNNER_INPUTS+=("${REPOSITORY_ROOT}/target/${RUST_TARGET}/${PROFILE_DIRECTORY}/atlas-plugin-runner")
  done

  mkdir -p "$(dirname "${RUNNER_DESTINATION}")"
  if [[ ${#RUNNER_INPUTS[@]} -eq 1 ]]; then
    cp "${RUNNER_INPUTS[0]}" "${RUNNER_DESTINATION}"
  else
    xcrun lipo -create "${RUNNER_INPUTS[@]}" -output "${RUNNER_DESTINATION}"
  fi
  chmod 755 "${RUNNER_DESTINATION}"

  if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
    SIGNING_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    /usr/bin/codesign --force --sign "${SIGNING_IDENTITY}" \
      --entitlements "${SRCROOT}/Atlas/Plugins/AtlasPluginRunner.entitlements" \
      --options runtime \
      "${RUNNER_DESTINATION}"
  fi
SCRIPT

app.source_build_phase.files.each do |build_file|
  if ["AtlasStore.entitlements", "AtlasMainView.swift"].include?(build_file.file_ref&.path)
    build_file.remove_from_project
  end
end

obsolete_view = project.files.find { |file| file.path == "AtlasMainView.swift" }
obsolete_view&.remove_from_project

app.frameworks_build_phase.files.each do |build_file|
  build_file.remove_from_project if build_file.file_ref&.path == "libatlas_ffi.a"
end

project.save
puts "Configured Store and Direct distributions"
