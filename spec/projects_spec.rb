# frozen_string_literal: true

require "spec_helper"

RSpec.describe Multilocale::Projects do
  let(:document) do
    {
      "_id" => "6a1f9c2b4d8e70135f2ab901",
      "name" => "multilocale-ruby-example",
      "organizationId" => "b2c4d6e8f0a1c3e5d7b9f102",
      "defaultLocale" => "en",
      "locales" => %w[en es fr it],
      "context" => "A demo application."
    }
  end

  it "lists projects" do
    stub_api.on(:get, "/api/projects") { [200, [document]] }

    projects = client.projects.list

    expect(projects.map(&:name)).to eq(["multilocale-ruby-example"])
    expect(projects.first.locales).to eq(%w[en es fr it])
    expect(projects.first.default_locale).to eq("en")
    expect(projects.first.organization_id).to eq("b2c4d6e8f0a1c3e5d7b9f102")
  end

  it "finds a project by name" do
    stub_api.on(:get, "/api/projects/multilocale-ruby-example") { [200, document] }

    expect(client.projects.find("multilocale-ruby-example").id).to eq("6a1f9c2b4d8e70135f2ab901")
  end

  it "escapes a name with characters that would otherwise change the path" do
    stub_api.on(:get, "/api/projects/marketing%2Fsite") { [200, document] }

    client.projects.find("marketing/site")

    expect(stub_api.requests.first.path).to eq("/api/projects/marketing%2Fsite")
  end

  it "returns nil from find_by rather than raising for a missing project" do
    stub_api.on(:get, "/api/projects/nope") { [404, { "message" => "not found" }] }

    expect(client.projects.find_by("nope")).to be_nil
  end

  it "creates a project from snake_case keywords" do
    stub_api.on(:post, "/api/projects") { |request| [200, request.json.merge("_id" => "new")] }

    project = client.projects.create(name: "website", default_locale: "en", locales: %w[en es])

    expect(project.id).to eq("new")
    expect(stub_api.requests.first.json).to eq("name" => "website", "defaultLocale" => "en", "locales" => %w[en es])
  end

  it "updates a project" do
    stub_api.on(:put, "/api/projects/6a1f9c2b4d8e70135f2ab901") { |request| [200, document.merge(request.json)] }

    project = client.projects.update("6a1f9c2b4d8e70135f2ab901", locales: %w[en es fr it pt])

    expect(project.locales).to eq(%w[en es fr it pt])
  end

  it "keeps unknown server fields on the round trip" do
    project = Multilocale::Project.new(document.merge("somethingNew" => 42))

    expect(Multilocale::Project.to_api(project)["somethingNew"]).to eq(42)
    expect(project["somethingNew"]).to eq(42)
  end
end
