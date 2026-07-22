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
  if configuration.name.include?("Release")
    configuration.build_settings["CODE_SIGN_INJECT_BASE_ENTITLEMENTS"] = "NO"
  end
  configuration.build_settings["OTHER_LDFLAGS"] = [
    "$(inherited)",
    "-lresolv",
    "-l#{library}",
  ]
end

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
