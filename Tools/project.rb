require 'xcodeproj'
require 'fileutils'

# Regenerates the checked-in Xcode project without changing source or signing credentials.
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'Dots.xcodeproj'))
app = project.new_target(:application, 'Dots', :ios, '18.0')
widget = project.new_target(:app_extension, 'DotsWidget', :ios, '18.0')
shared = Dir[File.join(root, 'Shared/*.swift')].sort.map { |path| project.main_group.new_file(path.delete_prefix(root + '/')) }
[[app, 'Dots'], [widget, 'DotsWidget']].each do |target, folder|
  files = Dir[File.join(root, folder, '*.swift')].sort.map { |path| project.main_group.new_file(path.delete_prefix(root + '/')) }
  target.add_file_references(shared + files)
  resource = project.main_group.new_file('Resources')
  resource.last_known_file_type = 'folder'
  target.resources_build_phase.add_file_reference(resource)
  target.build_configurations.each do |configuration|
    s = configuration.build_settings
    s['SWIFT_VERSION'] = '5.0'
    s['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = folder == 'Dots' ? 'com.jasonmiller.dots' : 'com.jasonmiller.dots.widget'
    s['INFOPLIST_FILE'] = "#{folder}/Info.plist"
    s['CODE_SIGN_ENTITLEMENTS'] = "#{folder}/#{folder}.entitlements"
    s['CODE_SIGN_STYLE'] = 'Automatic'
    s['MARKETING_VERSION'] = '1.0'
    s['CURRENT_PROJECT_VERSION'] = '1'
    s['TARGETED_DEVICE_FAMILY'] = '1'
    s['SUPPORTS_MACCATALYST'] = 'NO'
    s['SDKROOT'] = 'iphoneos'
    s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon' if folder == 'Dots'
    s['APPLICATION_EXTENSION_API_ONLY'] = 'YES' if folder == 'DotsWidget'
    s['SKIP_INSTALL'] = folder == 'Dots' ? 'NO' : 'YES'
    s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  end
end
project.files.select { |file| file.path&.end_with?('Foundation.framework') }.each do |file|
  file.path = 'System/Library/Frameworks/Foundation.framework'
  file.source_tree = 'SDKROOT'
end
app.resources_build_phase.add_file_reference(project.main_group.new_file('Dots/Assets.xcassets'))
app.add_dependency(widget)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(widget.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'Dots', true)
puts 'Generated Dots.xcodeproj'
