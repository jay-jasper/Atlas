#!/usr/bin/env ruby
# Adds source/test files to the Atlas Xcode project, idempotently.
#
# Usage:
#   ruby tools/xcode_add.rb app  Atlas/CommandPalette CalculatorProvider.swift ...
#   ruby tools/xcode_add.rb test AtlasTests           CalculatorProviderTests.swift ...
#
# First arg: target kind ("app" -> Atlas, "test" -> AtlasTests)
# Second arg: group path relative to project root group (slash-separated)
# Remaining args: file basenames (already written to disk under the group's folder)

require "xcodeproj"

PROJECT = File.expand_path(File.join(__dir__, "..", "Atlas.xcodeproj"))

target_kind = ARGV.shift
group_path = ARGV.shift
files = ARGV

abort "usage: xcode_add.rb <app|test> <group/path> file1 file2 ..." if target_kind.nil? || group_path.nil? || files.empty?

proj = Xcodeproj::Project.open(PROJECT)
target_name = target_kind == "test" ? "AtlasTests" : "Atlas"
target = proj.targets.find { |t| t.name == target_name } or abort "no target #{target_name}"

# Resolve (creating if needed) the nested group.
group = proj.main_group
group_path.split("/").each do |seg|
  nxt = group[seg]
  group = nxt || group.new_group(seg, seg)
end

added = []
files.each do |basename|
  existing = group.files.find { |f| f.display_name == basename }
  if existing
    # Ensure it's in the target's sources build phase.
    unless target.source_build_phase.files_references.include?(existing)
      target.add_file_references([existing])
    end
    next
  end
  ref = group.new_reference(basename)
  target.add_file_references([ref])
  added << basename
end

proj.save
puts "#{target_name}: added #{added.size} file(s): #{added.join(', ')}" unless added.empty?
puts "#{target_name}: no new files (already present)" if added.empty?
