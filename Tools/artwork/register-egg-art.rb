require 'xcodeproj'
require 'json'
root = File.expand_path('../..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'Dots.xcodeproj'))
ids = JSON.parse(File.read(File.join(root, 'Art/CollectionMotion/v001/catalog.json'))).map { |c| c['id'] }
assets = %w[EggWakingStrip EggCrackingStrip] + ids.map { |id| "EggHatch#{id.capitalize}Strip" }
assets.each do |asset|
  path = "Resources/#{asset}.png"
  ref = project.files.find { |f| f.path == path } || project.main_group.new_file(path)
  project.targets.each do |target|
    phase = target.resources_build_phase
    phase.add_file_reference(ref) unless phase.files_references.include?(ref)
  end
end
project.save
puts "Registered #{assets.count} approved egg strips."
