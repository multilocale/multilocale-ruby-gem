# frozen_string_literal: true

require "fileutils"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Byte-compile every Ruby file, so a syntax error fails before the suite does"
task :syntax do
  # vendor/ is a local bundle install, not our code — 400 files of somebody
  # else's syntax is not this task's business.
  files = Dir.glob(["lib/**/*.rb", "spec/**/*.rb", "exe/*", "example/*.rb", "example/Rakefile"])
    .reject { |file| file.include?("vendor/") }
  broken = files.reject { |file| system(RbConfig.ruby, "-c", file, out: File::NULL) }
  raise "syntax errors in: #{broken.join(', ')}" unless broken.empty?

  puts "syntax ok (#{files.size} files)"
end

desc "Build the gem into pkg/"
task :build do
  FileUtils.mkdir_p("pkg")
  system("gem", "build", "multilocale.gemspec", "--output", "pkg/multilocale-#{version}.gem") ||
    raise("gem build failed")
end

def version
  require_relative "lib/multilocale/version"
  Multilocale::VERSION
end

task default: %i[syntax spec]
