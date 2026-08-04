# frozen_string_literal: true

require "spec_helper"

RSpec.describe Multilocale::Phrases do
  describe "#list" do
    it "maps rows onto Phrase objects" do
      stub_api.on(:get, "/api/phrases") { [200, fixture_phrases.first(3)] }

      phrases = client.phrases.list(project: "multilocale-ruby-example")

      expect(phrases.map(&:key)).to eq(%w[app.title app.tagline nav.language])
      expect(phrases.first.projects).to eq(["multilocale-ruby-example"])
    end

    it "omits the parameters it was not given, so a bare list stays unbounded" do
      stub_api.on(:get, "/api/phrases") { [200, []] }

      client.phrases.list(project: "website")

      request = stub_api.requests.first
      expect(request.query).to eq("project=website")
    end

    it "URL-encodes the phrase key on top of the transport encoding" do
      stub_api.on(:get, "/api/phrases") { [200, []] }

      client.phrases.list(key: "discount.100%_off")

      # The API decodes the query string and then calls decodeURIComponent on
      # the result, so the wire value has to be double-encoded to survive.
      raw = stub_api.requests.first.raw_param("key")
      expect(raw).to eq("discount.100%2525_off")
      expect(stub_api.requests.first.param("key")).to eq("discount.100%25_off")
    end

    it "rejects a page size the server would silently clamp" do
      expect { client.phrases.list(limit: 5000) }.to raise_error(ArgumentError, /2001/)
      expect { client.phrases.list(skip: 20_000) }.to raise_error(ArgumentError, /10000/)
      expect { client.phrases.list(sort_field: "value") }.to raise_error(ArgumentError, /_id, key, language/)
    end

    it "passes paging and sorting through in the server's spelling" do
      stub_api.on(:get, "/api/phrases") { [200, []] }

      client.phrases.list(limit: 100, skip: 200, sort_field: "key", sort_direction: "DESC", fields: %w[key value])

      request = stub_api.requests.first
      expect(request.param("limit")).to eq("100")
      expect(request.param("skip")).to eq("200")
      expect(request.param("sortField")).to eq("key")
      expect(request.param("sortDirection")).to eq("DESC")
      expect(request.param("fields")).to eq("key,value")
    end
  end

  describe "#upsert" do
    it "sends a bare object for one row and unwraps the bare object back" do
      stub_api.on(:post, "/api/phrases") { |request| [200, request.json] }

      phrases = client.phrases.upsert(key: "cart.title", value: "Cart", language: "en", projects: ["website"])

      expect(stub_api.requests.first.json).to be_a(Hash)
      expect(phrases.map(&:key)).to eq(["cart.title"])
    end

    it "sends an array for several rows" do
      stub_api.on(:post, "/api/phrases") { |request| [200, request.json] }

      rows = [
        { key: "cart.title", value: "Cart", language: "en", projects: ["website"] },
        { key: "cart.title", value: "Carrito", language: "es", projects: ["website"] }
      ]

      expect(client.phrases.upsert(rows).size).to eq(2)
      expect(stub_api.requests.first.json).to be_an(Array)
    end

    it "translates snake_case attributes into the camelCase document" do
      stub_api.on(:post, "/api/phrases") { |request| [200, request.json] }

      client.phrases.upsert(key: "a", value: "b", language: "en", machine_translated: true, projects_ids: ["1"])

      expect(stub_api.requests.first.json.keys).to include("machineTranslated", "projectsIds")
    end

    it "batches large uploads instead of sending one enormous body" do
      stub_api.on(:post, "/api/phrases") { |request| [200, request.json] }

      rows = Array.new(5) { |index| { key: "k#{index}", value: "v", language: "en", projects: ["website"] } }
      client.phrases.upsert(rows, batch_size: 2)

      expect(stub_api.requests.size).to eq(3)
    end
  end

  describe "#update" do
    it "puts to the row's own path" do
      stub_api.on(:put, "/api/phrases/abc123") { |request| [200, request.json.merge("_id" => "abc123")] }

      phrase = client.phrases.update("abc123", value: "Updated")

      expect(phrase.id).to eq("abc123")
      expect(stub_api.requests.first.json).to eq("value" => "Updated")
    end
  end

  describe "#delete" do
    it "deletes every language of one key and returns the removed rows" do
      stub_api.on(:delete, "/api/phrases") do
        [200, fixture_phrases.select { |row| row["key"] == "footer.docs" }]
      end

      deleted = client.phrases.delete(key: "footer.docs", project: "multilocale-ruby-example")

      expect(deleted.map(&:language)).to contain_exactly("en", "es", "fr", "it")
      expect(stub_api.requests.first.param("project")).to eq("multilocale-ruby-example")
    end

    it "refuses to guess a missing key or project" do
      expect { client.phrases.delete(key: "", project: "website") }.to raise_error(ArgumentError, /key/)
      expect { client.phrases.delete(key: "a", project: nil) }.to raise_error(ArgumentError, /project/)
    end

    it "raises NotFoundError when nothing matched" do
      stub_api.on(:delete, "/api/phrases") { [404, {}] }

      expect { client.phrases.delete(key: "missing", project: "website") }
        .to raise_error(Multilocale::NotFoundError)
    end
  end

  describe Multilocale::Phrase do
    it "reads the legacy googleTranslate flag as machine-translation provenance" do
      legacy = fixture_phrases.find { |row| row["googleTranslate"] }

      expect(legacy).not_to be_nil
      expect(described_class.new(legacy)).to be_machine_translated
      expect(described_class.new(legacy)["machineTranslated"]).to be_nil
    end

    it "reports human-written rows as not machine translated" do
      row = fixture_phrases.find { |candidate| candidate["language"] == "en" }

      expect(described_class.new(row)).not_to be_machine_translated
    end
  end
end
