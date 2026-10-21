require 'json'
require 'xcodeproj'

# The runner owns this checkout. Keep distribution profiles out of the committed project.
profiles = JSON.parse(File.read(File.join(ENV.fetch('RUNNER_TEMP'), 'dotlings-signing', 'profiles.json')))
project = Xcodeproj::Project.open('Dots.xcodeproj')
expected = {'Dots' => 'com.jasonmiller.dots', 'DotsWidget' => 'com.jasonmiller.dots.widget'}
expected.each do |name, bundle_id|
  target = project.targets.find { |item| item.name == name }
  raise "Missing target #{name}" unless target
  release = target.build_configurations.find { |item| item.name == 'Release' }
  settings = release.build_settings
  raise "Unexpected bundle ID for #{name}" unless settings['PRODUCT_BUNDLE_IDENTIFIER'] == bundle_id
  settings['DEVELOPMENT_TEAM'] = ENV.fetch('APPLE_TEAM_ID')
  settings['CODE_SIGN_STYLE'] = 'Manual'
  settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  settings['PROVISIONING_PROFILE_SPECIFIER'] = profiles.fetch(bundle_id)
end
project.save
puts 'Distribution signing configured for the app and widget'
