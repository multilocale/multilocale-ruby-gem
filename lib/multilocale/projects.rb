# frozen_string_literal: true

module Multilocale
  # /api/projects. Reads need the `projects:read` scope, writes `projects:write`.
  class Projects
    def initialize(client)
      @client = client
    end

    # Every project the credential can see. A project-scoped API key sees
    # exactly one — the server filters the list, it does not 403.
    def list
      Array(@client.get("projects")).map { |attributes| Project.new(attributes) }
    end

    # Accepts an id (24 hex characters) or a name. Names are unique per
    # organization, not globally, and the credential supplies the organization.
    def find(id_or_name)
      raise ConfigurationError, "Project id or name required" if id_or_name.nil? || id_or_name.to_s.empty?

      Project.new(@client.get("projects/#{Encoding.percent_encode(id_or_name)}"))
    end

    # Returns nil instead of raising when there is no such project.
    def find_by(id_or_name)
      find(id_or_name)
    rescue NotFoundError
      nil
    end

    # create(name: "website", default_locale: "en", locales: %w[en es fr])
    def create(attributes)
      Project.new(@client.post("projects", body: Project.to_api(attributes)))
    end

    # `locales:` is a REPLACEMENT, not a merge. Read the project first and send
    # the full list, or you will silently drop the locales you left out.
    def update(id, attributes)
      Project.new(@client.put("projects/#{Encoding.percent_encode(id)}", body: Project.to_api(attributes)))
    end
  end
end
