# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Multilocale::LocaleFile do
  let(:dictionary) do
    Multilocale::Dictionary.new("es", "nav.language" => "Idioma", "greeting" => "¡Hola, %{name}!")
  end

  it "insists on a %lang% placeholder" do
    expect { described_class.new(path_template: "config/locales/es.yml") }
      .to raise_error(Multilocale::ConfigurationError, /%lang%/)
  end

  it "writes one top-level locale key, which is what the i18n gem loads" do
    yaml = described_class.new(path_template: "%lang%.yml").render(dictionary)

    expect(YAML.safe_load(yaml)).to eq(
      "es" => { "nav" => { "language" => "Idioma" }, "greeting" => "¡Hola, %{name}!" }
    )
  end

  it "does not inject a 'locale' entry the way `npx multilocale download` does" do
    yaml = described_class.new(path_template: "%lang%.yml").render(dictionary)

    expect(YAML.safe_load(yaml)["es"]).not_to have_key("locale")
  end

  it "keeps i18n interpolation placeholders intact" do
    yaml = described_class.new(path_template: "%lang%.yml").render(dictionary)

    expect(YAML.safe_load(yaml)["es"]["greeting"]).to eq("¡Hola, %{name}!")
  end

  it "keeps long sentences on one line so diffs stay readable" do
    long = "a" * 200
    yaml = described_class.new(path_template: "%lang%.yml")
      .render(Multilocale::Dictionary.new("en", "long" => long))

    expect(yaml.lines.find { |line| line.include?("long:") }).to include(long)
  end

  it "writes flat keys when asked" do
    yaml = described_class.new(path_template: "%lang%.yml", nested: false).render(dictionary)

    expect(YAML.safe_load(yaml)["es"]).to have_key("nav.language")
  end

  it "infers JSON from the extension and writes it without a locale root" do
    json = described_class.new(path_template: "%lang%.json").render(dictionary)

    expect(JSON.parse(json)).to eq("nav" => { "language" => "Idioma" }, "greeting" => "¡Hola, %{name}!")
  end

  it "refuses the npm CLI's JavaScript formats" do
    expect { described_class.new(path_template: "%lang%.js", format: :esm) }
      .to raise_error(Multilocale::ConfigurationError, /yaml, json/)
  end

  it "writes to the language's own path, relative to base_dir" do
    Dir.mktmpdir do |directory|
      file = described_class.new(path_template: "config/locales/%lang%.yml", base_dir: directory)
      path = file.write(dictionary)

      expect(path).to eq(File.join(directory, "config/locales/es.yml"))
      expect(File.read(path)).to include("Idioma")
    end
  end

  it "reads a file back into a flat dictionary" do
    Dir.mktmpdir do |directory|
      file = described_class.new(path_template: "%lang%.yml", base_dir: directory)
      file.write(dictionary)

      expect(file.read("es").to_h).to eq(dictionary.to_h)
      expect(file.read("de")).to be_nil
    end
  end

  it "prefixes the header as a YAML comment" do
    yaml = described_class.new(path_template: "%lang%.yml", header: "Generated. Do not edit.").render(dictionary)

    expect(yaml.lines.first).to eq("# Generated. Do not edit.\n")
    expect { YAML.safe_load(yaml) }.not_to raise_error
  end
end
