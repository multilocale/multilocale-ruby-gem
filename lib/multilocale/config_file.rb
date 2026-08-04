# frozen_string_literal: true

require "json"

module Multilocale
  # multilocale.json — the same file the npm CLI reads, so a repository that
  # uses both tools describes its project once.
  #
  #   {
  #     "projectId": "website",
  #     "defaultLocale": "en",
  #     "locales": ["en", "es", "fr"],
  #     "paths": ["config/locales/%lang%.yml"]
  #   }
  #
  # `projectId` accepts an id or a name, exactly like the CLI's `--project`.
  #
  # Paths are resolved relative to the config file, not to the working
  # directory: `rake` from a subdirectory writes the same files as `rake` from
  # the root. (The npm CLI resolves them against the process cwd instead.)
  class ConfigFile
    FILENAME = "multilocale.json"

    attr_reader :path, :data

    def initialize(path, data)
      @path = path
      @data = data
    end

    # Walks up from `directory` looking for multilocale.json, the way git finds
    # .git. Returns nil rather than raising: callers decide whether a missing
    # config is fatal.
    def self.discover(directory = Dir.pwd)
      current = File.expand_path(directory)

      loop do
        candidate = File.join(current, FILENAME)
        return load(candidate) if File.exist?(candidate)

        parent = File.dirname(current)
        return nil if parent == current

        current = parent
      end
    end

    def self.load(path)
      raise ConfigurationError, "No such config file: #{path}" unless File.exist?(path)

      data =
        begin
          JSON.parse(File.read(path))
        rescue JSON::ParserError => error
          raise ConfigurationError, "#{path} is not valid JSON: #{error.message}"
        end

      new(File.expand_path(path), data)
    end

    def directory
      File.dirname(path)
    end

    # Id or name. Named `projectId` in the file for CLI compatibility even
    # though a name is equally valid there.
    def project
      data["projectId"] || data["project"]
    end

    def default_locale
      data["defaultLocale"]
    end

    def locales
      data["locales"]
    end

    # The npm CLI's `import` and `unused` commands destructure this without a
    # default and crash with "Cannot read properties of undefined" when it is
    # missing; this gem answers with an empty list and lets the caller decide.
    def paths
      Array(data["paths"])
    end

    def format
      data["format"]
    end

    def header
      data["header"]
    end

    # Gem-only key. Absent from the CLI's vocabulary, which ignores unknown
    # keys, so adding it here does not break `npx multilocale`.
    def nested?
      data.fetch("nested", true)
    end

    def project!
      value = project
      if value.nil? || value.to_s.empty?
        raise ConfigurationError, <<~MESSAGE
          #{path} does not say which project it describes.

          Add the project id or name:

            { "projectId": "website", "locales": ["en", "es"], "paths": ["config/locales/%lang%.yml"] }
        MESSAGE
      end

      value
    end

    def paths!
      values = paths
      if values.empty?
        raise ConfigurationError, <<~MESSAGE
          #{path} has no "paths".

          Add at least one path template containing #{LocaleFile::PLACEHOLDER}:

            { "paths": ["config/locales/#{LocaleFile::PLACEHOLDER}.yml"] }
        MESSAGE
      end

      values
    end
  end
end
