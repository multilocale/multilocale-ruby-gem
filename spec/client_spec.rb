# frozen_string_literal: true

require "spec_helper"

RSpec.describe Multilocale::Client do
  describe "authentication" do
    it "sends the key secret as Basic base64(secret), with no colon" do
      stub_api.on(:get, "/api/projects") { [200, []] }

      client(api_key: "sk_live_example").projects.list

      authorization = stub_api.requests.first.headers["authorization"]
      expect(authorization).to eq("Basic #{['sk_live_example'].pack('m0')}")
      expect(authorization.split(" ").last.unpack1("m0")).to eq("sk_live_example")
      expect(authorization).not_to include(":")
    end

    it "sends an operator session token as Token base64(token)" do
      stub_api.on(:get, "/api/projects") { [200, []] }

      client(api_key: nil, access_token: "jwt.header.payload").projects.list

      expect(stub_api.requests.first.headers["authorization"]).to eq("Token #{['jwt.header.payload'].pack('m0')}")
    end

    it "prefers the API key when both are given" do
      stub_api.on(:get, "/api/projects") { [200, []] }

      client(api_key: "key", access_token: "token").projects.list

      expect(stub_api.requests.first.headers["authorization"]).to start_with("Basic ")
    end

    it "refuses to build without a credential, and says how to get one" do
      expect { described_class.new(api_key: nil, access_token: nil) }
        .to raise_error(Multilocale::ConfigurationError, /MULTILOCALE_API_KEY/)
    end

    it "treats a blank credential as no credential" do
      expect { described_class.new(api_key: "  ", access_token: nil) }
        .to raise_error(Multilocale::ConfigurationError)
    end

    it "keeps the credential out of inspect output" do
      instance = client(api_key: "sk_live_secret")

      expect(instance.inspect).not_to include("sk_live_secret")
      expect(instance.inspect).to include("api_key")
    end
  end

  describe "requests" do
    it "identifies itself and asks for JSON" do
      stub_api.on(:get, "/api/projects") { [200, []] }

      client.projects.list

      headers = stub_api.requests.first.headers
      expect(headers["user-agent"]).to match(%r{\Amultilocale-ruby/#{Multilocale::VERSION} })
      expect(headers["accept"]).to eq("application/json")
    end

    it "sends a JSON body with a JSON content type on writes" do
      stub_api.on(:post, "/api/projects") { |request| [200, request.json] }

      client.projects.create(name: "website", default_locale: "en", locales: %w[en es])

      request = stub_api.requests.first
      expect(request.headers["content-type"]).to eq("application/json")
      expect(request.json).to eq("name" => "website", "defaultLocale" => "en", "locales" => %w[en es])
    end
  end

  describe "error mapping" do
    {
      401 => Multilocale::AuthenticationError,
      403 => Multilocale::PermissionError,
      404 => Multilocale::NotFoundError,
      429 => Multilocale::RateLimitedError,
      500 => Multilocale::ServerError,
      503 => Multilocale::ServerError
    }.each do |status, error_class|
      it "raises #{error_class} for #{status}" do
        stub_api.on(:get, "/api/projects") { [status, { "status" => status, "message" => "nope" }] }

        expect { client.projects.list }.to raise_error(error_class) do |error|
          expect(error.status).to eq(status)
          expect(error.message).to include("nope")
        end
      end
    end

    it "explains the Basic-base64(secret) scheme on 401, where everyone gets it wrong" do
      stub_api.on(:get, "/api/projects") { [401, { "message" => "Unauthorized" }] }

      expect { client.projects.list }.to raise_error(/base64\(secret\)/)
    end

    it "names scopes on 403" do
      stub_api.on(:get, "/api/projects") { [403, { "message" => "Forbidden" }] }

      expect { client.projects.list }.to raise_error(/scope/)
    end

    it "survives an error body that is not JSON" do
      stub_api.on(:get, "/api/projects") { [500, "<html>gateway</html>"] }

      expect { client.projects.list }.to raise_error(Multilocale::ServerError, /HTTP 500/)
    end
  end

  describe "retries" do
    it "retries a 429 and returns the eventual success" do
      calls = 0
      stub_api.on(:get, "/api/projects") do
        calls += 1
        calls == 1 ? [429, { "message" => "slow down" }] : [200, [{ "_id" => "1", "name" => "website" }]]
      end

      projects = client(max_retries: 2, retry_backoff: 0.01).projects.list

      expect(calls).to eq(2)
      expect(projects.first.name).to eq("website")
    end

    it "gives up after the retry budget and raises the last status" do
      stub_api.on(:get, "/api/projects") { [503, { "message" => "unavailable" }] }

      expect { client(max_retries: 1, retry_backoff: 0.01).projects.list }
        .to raise_error(Multilocale::ServerError)
      expect(stub_api.requests.size).to eq(2)
    end

    it "does not retry a 4xx the caller has to fix" do
      stub_api.on(:get, "/api/projects") { [403, { "message" => "no scope" }] }

      expect { client(max_retries: 3, retry_backoff: 0.01).projects.list }
        .to raise_error(Multilocale::PermissionError)
      expect(stub_api.requests.size).to eq(1)
    end

    it "raises ConnectionError when nothing answers" do
      unreachable = described_class.new(api_key: "k", api_url: "http://127.0.0.1:1", max_retries: 0)

      expect { unreachable.projects.list }.to raise_error(Multilocale::ConnectionError, /GET/)
    end
  end

  describe "#dictionary" do
    it "returns one language as a flat key => value map" do
      stub_api.on(:get, "/api/phrases") do
        [200, fixture_phrases.select { |row| row["language"] == "es" }]
      end

      dictionary = client.dictionary(project: "multilocale-ruby-example", language: "es")

      expect(dictionary.language).to eq("es")
      expect(dictionary["nav.language"]).to eq("Idioma")
      expect(stub_api.requests.first.param("language")).to eq("es")
      expect(stub_api.requests.first.param("project")).to eq("multilocale-ruby-example")
    end
  end

  describe "#project_name" do
    it "passes a name straight through, without a lookup" do
      expect(client.project_name("website")).to eq("website")
      expect(stub_api.requests).to be_empty
    end

    it "resolves a 24-hex id to the name the phrases endpoints filter on" do
      stub_api.on(:get, "/api/projects/6a1f9c2b4d8e70135f2ab901") do
        [200, { "_id" => "6a1f9c2b4d8e70135f2ab901", "name" => "website" }]
      end

      expect(client.project_name("6a1f9c2b4d8e70135f2ab901")).to eq("website")
    end
  end
end
