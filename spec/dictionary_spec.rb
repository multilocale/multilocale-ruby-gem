# frozen_string_literal: true

require "spec_helper"

RSpec.describe Multilocale::Dictionary do
  it "groups phrase rows by language" do
    dictionaries = described_class.from_phrases(fixture_phrases.map { |row| Multilocale::Phrase.new(row) })

    expect(dictionaries.keys).to contain_exactly("en", "es", "fr", "it")
    expect(dictionaries["it"]["nav.language"]).to eq("Lingua")
  end

  it "sorts entries, so a regenerated file has no incidental diff" do
    dictionary = described_class.new("en", "z" => "1", "a" => "2")

    expect(dictionary.keys).to eq(%w[a z])
  end

  it "nests dotted keys, because i18n resolves t('a.b') by walking hashes" do
    dictionary = described_class.new("en", "cart.title" => "Cart", "cart.items.one" => "1 item", "hello" => "Hi")

    expect(dictionary.nested).to eq(
      "cart" => { "title" => "Cart", "items" => { "one" => "1 item" } },
      "hello" => "Hi"
    )
  end

  it "reports a key that is both a value and a namespace instead of dropping one" do
    dictionary = described_class.new("en", "cart" => "Cart", "cart.title" => "Your cart")

    expect { dictionary.nested }.to raise_error(Multilocale::Error, /collision/)
  end

  it "flattens a nested tree back into phrase keys" do
    tree = { "cart" => { "title" => "Cart", "items" => { "one" => "1 item" } }, "hello" => "Hi" }

    expect(described_class.flatten(tree)).to eq(
      "cart.title" => "Cart",
      "cart.items.one" => "1 item",
      "hello" => "Hi"
    )
  end

  it "round-trips nesting and flattening" do
    dictionary = described_class.new("en", "a.b.c" => "1", "a.b.d" => "2", "e" => "3")

    expect(described_class.flatten(dictionary.nested)).to eq(dictionary.to_h)
  end

  it "is enumerable" do
    dictionary = described_class.new("en", "a" => "1", "b" => "2")

    expect(dictionary.map { |key, value| "#{key}=#{value}" }).to eq(%w[a=1 b=2])
    expect(dictionary.size).to eq(2)
    expect(described_class.new("en")).to be_empty
  end
end
