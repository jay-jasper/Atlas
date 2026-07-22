#!/usr/bin/env ruby
# Registers Launcher module sources + tests in Atlas.xcodeproj. Idempotent.
require "xcodeproj"

project_path = File.expand_path(File.join(__dir__, "..", "Atlas.xcodeproj"))
repo_macos = File.expand_path(File.join(__dir__, ".."))
project = Xcodeproj::Project.open(project_path)

app = project.targets.find { |t| t.name == "Atlas" } or abort "Atlas target missing"
tests = project.targets.find { |t| t.name == "AtlasTests" } or abort "AtlasTests target missing"

REMOVED_FILES = [
  "CommandPaletteView.swift",
  "CommandPaletteController.swift",
].freeze

def ensure_group(parent, name, path)
  parent[name] || parent.new_group(name, path)
end

def add_file(group, target, filename)
  reference = group.files.find { |f| f.path == filename } || group.new_reference(filename)
  unless target.source_build_phase.files_references.include?(reference)
    target.add_file_references([reference])
  end
end

atlas_group = project.main_group["Atlas"] or abort "Atlas group missing"

%w[Launcher MainShell AIChat MenuPanel].each do |dir|
  group = ensure_group(atlas_group, dir, dir)
  Dir.glob(File.join(repo_macos, "Atlas", dir, "*.swift")).sort.each do |file|
    add_file(group, app, File.basename(file))
  end
  # Prune references whose backing files were deleted.
  group.files.select { |f| !File.exist?(File.join(repo_macos, "Atlas", dir, f.path.to_s)) }.each do |reference|
    reference.build_files.each(&:remove_from_project)
    reference.remove_from_project
  end
end

# Provider icon SVGs → app resources build phase.
aichat_group = atlas_group["AIChat"]
icons_group = ensure_group(aichat_group, "ProviderIcons", "ProviderIcons")
Dir.glob(File.join(repo_macos, "Atlas", "AIChat", "ProviderIcons", "*.svg")).sort.each do |file|
  name = File.basename(file)
  reference = icons_group.files.find { |f| f.path == name } || icons_group.new_reference(name)
  unless app.resources_build_phase.files_references.include?(reference)
    app.resources_build_phase.add_file_reference(reference)
  end
end

widgets_parent = atlas_group["MenuPanel"]
widgets_group = ensure_group(widgets_parent, "Widgets", "Widgets")
Dir.glob(File.join(repo_macos, "Atlas", "MenuPanel", "Widgets", "*.swift")).sort.each do |file|
  add_file(widgets_group, app, File.basename(file))
end

tests_group = project.main_group["AtlasTests"] or abort "AtlasTests group missing"
["Launcher*Tests.swift", "ShellTab*Tests.swift", "AI*Tests.swift", "MenuPanel*Tests.swift"].each do |pattern|
  Dir.glob(File.join(repo_macos, "AtlasTests", pattern)).sort.each do |file|
    add_file(tests_group, tests, File.basename(file))
  end
end

# Drop references to palette view layer files once they are deleted from disk;
# re-add them while they still exist.
palette_group = atlas_group["CommandPalette"]
if palette_group
  REMOVED_FILES.each do |name|
    next unless File.exist?(File.join(repo_macos, "Atlas", "CommandPalette", name))
    add_file(palette_group, app, name)
  end
  stale = palette_group.files.select do |f|
    REMOVED_FILES.include?(f.path) &&
      !File.exist?(File.join(repo_macos, "Atlas", "CommandPalette", f.path))
  end
  stale.each do |reference|
    reference.build_files.each(&:remove_from_project)
    reference.remove_from_project
  end
end

project.save
puts "Launcher files registered"
