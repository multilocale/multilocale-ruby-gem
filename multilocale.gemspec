# frozen_string_literal: true

require_relative "lib/multilocale/version"

Gem::Specification.new do |spec|
  spec.name = "multilocale"
  spec.version = Multilocale::VERSION
  spec.authors = ["Multilocale"]
  spec.email = ["support@multilocale.com"]

  spec.summary = "Ruby client for the Multilocale translation API"
  spec.description = <<~DESCRIPTION
    Reads and writes projects and phrases on multilocale.com over its REST API,
    and syncs them into the locale files the i18n gem (and Rails) already read.
    No runtime dependencies.
  DESCRIPTION

  spec.homepage = "https://www.multilocale.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/multilocale/multilocale-ruby-gem",
    "changelog_uri" => "https://github.com/multilocale/multilocale-ruby-gem/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://www.multilocale.com/developers/",
    "bug_tracker_uri" => "https://github.com/multilocale/multilocale-ruby-gem/issues",
    "rubygems_mfa_required" => "true"
  }

  # Globbed rather than `git ls-files`: the gem is built from a mirror of a
  # monorepo directory and from CI checkouts, and neither is guaranteed to be a
  # git repository rooted here.
  spec.files = Dir.chdir(__dir__) do
    Dir.glob(["lib/**/*.rb", "exe/*", "README.md", "CHANGELOG.md", "LICENSE"]).select { |path| File.file?(path) }
  end

  spec.bindir = "exe"
  # Not "multilocale": that binary is the npm CLI's.
  spec.executables = ["multilocale-ruby"]
  spec.require_paths = ["lib"]
end
