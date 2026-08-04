# frozen_string_literal: true

module Multilocale
  # One `{key, value, language}` row. A key translated into 12 locales is 12
  # phrases, not one phrase with 12 values — every API call and every error
  # message counts rows, not keys.
  #
  # A row can belong to several projects at once (`projects`). Editing it edits
  # it for all of them, and deleting a key deletes every row it matches
  # including the shared ones.
  class Phrase
    attr_reader :to_h

    def initialize(attributes)
      @to_h = attributes.is_a?(Phrase) ? attributes.to_h : (attributes || {})
    end

    def id
      @to_h["_id"]
    end

    def key
      @to_h["key"]
    end

    def value
      @to_h["value"]
    end

    def language
      @to_h["language"]
    end

    def projects
      @to_h["projects"] || []
    end

    def projects_ids
      @to_h["projectsIds"] || []
    end

    def organization_id
      @to_h["organizationId"]
    end

    # `googleTranslate` is the pre-2024 spelling and is still the only
    # provenance flag on older rows, so a reader that only looks at
    # `machineTranslated` reports human-written text that never was.
    def machine_translated?
      value = @to_h.fetch("machineTranslated") { @to_h["googleTranslate"] }
      !!value
    end

    # Which engine produced it, when it was machine translated.
    def model
      @to_h["model"]
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
      other.is_a?(Phrase) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    def inspect
      "#<Multilocale::Phrase key=#{key.inspect} language=#{language.inspect} value=#{value.inspect}>"
    end

    ATTRIBUTE_NAMES = {
      id: "_id",
      key: "key",
      value: "value",
      language: "language",
      projects: "projects",
      projects_ids: "projectsIds",
      machine_translated: "machineTranslated",
      model: "model"
    }.freeze

    def self.to_api(attributes)
      return attributes.to_h if attributes.is_a?(Phrase)

      attributes.each_with_object({}) do |(key, value), document|
        document[ATTRIBUTE_NAMES[key] || key.to_s] = value
      end
    end
  end
end
