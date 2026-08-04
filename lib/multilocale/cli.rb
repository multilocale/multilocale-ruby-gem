# frozen_string_literal: true

require "json"
require "optparse"

require_relative "../multilocale"

module Multilocale
  # `multilocale-ruby` — the thin command wrapper around this gem.
  #
  # The name is not `multilocale` on purpose: that binary belongs to the npm
  # CLI (`npm i -g multilocale`), and two tools fighting over one name on PATH
  # is a support ticket nobody enjoys.
  #
  # Credentials come from the environment only. A secret passed as
  # `--api-key=…` is in the process table for every user on the machine and in
  # ~/.zsh_history forever, so there is no such flag.
  class CLI
    BANNER = <<~USAGE
      multilocale-ruby #{VERSION}

      Usage:
        multilocale-ruby pull [options]        download phrases into locale files
        multilocale-ruby push [options]        upload locale files as phrases
        multilocale-ruby projects [options]    list the projects this credential can see
        multilocale-ruby phrases [options]     print one language as key = value
        multilocale-ruby version

      Options:
        -p, --project NAME     project id or name (default: multilocale.json)
        -c, --config PATH      path to multilocale.json (default: nearest one)
            --path TEMPLATE    output path containing %lang% (repeatable)
        -l, --language LANG    restrict to one language (repeatable)
            --flat             write flat "a.b" keys instead of nested hashes
            --json             machine-readable output
            --yes              required by push, which overwrites remote rows
        -h, --help

      Environment:
        MULTILOCALE_API_KEY        API key secret (app.multilocale.com -> API keys)
        MULTILOCALE_ACCESS_TOKEN   operator session token, as an alternative
        MULTILOCALE_API_URL        override the API host
        MULTILOCALE_PROJECT        default project id or name
    USAGE

    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
    end

    # Returns a process exit status: 0 ok, 1 failure, 2 usage.
    def run(argv)
      command = argv.first

      return usage(0) if command.nil? || %w[-h --help help].include?(command)
      return version if %w[version --version -v].include?(command)

      options = parse(argv[1..] || [])

      case command
      when "pull" then pull(options)
      when "push" then push(options)
      when "projects" then projects(options)
      when "phrases" then phrases(options)
      else
        @stderr.puts("Unknown command: #{command}")
        usage(2)
      end
    rescue ConfigurationError, ApiError, ConnectionError, Error, ArgumentError => error
      @stderr.puts(error.message)
      1
    end

    private

    def parse(argv)
      options = { paths: [], languages: [] }

      parser = OptionParser.new do |parser|
        parser.banner = BANNER
        parser.on("-p", "--project NAME") { |value| options[:project] = value }
        parser.on("-c", "--config PATH") { |value| options[:config] = value }
        parser.on("--path TEMPLATE") { |value| options[:paths] << value }
        parser.on("-l", "--language LANG") { |value| options[:languages] << value }
        parser.on("--flat") { options[:flat] = true }
        parser.on("--json") { options[:json] = true }
        parser.on("--yes") { options[:yes] = true }
        parser.on("-h", "--help") { options[:help] = true }
      end

      parser.parse(argv)
      options
    end

    def usage(status)
      (status.zero? ? @stdout : @stderr).puts(BANNER)
      status
    end

    def version
      @stdout.puts("multilocale-ruby #{VERSION}")
      0
    end

    def client(options)
      # Passing `project: nil` would override the client's own MULTILOCALE_PROJECT
      # default with nil, so the keyword is only supplied when there is one.
      options[:project] ? Client.new(project: options[:project]) : Client.new
    end

    def config(options)
      return ConfigFile.load(options[:config]) if options[:config]

      ConfigFile.discover
    end

    def sync(options)
      Sync.new(
        client: client(options),
        config: config(options),
        project: options[:project],
        paths: (options[:paths].empty? ? nil : options[:paths]),
        nested: (options[:flat] ? false : nil)
      )
    end

    def pull(options)
      return usage(0) if options[:help]

      result = sync(options).pull(languages: languages(options))

      if options[:json]
        @stdout.puts(JSON.pretty_generate(
                       ok: true,
                       project: result.project.name,
                       phrases: result.phrases,
                       languages: result.languages,
                       empty_locales: result.empty_locales,
                       files: result.files
                     ))
      else
        @stdout.puts("#{result.project.name}: #{result.phrases} phrases in #{result.languages.size} languages")
        result.files.each { |file| @stdout.puts("  wrote #{relative(file)}") }
        unless result.empty_locales.empty?
          @stdout.puts("  no phrases yet for: #{result.empty_locales.join(', ')} (files left untouched)")
        end
      end

      0
    end

    def push(options)
      return usage(0) if options[:help]

      unless options[:yes]
        @stderr.puts("push overwrites the remote value of every key in the files it reads. Re-run with --yes.")
        return 2
      end

      rows = sync(options).push(languages: languages(options))

      if options[:json]
        @stdout.puts(JSON.pretty_generate(ok: true, phrases: rows.size))
      else
        @stdout.puts("pushed #{rows.size} phrases")
      end

      0
    end

    def projects(options)
      return usage(0) if options[:help]

      list = client(options).projects.list

      if options[:json]
        @stdout.puts(JSON.pretty_generate(list.map(&:to_h)))
      else
        list.sort_by { |project| project.name.to_s }.each do |project|
          @stdout.puts("#{project.name}  #{project.id}  #{project.locales.size} locales")
        end
      end

      0
    end

    def phrases(options)
      return usage(0) if options[:help]

      language = languages(options)&.first
      raise ArgumentError, "phrases needs --language" if language.nil?

      dictionary = client(options).dictionary(
        project: options[:project] || config(options)&.project,
        language: language
      )

      if options[:json]
        @stdout.puts(JSON.pretty_generate(dictionary.to_h))
      else
        dictionary.each { |key, value| @stdout.puts("#{key} = #{value}") }
      end

      0
    end

    def languages(options)
      options[:languages].empty? ? nil : options[:languages]
    end

    def relative(path)
      path.sub("#{Dir.pwd}/", "")
    end
  end
end
