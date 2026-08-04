# frozen_string_literal: true

module Multilocale
  # /api/phrases. Reads need the `phrases:read` scope, writes `phrases:write`.
  class Phrases
    # Server-side caps, mirrored here so a bad page size fails locally with a
    # useful message instead of being silently clamped.
    MAX_LIMIT = 2001
    MAX_SKIP = 10_000
    SORT_FIELDS = %w[_id key language].freeze

    # POST accepts an array, but a few thousand rows in one body is how you
    # meet a timeout. 200 is comfortably under it.
    DEFAULT_BATCH_SIZE = 200

    def initialize(client)
      @client = client
    end

    # Omitting `limit` returns every matching row — the server treats a missing
    # limit as unbounded, which is what a full dictionary download wants. Pass
    # `limit`/`skip` only when you actually want a page.
    def list(project: nil, language: nil, key: nil, fields: nil, limit: nil, skip: nil, sort_field: nil,
             sort_direction: nil)
      if limit && (limit.to_i < 1 || limit.to_i > MAX_LIMIT)
        raise ArgumentError, "limit must be between 1 and #{MAX_LIMIT} (got #{limit})"
      end

      if skip && (skip.to_i.negative? || skip.to_i > MAX_SKIP)
        raise ArgumentError, "skip must be between 0 and #{MAX_SKIP} (got #{skip})"
      end

      if sort_field && !SORT_FIELDS.include?(sort_field.to_s)
        raise ArgumentError, "sort_field must be one of #{SORT_FIELDS.join(', ')} (got #{sort_field})"
      end

      parameters = {
        "project" => project,
        "language" => language,
        "key" => (key && Encoding.phrase_key(key)),
        "fields" => (fields && Array(fields).join(",")),
        "limit" => limit,
        "skip" => skip,
        "sortField" => sort_field,
        "sortDirection" => sort_direction
      }

      Array(@client.get("phrases", params: parameters)).map { |attributes| Phrase.new(attributes) }
    end

    # Every row of one key, one per language.
    def find_by_key(key, project: nil)
      list(key: key, project: project)
    end

    # Creates or overwrites rows. A row with an `_id` that already exists is
    # replaced wholesale (it is an upsert, not a patch): send the whole row.
    #
    #   phrases.upsert(key: "cart.title", value: "Cart", language: "en", projects: ["website"])
    #
    # `projects` must name the key's project, otherwise the row is created but
    # no download will ever include it.
    def upsert(phrases = nil, batch_size: DEFAULT_BATCH_SIZE, **attributes)
      rows =
        if phrases.nil?
          attributes.empty? ? [] : [attributes]
        else
          phrases.is_a?(Array) ? phrases : [phrases]
        end
      return [] if rows.empty?

      rows.each_slice(batch_size).flat_map do |batch|
        payload = batch.map { |row| Phrase.to_api(row) }
        # The API answers with a bare object for a single-element body and an
        # array otherwise, so both shapes have to be handled.
        result = @client.post("phrases", body: payload.size == 1 ? payload.first : payload)
        (result.is_a?(Array) ? result : [result]).map { |attributes| Phrase.new(attributes) }
      end
    end

    def update(id, attributes)
      Phrase.new(@client.put("phrases/#{Encoding.percent_encode(id)}", body: Phrase.to_api(attributes)))
    end

    # Deletes EVERY language of `key` in `project` — a 30-locale key is 30 rows
    # gone in one call. Rows shared with other projects are deleted too, not
    # detached from this one. Returns the deleted rows.
    def delete(key:, project:)
      raise ArgumentError, "key is required" if key.nil? || key.to_s.empty?
      raise ArgumentError, "project is required" if project.nil? || project.to_s.empty?

      result = @client.delete("phrases", params: { "key" => Encoding.phrase_key(key), "project" => project })
      Array(result).map { |attributes| Phrase.new(attributes) }
    end
  end
end
