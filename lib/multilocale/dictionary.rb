# frozen_string_literal: true

module Multilocale
  # One language's phrases as a flat `key => value` map, plus the conversion
  # the Ruby i18n gem needs.
  #
  # Multilocale stores keys flat. The i18n gem resolves `t("cart.title")` by
  # splitting on dots and walking nested hashes, so a flat YAML key
  # `"cart.title": Cart` is NOT found at runtime — it has to be nested on the
  # way out and flattened again on the way in. That translation is this class.
  class Dictionary
    include Enumerable

    attr_reader :language, :entries

    def initialize(language, entries = {})
      @language = language
      @entries = entries.sort_by { |key, _| key.to_s }.to_h
    end

    # { "en" => Dictionary, "es" => Dictionary, … } from a flat list of rows.
    def self.from_phrases(phrases)
      phrases.each_with_object({}) { |phrase, grouped|
        (grouped[phrase.language] ||= {})[phrase.key] = phrase.value
      }.map { |language, entries| [language, new(language, entries)] }.to_h
    end

    def [](key)
      entries[key.to_s]
    end

    def each(&block)
      entries.each(&block)
    end

    def size
      entries.size
    end

    def empty?
      entries.empty?
    end

    def keys
      entries.keys
    end

    def to_h
      entries
    end

    # Dotted keys become nested hashes, which is what i18n (and Rails) read.
    # `cart.title` and `cart` cannot both be keys — one would have to be both a
    # string and a hash — so that collision is reported rather than silently
    # dropping one of them.
    def nested
      entries.each_with_object({}) do |(key, value), tree|
        path = key.to_s.split(".")
        leaf = path.pop
        node = tree

        path.each_with_index do |segment, index|
          node[segment] ||= {}
          unless node[segment].is_a?(Hash)
            raise Error, "Key collision in #{language}: #{path[0..index].join('.')} is both a value and a namespace " \
                         "(#{key})"
          end

          node = node[segment]
        end

        if node[leaf].is_a?(Hash)
          raise Error, "Key collision in #{language}: #{key} is both a value and a namespace"
        end

        node[leaf] = value
      end
    end

    # The inverse of #nested: what a locale file read from disk has to go
    # through before it can be pushed back as phrase rows.
    def self.flatten(tree, prefix = nil)
      tree.each_with_object({}) do |(key, value), flat|
        path = [prefix, key].compact.join(".")

        if value.is_a?(Hash)
          flat.merge!(flatten(value, path))
        else
          flat[path] = value
        end
      end
    end
  end
end
