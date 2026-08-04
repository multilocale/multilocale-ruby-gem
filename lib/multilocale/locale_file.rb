# frozen_string_literal: true

require "fileutils"
require "json"
require "yaml"

module Multilocale
  # Reads and writes the locale files on disk.
  #
  # The path is a template containing `%lang%`, the same convention the npm CLI
  # uses in multilocale.json:
  #
  #   config/locales/%lang%.yml  ->  config/locales/en.yml, config/locales/es.yml, …
  #
  # YAML is written the way the i18n gem expects it: a single top-level locale
  # key, nested below it. Two differences from `npx multilocale download` are
  # deliberate and both matter to Ruby:
  #
  #   * no injected "locale" entry. The CLI writes one into every dictionary it
  #     generates (only its Swift writer strips it again); in a Rails locale
  #     file it would surface as the translation `t("locale")`.
  #   * dotted keys are nested, because i18n resolves them by walking hashes.
  class LocaleFile
    FORMATS = %i[yaml json].freeze
    PLACEHOLDER = "%lang%"

    attr_reader :path_template, :format, :nested, :header, :base_dir

    def initialize(path_template:, format: nil, nested: true, header: nil, base_dir: Dir.pwd)
      unless path_template.to_s.include?(PLACEHOLDER)
        raise ConfigurationError, "Path #{path_template.inspect} must contain #{PLACEHOLDER}, e.g. " \
                                  "config/locales/#{PLACEHOLDER}.yml"
      end

      @path_template = path_template.to_s
      @format = (format || self.class.infer_format(@path_template)).to_sym

      unless FORMATS.include?(@format)
        raise ConfigurationError,
              "Unsupported format #{@format.inspect} (supported: #{FORMATS.join(', ')}). " \
              "The npm CLI's cjs/esm/js/swift writers have no equivalent here."
      end

      @nested = nested
      @header = header
      @base_dir = base_dir
    end

    def self.infer_format(path)
      case File.extname(path).downcase
      when ".json" then :json
      else :yaml
      end
    end

    def path_for(language)
      File.expand_path(path_template.gsub(PLACEHOLDER, language.to_s), base_dir)
    end

    # Writes one language and returns the absolute path written.
    def write(dictionary)
      path = path_for(dictionary.language)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, render(dictionary))
      path
    end

    def render(dictionary)
      body = nested ? dictionary.nested : dictionary.to_h

      case format
      when :yaml
        # line_width: -1 keeps long sentences on one line; wrapped YAML is
        # valid but re-wraps on every unrelated edit and ruins the diff.
        "#{yaml_header}#{{ dictionary.language.to_s => body }.to_yaml(line_width: -1)}"
      else
        # JSON has no comment syntax, so `header` is deliberately dropped here
        # rather than written as an invalid first line.
        "#{JSON.pretty_generate(body)}\n"
      end
    end

    # Reads one language file back into a Dictionary, flattening the nesting.
    # Returns nil when the file does not exist.
    def read(language)
      path = path_for(language)
      return nil unless File.exist?(path)

      raw = File.read(path)
      document =
        case format
        when :yaml then YAML.safe_load(raw) || {}
        else JSON.parse(raw)
        end

      # A locale file is `{ "en" => { … } }`; anything else is either already
      # flat or someone else's file, and is taken as it comes.
      body =
        if document.is_a?(Hash) && document.size == 1 && document.key?(language.to_s)
          document[language.to_s]
        else
          document
        end

      Dictionary.new(language.to_s, Dictionary.flatten(body))
    end

    private

    def yaml_header
      return "" if header.nil? || header.to_s.empty?

      header.to_s.lines.map { |line| line.start_with?("#") ? line : "# #{line}" }.join.then do |comment|
        comment.end_with?("\n") ? comment : "#{comment}\n"
      end
    end
  end
end
