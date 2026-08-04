# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tmpdir"

RSpec.describe Multilocale::CLI do
  subject(:cli) { described_class.new(stdout: stdout, stderr: stderr) }

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  around do |example|
    original = ENV.to_hash
    ENV["MULTILOCALE_API_KEY"] = "s3cret"
    ENV["MULTILOCALE_API_URL"] = stub_api.url
    example.run
  ensure
    ENV.replace(original)
  end

  it "prints its version" do
    expect(cli.run(["version"])).to eq(0)
    expect(stdout.string).to include(Multilocale::VERSION)
  end

  it "prints usage with no arguments, and exits 0" do
    expect(cli.run([])).to eq(0)
    expect(stdout.string).to include("multilocale-ruby pull")
  end

  it "exits 2 on an unknown command" do
    expect(cli.run(["frobnicate"])).to eq(2)
    expect(stderr.string).to include("Unknown command")
  end

  it "lists projects" do
    stub_api.on(:get, "/api/projects") do
      [200, [{ "_id" => "1", "name" => "website", "locales" => %w[en es] }]]
    end

    expect(cli.run(["projects"])).to eq(0)
    expect(stdout.string).to include("website", "2 locales")
  end

  it "prints one language as key = value" do
    stub_api.on(:get, "/api/phrases") { [200, fixture_phrases.select { |row| row["language"] == "it" }] }

    expect(cli.run(["phrases", "--project", "multilocale-ruby-example", "--language", "it"])).to eq(0)
    expect(stdout.string).to include("nav.language = Lingua")
  end

  it "pulls into the paths from multilocale.json, with no flags" do
    stub_api.on(:get, "/api/projects/multilocale-ruby-example") do
      [200, { "_id" => "1", "name" => "multilocale-ruby-example", "locales" => %w[en es fr it] }]
    end
    stub_api.on(:get, "/api/phrases") { [200, fixture_phrases] }

    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "multilocale.json"), JSON.generate(
                                                             "projectId" => "multilocale-ruby-example",
                                                             "locales" => %w[en es fr it],
                                                             "paths" => ["config/locales/%lang%.yml"]
                                                           ))

      Dir.chdir(directory) { expect(cli.run(["pull", "--json"])).to eq(0) }

      report = JSON.parse(stdout.string)
      expect(report["phrases"]).to eq(44)
      expect(report["files"].size).to eq(4)
      expect(File.exist?(File.join(directory, "config/locales/es.yml"))).to be(true)
    end
  end

  it "falls back to MULTILOCALE_PROJECT when neither a flag nor a config file names one" do
    ENV["MULTILOCALE_PROJECT"] = "multilocale-ruby-example"
    stub_api.on(:get, "/api/phrases") { [200, fixture_phrases.select { |row| row["language"] == "es" }] }

    Dir.mktmpdir { |directory| Dir.chdir(directory) { expect(cli.run(["phrases", "--language", "es"])).to eq(0) } }

    expect(stub_api.requests.first.param("project")).to eq("multilocale-ruby-example")
  end

  it "refuses to push without --yes, because push overwrites remote rows" do
    expect(cli.run(["push"])).to eq(2)
    expect(stderr.string).to include("--yes")
  end

  it "reports an API failure as a message and exit 1, not a backtrace" do
    stub_api.on(:get, "/api/projects") { [403, { "message" => "missing scope projects:read" }] }

    expect(cli.run(["projects"])).to eq(1)
    expect(stderr.string).to include("missing scope projects:read")
  end

  it "reports a missing credential without a backtrace" do
    ENV.delete("MULTILOCALE_API_KEY")

    expect(cli.run(["projects"])).to eq(1)
    expect(stderr.string).to include("MULTILOCALE_API_KEY")
  end

  it "takes no credential on the command line, where it would leak into the process table" do
    expect(described_class::BANNER).not_to include("--api-key")
  end
end
