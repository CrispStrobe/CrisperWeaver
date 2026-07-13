#!/usr/bin/env ruby
# Wire ios/Frameworks/glint.xcframework into the Runner target so
# `flutter build ios` links the glint codec framework into Runner.app.
# glint's Dart loader uses DynamicLibrary.process() on iOS, so LINKING it
# into the Runner binary is what makes glint_* visible at runtime (dyld
# loads the linked framework at launch → symbols land in the process
# image). Embedding it (Copy Files phase, CodeSignOnCopy) ships the
# framework inside the .app.
#
# Idempotent — safe to re-run after `pod install`.
# Run from repo root: ruby scripts/wire_ios_glint.rb

require 'xcodeproj'

REPO_ROOT  = File.expand_path('..', __dir__)
PROJECT    = File.join(REPO_ROOT, 'ios', 'Runner.xcodeproj')
XCFW_PATH  = 'Frameworks/glint.xcframework'
XCFW_ABS   = File.join(REPO_ROOT, 'ios', XCFW_PATH)

abort "missing #{XCFW_ABS} — run scripts/build_ios_glint_xcframework.sh first" \
  unless File.exist?(XCFW_ABS)

project = Xcodeproj::Project.open(PROJECT)
target  = project.targets.find { |t| t.name == 'Runner' } or
  abort 'Runner target not found'

# 1. File reference in the Frameworks group.
fw_group = project.main_group['Frameworks'] ||
           project.main_group.new_group('Frameworks')

ref = fw_group.files.find { |f| f.path == XCFW_PATH }
unless ref
  ref = fw_group.new_file(XCFW_PATH)
  ref.last_known_file_type = 'wrapper.xcframework'
end

# 2. Link Binary With Libraries — binds glint_* into the Runner image so
#    DynamicLibrary.process() resolves them.
link_phase = target.frameworks_build_phase
unless link_phase.files_references.include?(ref)
  link_phase.add_file_reference(ref)
end

# 3. Embed Frameworks (Copy Files, dst_subfolder_spec=10 → <app>.app/Frameworks/).
embed_phase = target.copy_files_build_phases.find do |p|
  p.dst_subfolder_spec == '10' && p.name&.include?('Embed')
end
unless embed_phase
  embed_phase = target.new_copy_files_build_phase('Embed Frameworks')
  embed_phase.dst_subfolder_spec = '10'
  embed_phase.dst_path = ''
end

embed_file = embed_phase.files.find { |bf| bf.file_ref == ref }
unless embed_file
  embed_file = embed_phase.add_file_reference(ref)
end
embed_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }

# 4. FRAMEWORK_SEARCH_PATHS so the linker finds the .xcframework.
target.build_configurations.each do |config|
  paths = config.build_settings['FRAMEWORK_SEARCH_PATHS']
  paths = case paths
          when nil then ['$(inherited)']
          when String then [paths]
          else paths
          end
  needed = '$(PROJECT_DIR)/Frameworks'
  config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths | [needed]
end

project.save

puts 'wired glint.xcframework into Runner target:'
puts '  - file reference in Frameworks group'
puts '  - linked into binary (satisfies DynamicLibrary.process())'
puts '  - embedded with CodeSignOnCopy'
puts '  - FRAMEWORK_SEARCH_PATHS includes $(PROJECT_DIR)/Frameworks'
