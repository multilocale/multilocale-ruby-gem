# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Multilocale::ConfigFile do
  def with_config(contents)
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "multilocale.json"), contents)
      yield directory
    end
  end

  it "reads the file the npm CLI reads" do
    with_config(<<~JSON) do |directory|
      {
        "projectId": "multilocale-ruby-example",
        "defaultLocale": "en",
        "locales": ["en", "es"],
        "paths": ["example/config/locales/%lang%.yml"]
      }
    JSON
      config = described_class.load(File.join(directory, "multilocale.json"))

      expect(config.project).to eq("multilocale-ruby-example")
      expect(config.default_locale).to eq("en")
      expect(config.locales).to eq(%w[en es])
      expect(config.paths).to eq(["example/config/locales/%lang%.yml"])
      expect(config.nested?).to be(true)
    end
  end

  it "finds the nearest config walking up, like git finds .git" do
    with_config('{"projectId":"website"}') do |directory|
      nested = File.join(directory, "app", "views")
      FileUtils.mkdir_p(nested)

      expect(described_class.discover(nested).project).to eq("website")
    end
  end

  it "returns nil when there is no config anywhere above" do
    Dir.mktmpdir { |directory| expect(described_class.discover(directory)).to be_nil }
  end

  it "answers with an empty list for missing paths instead of crashing" do
    with_config('{"projectId":"website"}') do |directory|
      config = described_class.load(File.join(directory, "multilocale.json"))

      expect(config.paths).to eq([])
      expect { config.paths! }.to raise_error(Multilocale::ConfigurationError, /%lang%/)
    end
  end

  it "says what to add when the project is missing" do
    with_config("{}") do |directory|
      config = described_class.load(File.join(directory, "multilocale.json"))

      expect { config.project! }.to raise_error(Multilocale::ConfigurationError, /projectId/)
    end
  end

  it "reports invalid JSON with the file name" do
    with_config("{ not json") do |directory|
      expect { described_class.load(File.join(directory, "multilocale.json")) }
        .to raise_error(Multilocale::ConfigurationError, /not valid JSON/)
    end
  end

  describe "the config committed in this repository" do
    let(:config) { described_class.load(File.join(GEM_ROOT, "multilocale.json")) }

    it "names a project, so no command drops into an interactive picker" do
      expect(config.project).not_to be_nil
    end

    it "points at the example application's locale directory" do
      expect(config.paths!).to eq(["example/config/locales/%lang%.yml"])
    end

    it "lists exactly the locales the example ships" do
      committed = Dir.glob(File.join(GEM_ROOT, "example/config/locales/*.yml")).map do |path|
        File.basename(path, ".yml")
      end

      expect(config.locales.sort).to eq(committed.sort)
    end
  end
end
