#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# Generates apple/DSH.xcodeproj from the sources on disk. The project file is a
# build output of this script: change this script, never hand-edit the pbxproj.
#
# Prerequisites (not committed):
#   bash tooling/build-ish.sh                 -> apple/Vendor/ish/ish.xcframework
#   bash runtime/build-ios-runtime.sh   -> runtime/out/ios-arm64/assets/runtime
require 'fileutils'
require 'xcodeproj'

APPLE = File.expand_path('../apple', __dir__)
PROJECT_PATH = File.join(APPLE, 'DSH.xcodeproj')
DEPLOYMENT = '17.0'
BUNDLE_ID = 'io.github.fanofacane.dsh' # Placeholder until branding (see ios-port.md stage 7).

# Keep the SwiftPM pins (swift-nio-ssh and its dependencies) across regenerations.
RESOLVED = File.join(PROJECT_PATH, 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
pins = File.exist?(RESOLVED) ? File.read(RESOLVED) : nil

# Xcodeproj's UUID predictor hashes target proxies' original UUID strings too.
# Give those temporary IDs a repeatable seed before deriving content-based IDs.
class GeneratedAppleProject < Xcodeproj::Project
  def generate_uuid
    @temporary_uuid = (@temporary_uuid || 0) + 1
    format('%024X', @temporary_uuid)
  end
end

FileUtils.rm_rf(PROJECT_PATH)
project = GeneratedAppleProject.new(PROJECT_PATH)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2700'
project.root_object.known_regions = %w[en zh-Hans Base]
project.root_object.development_region = 'en'

def add_sources(project, target, group_path, extensions, recursive: false)
  group = project.main_group.find_subpath(group_path, true)
  group.set_source_tree('<group>')
  group.set_path(group_path)
  refs = []
  base = File.join(APPLE, group_path)
  Dir.glob(File.join(base, recursive ? '**/*' : '*')).sort.each do |path|
    next unless File.file?(path) && extensions.include?(File.extname(path))
    parts = path.delete_prefix(base + '/').split('/')
    name = parts.pop
    parent = parts.reduce(group) do |current, folder|
      current.groups.find { |sub| sub.path == folder } || current.new_group(folder, folder)
    end
    ref = parent.new_reference(name)
    refs << ref
    target.source_build_phase.add_file_reference(ref, true) if File.extname(path) == '.swift'
  end
  [group, refs]
end

def common_settings(target)
  target.build_configurations.each do |config|
    s = config.build_settings
    s['SWIFT_VERSION'] = '5.0'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT
    s['TARGETED_DEVICE_FAMILY'] = '1,2'
    # The guest gadget engine and both xcframework slices are ARM64 only.
    s['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'x86_64'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['CURRENT_PROJECT_VERSION'] = '1'
    s['MARKETING_VERSION'] = '0.1.0'
    s['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
    if config.name == 'Debug'
      s['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = ['$(inherited)', 'DEBUG']
      s['ENABLE_TESTABILITY'] = 'YES'
    end
  end
end

# --- DSHRuntime: Flutter-free engine module, links the iSH static framework.
runtime = project.new_target(:framework, 'DSHRuntime', :ios, DEPLOYMENT)
runtime_group, _ = add_sources(project, runtime, 'Modules/DSHRuntime', ['.swift'])
# Native inputs are compiled into ish.xcframework by tooling/build-ish.sh.
# Keep them visible in Xcode without compiling them again in the Swift target.
native_group = runtime_group.new_group('Native', 'Native')
%w[ISHRuntime.h ISHRuntime.m].each { |name| native_group.new_reference(name) }
vendor = project.main_group.find_subpath('Vendor', true)
vendor.set_source_tree('<group>')
vendor.set_path('Vendor')
ish = vendor.new_reference('ish/ish.xcframework')
runtime.frameworks_build_phase.add_file_reference(ish, true)
common_settings(runtime)
runtime.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.runtime"
  s['PRODUCT_NAME'] = 'DSHRuntime'
  s['DEFINES_MODULE'] = 'YES'
  s['SKIP_INSTALL'] = 'YES'
  s['OTHER_LDFLAGS'] = %w[$(inherited) -lsqlite3 -lz -llzma -liconv -lresolv]
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
end

# --- DSHClient: Swift port of the dsh_client wire contract (no third-party deps).
client = project.new_target(:framework, 'DSHClient', :ios, DEPLOYMENT)
add_sources(project, client, 'Modules/DSHClient', ['.swift'])
common_settings(client)
client.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.client"
  s['PRODUCT_NAME'] = 'DSHClient'
  s['DEFINES_MODULE'] = 'YES'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
end

# --- DSHPhone: phone-control MCP server, loopback bridge, safety (Foundation/Network only).
phone = project.new_target(:framework, 'DSHPhone', :ios, DEPLOYMENT)
add_sources(project, phone, 'Modules/DSHPhone', ['.swift'])
common_settings(phone)
phone.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.phone"
  s['PRODUCT_NAME'] = 'DSHPhone'
  s['DEFINES_MODULE'] = 'YES'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
end

# --- DSHRemote: SSH link to a computer running `dsh web` (swift-nio-ssh), remote
# bootstrap of `dsh web`, and the loopback port forward the client talks to.
remote = project.new_target(:framework, 'DSHRemote', :ios, DEPLOYMENT)
remote_group, _ = add_sources(project, remote, 'Modules/DSHRemote', ['.swift'])
# Relay/: the ds-harness-remote client (Noise IK, relay transport, account, tunnel carrier).
relay_group = remote_group.new_group('Relay', 'Relay')
Dir.glob(File.join(APPLE, 'Modules/DSHRemote/Relay/*.swift')).sort.each do |path|
  remote.source_build_phase.add_file_reference(relay_group.new_reference(File.basename(path)), true)
end
common_settings(remote)
remote.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.remote"
  s['PRODUCT_NAME'] = 'DSHRemote'
  s['DEFINES_MODULE'] = 'YES'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
end
remote.add_dependency(client)
remote.frameworks_build_phase.add_file_reference(client.product_reference, true)
nio_ssh = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
nio_ssh.repositoryURL = 'https://github.com/apple/swift-nio-ssh.git'
nio_ssh.requirement = { 'kind' => 'upToNextMinorVersion', 'minimumVersion' => '0.15.1' }
project.root_object.package_references << nio_ssh
%w[NIOSSH NIOCore NIOPosix].each do |product|
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = nio_ssh
  dep.product_name = product
  remote.package_product_dependencies << dep
  file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  file.product_ref = dep
  remote.frameworks_build_phase.files << file
end

# --- DSH app (SwiftUI).
app = project.new_target(:application, 'DSH', :ios, DEPLOYMENT)
app_group, app_refs = add_sources(project, app, 'App', ['.swift', '.xcstrings', '.entitlements', '.plist'], recursive: true)
app_refs.select { |r| r.path.end_with?('.xcstrings') }.each { |r| app.resources_build_phase.add_file_reference(r, true) }
# Shared with the extensions: Live Activity attributes, deep links, share inbox.
_shared_group, shared_refs = add_sources(project, app, 'Extensions/Shared', ['.swift'])
app.resources_build_phase.add_file_reference(app_group.new_reference('Assets.xcassets'), true)
app.resources_build_phase.add_file_reference(app_group.new_reference('PrivacyInfo.xcprivacy'), true)
# App resources, owned by apple/. Phone/phone-ios-tools.json is the phone tool
# catalog contract (single source for the app and its tests).
resources = project.main_group.new_group('Resources', 'Resources')
['Phone/relay.cjs', 'Phone/phone.patch.yml', 'Phone/phone-ios-tools.json',
 # Mist Glass: Phosphor icon font (MIT), JetBrains Mono (OFL), whale tail.
 'Fonts/DshIcons.ttf', 'Fonts/JetBrainsMono-Regular.ttf', 'Fonts/JetBrainsMono-Medium.ttf',
 'Fonts/JetBrainsMono-Bold.ttf', *%w[1 2 3 4].map { |level| "Images/whale_#{level}.png" }].each do |path|
  app.resources_build_phase.add_file_reference(resources.new_reference(path), true)
end
# Pack manifests and sheets stay together so both targets can discover packs.
pet_pack = resources.new_reference('Pets')
pet_pack.last_known_file_type = 'folder'
app.resources_build_phase.add_file_reference(pet_pack, true)
license_pack = resources.new_reference('Licenses')
license_pack.last_known_file_type = 'folder'
app.resources_build_phase.add_file_reference(license_pack, true)
common_settings(app)
app.build_configurations.each do |config|
  s = config.build_settings
  s['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = ['$(inherited)', 'DSH_MAIN_APP'] + (config.name == 'Debug' ? ['DEBUG'] : [])
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['PRODUCT_NAME'] = 'DSH'
  s['INFOPLIST_KEY_CFBundleDisplayName'] = 'DSH Fan'
  s['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  s['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  s['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  s['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  s['CODE_SIGN_ENTITLEMENTS'] = 'App/DSH.entitlements'
  s['INFOPLIST_FILE'] = 'App/Info.plist'
  # Runs on Apple silicon Macs as the iPad app (M5); a native Mac app is separate work.
  s['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'YES'
  # AlarmKit exists only on iOS 26+; the app runs from iOS 17.
  s['OTHER_LDFLAGS'] = %w[$(inherited) -weak_framework AlarmKit]
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
  s['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
  s['ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS'] = 'YES'
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor' # Mist accent #4B67B4 / #97B1F0
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = '' # App icon arrives with the new brand (stage 7).
end
embed = app.new_copy_files_build_phase('Embed Frameworks')
embed.symbol_dst_subfolder_spec = :frameworks
[runtime, client, phone, remote].each do |framework|
  app.add_dependency(framework)
  app.frameworks_build_phase.add_file_reference(framework.product_reference, true)
  embed_file = embed.add_file_reference(framework.product_reference, true)
  embed_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
end

# --- App extensions: widgets (Ask, Control, Live Activity) and share.
def extension(project, name, folder, plist, bundle_suffix, entitlements, extra_refs)
  target = project.new_target(:app_extension, name, :ios, DEPLOYMENT)
  _group, refs = add_sources(project, target, folder, ['.swift', '.plist', '.entitlements', '.xcstrings'])
  refs.select { |r| r.path.end_with?('.xcstrings') }.each { |r| target.resources_build_phase.add_file_reference(r, true) }
  extra_refs.each { |ref| target.source_build_phase.add_file_reference(ref, true) }
  common_settings(target)
  target.build_configurations.each do |config|
    s = config.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.#{bundle_suffix}"
    s['PRODUCT_NAME'] = name
    s['INFOPLIST_FILE'] = plist
    s['INFOPLIST_KEY_CFBundleDisplayName'] = 'DSH Fan'
    s['SKIP_INSTALL'] = 'YES'
    s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    s['CODE_SIGN_ENTITLEMENTS'] = entitlements if entitlements
    s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  end
  target
end
theme_refs = shared_refs + %w[Theme.swift AccentMath.swift Glyphs.swift].map { |name| app_refs.find { |ref| ref.path == name } }
widgets = extension(project, 'DSHWidgets', 'Extensions/Widgets', 'Extensions/Widgets/Info.plist', 'widgets', nil, theme_refs)
widgets.resources_build_phase.add_file_reference(pet_pack, true)

# Local reference art is optional and excluded from Release and source control.
# Evaluate it at build time so a local preview does not change the project.
[app, widgets].each do |target|
  target.build_configurations.each { |config| config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO' }
  local_pets = target.new_shell_script_build_phase('Copy local pet previews')
  local_pets.always_out_of_date = '1'
  local_pets.shell_script = <<~'SH'
    set -eu
    source="$SRCROOT/Resources/PetsLocal"
    destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/PetsLocal"
    if [ "$CONFIGURATION" = Debug ] && [ -d "$source" ]; then
      rm -rf "$destination"
      ditto "$source" "$destination"
    elif [ -d "$destination" ]; then
      rm -rf "$destination"
    fi
  SH
end
share = extension(project, 'DSHShare', 'Extensions/Share', 'Extensions/Share/Info.plist', 'share', 'Extensions/Share/DSHShare.entitlements', theme_refs)
plugins = app.new_copy_files_build_phase('Embed App Extensions')
plugins.symbol_dst_subfolder_spec = :plug_ins
[widgets, share].each do |ext|
  app.add_dependency(ext)
  plugins.add_file_reference(ext.product_reference, true).settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy] }
end

# --- Swift Testing: the existing client contract assertions, hosted by DSH.
tests = project.new_target(:unit_test_bundle, 'DSHTests', :ios, DEPLOYMENT)
add_sources(project, tests, 'Tests', ['.swift'])
common_settings(tests)
tests.add_dependency(app)
project.root_object.attributes['TargetAttributes'] = {
  tests.uuid => { 'TestTargetID' => app.uuid }
}
tests.frameworks_build_phase.add_file_reference(client.product_reference, true)
tests.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.tests"
  s['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/DSH.app/DSH'
  s['BUNDLE_LOADER'] = '$(TEST_HOST)'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@loader_path/Frameworks', '@executable_path/Frameworks']
end

bundle = app.new_shell_script_build_phase('Bundle iOS runtime')
bundle.always_out_of_date = '1'
bundle.shell_script = <<~SH
  set -eu
  source_dir="$SRCROOT/../runtime/out/ios-arm64/assets/runtime"
  destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/runtime"
  mkdir -p "$destination"
  for name in manifest.json rootfs-ios-arm64.tar.xz; do
    if [ ! -f "$source_dir/$name" ]; then
      echo "error: Missing iOS runtime. Run: bash runtime/build-ios-runtime.sh" >&2
      exit 1
    fi
    # Copy only when changed: the archive is ~130 MiB.
    if ! cmp -s "$source_dir/$name" "$destination/$name"; then cp "$source_dir/$name" "$destination/$name"; fi
  done
SH

# Xcode runs App Intents extraction for every Swift target, including targets
# without intents. Link the system framework so extraction completes without a
# missing-dependency warning (the app and widgets already import it).
app_intents = project.frameworks_group.new_reference('System/Library/Frameworks/AppIntents.framework', :sdk_root)
[runtime, client, phone, remote, share, tests].each do |target|
  target.frameworks_build_phase.add_file_reference(app_intents, true)
end

# Sort references before deriving UUIDs: insertion order must not leak into
# either the project or the scheme when Xcodeproj recreates default groups.
project.objects.grep(Xcodeproj::Project::Object::PBXGroup).each do |group|
  group.children.sort_by! { |ref| [ref.isa, ref.display_name.to_s, ref.path.to_s] }
end
project.targets.each do |target|
  target.build_phases.each do |phase|
    phase.files.sort_by! { |file| [file.display_name.to_s, file.file_ref&.path.to_s, file.product_ref&.product_name.to_s] }
  end
end
project.predictabilize_uuids
project.save
if pins
  FileUtils.mkdir_p(File.dirname(RESOLVED))
  File.write(RESOLVED, pins)
end

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, tests, launch_target: true)
scheme.test_action.should_use_launch_scheme_args_env = false
scheme.test_action.command_line_arguments = Xcodeproj::XCScheme::CommandLineArguments.new([
  { argument: '-dsh-unit-tests', enabled: true }
])
scheme.test_action.testables.each { |testable| testable.parallelizable = false }
scheme.save_as(PROJECT_PATH, 'DSH', true)
puts "Generated #{PROJECT_PATH}"
