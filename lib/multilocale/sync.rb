# frozen_string_literal: true

module Multilocale
  # Moves phrases between multilocale.com and the locale files in a repository.
  #
  #   sync = Multilocale::Sync.new(client: client, config: Multilocale::ConfigFile.discover)
  #   sync.pull   # API   -> config/locales/*.yml
  #   sync.push   # files -> API
  #
  # Pull is the one to wire into a rake task or CI job; push exists so a
  # developer who edited a locale file by hand can send it back rather than
  # retyping it in the dashboard.
  class Sync
    # What a pull did, so a CLI or a rake task can report it without guessing.
    Result = Struct.new(:project, :files, :languages, :phrases, :empty_locales, keyword_init: true)

    attr_reader :client, :config, :base_dir

    def initialize(client:, config: nil, project: nil, paths: nil, nested: nil, header: nil, base_dir: nil)
      @client = client
      @config = config
      @project = project
      @paths = paths
      @nested = nested
      @header = header
      @base_dir = base_dir || config&.directory || Dir.pwd
    end

    def project
      @project || config&.project || client.project ||
        raise(ConfigurationError, <<~MESSAGE)
          No project. Pass project: to Sync.new, set "projectId" in #{ConfigFile::FILENAME},
          or export MULTILOCALE_PROJECT.
        MESSAGE
    end

    def paths
      value = @paths || config&.paths
      value = Array(value)
      return value unless value.empty?

      raise ConfigurationError, <<~MESSAGE
        No output paths. Pass paths: to Sync.new or add them to #{ConfigFile::FILENAME}:

          { "paths": ["config/locales/#{LocaleFile::PLACEHOLDER}.yml"] }
      MESSAGE
    end

    # Downloads every phrase of the project and rewrites the locale files.
    #
    # Locales the project declares but has no phrases for are reported in
    # `Result#empty_locales` and left alone: writing an empty file for them
    # would make i18n treat a missing translation as an empty string.
    def pull(languages: nil)
      # Local configuration is validated before the first request: a missing
      # path template should not cost a round trip to find out about.
      writers

      resolved = resolve_project
      rows = client.phrases.list(project: resolved.name)
      dictionaries = Dictionary.from_phrases(rows)

      wanted = languages || config&.locales || resolved.locales
      wanted = dictionaries.keys if wanted.nil? || wanted.empty?

      files = []
      empty = []

      wanted.sort.each do |language|
        dictionary = dictionaries[language]

        if dictionary.nil? || dictionary.empty?
          empty << language
          next
        end

        writers.each { |writer| files << writer.write(dictionary) }
      end

      Result.new(
        project: resolved,
        files: files,
        languages: wanted.sort - empty,
        phrases: rows.size,
        empty_locales: empty
      )
    end

    # Reads the locale files back and upserts them as phrase rows.
    #
    # Every row is sent with `projects: [name]`; a row created without it exists
    # in the organization but belongs to no project, and no download will ever
    # include it again.
    def push(languages: nil)
      resolved = resolve_project
      writer = writers.first
      wanted = languages || config&.locales || resolved.locales

      rows = wanted.flat_map do |language|
        dictionary = writer.read(language)
        next [] if dictionary.nil?

        dictionary.map do |key, value|
          { key: key, value: value, language: language, projects: [resolved.name] }
        end
      end

      client.phrases.upsert(rows)
    end

    def resolve_project
      client.projects.find(project)
    rescue NotFoundError
      raise NotFoundError.new(
        "No project #{project.inspect} in this organization. `multilocale-ruby projects` lists the ones " \
        "this credential can see.",
        status: 404
      )
    end

    private

    def writers
      @writers ||= paths.map do |path|
        LocaleFile.new(
          path_template: path,
          format: config&.format,
          nested: @nested.nil? ? (config.nil? || config.nested?) : @nested,
          header: @header || config&.header,
          base_dir: base_dir
        )
      end
    end
  end
end
