require 'xcodeproj'
require 'json'
root = File.expand_path('../../..', __dir__)
p = Xcodeproj::Project.open(File.join(root, 'Dots.xcodeproj'))
suffixes = %w[Idle MoveRight MoveLeft Wave Jump Disappointed Waiting Thinking Reviewing LookAround]
JSON.parse(File.read(File.join(__dir__, 'catalog.json'))).each do |c|
  suffixes.each do |suffix|
    path = "Resources/Companion#{c['id'].capitalize}Motion#{suffix}.png"
    ref = p.files.find { |f| f.path == path } || p.main_group.new_file(path)
    p.targets.each do |target|
      phase = target.resources_build_phase
      phase.add_file_reference(ref) unless phase.files_references.include?(ref)
    end
  end
end
p.save
puts 'Registered 290 animation strips for app and widget.'
