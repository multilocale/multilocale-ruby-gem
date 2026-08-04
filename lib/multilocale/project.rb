# frozen_string_literal: true

module Multilocale
  # A project: the unit an API key is scoped to, and the thing that owns the
  # locale list every download is written from.
  #
  # The wire format is the API's camelCase document; the readers are the Ruby
  # names. `#to_h` always returns the untouched document, so a round-trip
  # through this class never drops a field the API added yesterday.
  class Project
    attr_reader :to_h

    def initialize(attributes)
      @to_h = attributes.is_a?(Project) ? attributes.to_h : (attributes || {})
    end

    def id
      @to_h["_id"]
    end

    def name
      @to_h["name"]
    end

    def organization_id
      @to_h["organizationId"]
    end

    def default_locale
      @to_h["defaultLocale"]
    end

    # The complete locale list. Updating it REPLACES it: a project update that
    # omits a locale removes it, it does not merge.
    def locales
      @to_h["locales"] || []
    end

    # Free-text translation context, prepended to every machine translation.
    def context
      @to_h["context"]
    end

    # Server-side download paths. The npm CLI resolves `project.paths ||
    # config.paths`, so a value set here wins over the local multilocale.json.
    def paths
      @to_h["paths"]
    end

    def creation_time
      @to_h["creationTime"]
    end

    def last_edit_time
      @to_h["lastEditTime"]
    end

    def [](key)
      @to_h[key.to_s]
    end

    def ==(other)
      other.is_a?(Project) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    def inspect
      "#<Multilocale::Project id=#{id.inspect} name=#{name.inspect} locales=#{locales.size}>"
    end

    ATTRIBUTE_NAMES = {
      id: "_id",
      name: "name",
      default_locale: "defaultLocale",
      locales: "locales",
      context: "context",
      paths: "paths"
    }.freeze

    # Snake_case keyword arguments -> the camelCase document the API stores.
    # String keys are passed through untouched so anything not modelled here
    # can still be sent.
    def self.to_api(attributes)
      return attributes.to_h if attributes.is_a?(Project)

      attributes.each_with_object({}) do |(key, value), document|
        document[ATTRIBUTE_NAMES[key] || key.to_s] = value
      end
    end
  end
end
