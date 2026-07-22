#!/usr/bin/env ruby
require "xcodeproj"

project_path = File.expand_path(File.join(__dir__, "..", "Atlas.xcodeproj"))
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |target| target.name == "Atlas" } or abort "Atlas target missing"
target = project.targets.find { |item| item.name == "AtlasUITests" }
target ||= project.new_target(:ui_test_bundle, "AtlasUITests", :osx, "13.0")
target.add_dependency(app) unless target.dependencies.any? { |dependency| dependency.target == app }

group = project.main_group["AtlasUITests"] || project.main_group.new_group("AtlasUITests", "AtlasUITests")
reference = group.files.find { |file| file.path == "AtlasUITests.swift" } || group.new_reference("AtlasUITests.swift")
target.add_file_references([reference]) unless target.source_build_phase.files_references.include?(reference)

target.build_configurations.each do |configuration|
  configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "ai.atlas.app.uitests"
  configuration.build_settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  configuration.build_settings["TEST_TARGET_NAME"] = "Atlas"
  configuration.build_settings["SWIFT_VERSION"] = "5.0"
  configuration.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  configuration.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
end

project.save
puts "Configured AtlasUITests"
