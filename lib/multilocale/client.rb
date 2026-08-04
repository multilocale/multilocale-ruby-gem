# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Multilocale
  # HTTP client for the Multilocale REST API (https://api.multilocale.com).
  #
  #   client = Multilocale::Client.new(api_key: ENV["MULTILOCALE_API_KEY"])
  #   client.projects.list
  #   client.dictionary(project: "website", language: "es")
  #
  # Authentication is `Authorization: Basic base64(secret)` — the API key
  # secret on its own, base64'd, with no key/secret pair and no colon. The
  # secret selects both the organization and the project, so there is no
  # tenant parameter to pass and no way for a key to reach another project.
  class Client
    DEFAULT_API_URL = "https://api.multilocale.com"
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 2
    DEFAULT_RETRY_BACKOFF = 0.5

    # 429 and 5xx are the transient ones. 4xx is the caller's problem and
    # retrying it only burns rate limit.
    RETRIABLE_STATUSES = [429, 500, 502, 503, 504].freeze
    RETRIABLE_EXCEPTIONS = [
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      EOFError,
      IOError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      SocketError
    ].freeze

    attr_reader :api_url, :project, :open_timeout, :read_timeout, :max_retries, :retry_backoff, :user_agent

    # @param api_key [String] REST API key secret, from app.multilocale.com → API keys
    # @param access_token [String] operator session token, the alternative the
    #   dashboard and the npm CLI use (`Authorization: Token base64(token)`).
    #   Prefer an API key for anything automated: it is scoped and revocable.
    # @param project [String] default project id or name for calls that take one
    def initialize(
      api_key: ENV.fetch("MULTILOCALE_API_KEY", nil),
      access_token: ENV.fetch("MULTILOCALE_ACCESS_TOKEN", nil),
      api_url: ENV.fetch("MULTILOCALE_API_URL", DEFAULT_API_URL),
      project: ENV.fetch("MULTILOCALE_PROJECT", nil),
      open_timeout: DEFAULT_OPEN_TIMEOUT,
      read_timeout: DEFAULT_READ_TIMEOUT,
      max_retries: DEFAULT_MAX_RETRIES,
      retry_backoff: DEFAULT_RETRY_BACKOFF,
      user_agent: nil,
      logger: nil
    )
      api_key = nil if api_key.nil? || api_key.to_s.strip.empty?
      access_token = nil if access_token.nil? || access_token.to_s.strip.empty?

      if api_key.nil? && access_token.nil?
        raise ConfigurationError, <<~MESSAGE
          No Multilocale credential.

          Create an API key at https://app.multilocale.com/keys and export it:

            export MULTILOCALE_API_KEY=<the key secret>

          or pass one explicitly: Multilocale::Client.new(api_key: "…").
        MESSAGE
      end

      @api_key = api_key
      @access_token = access_token
      @api_url = api_url.to_s.sub(%r{/+\z}, "")
      @project = project
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @max_retries = max_retries
      @retry_backoff = retry_backoff
      @user_agent = user_agent || "multilocale-ruby/#{VERSION} (ruby #{RUBY_VERSION})"
      @logger = logger
    end

    def projects
      @projects ||= Projects.new(self)
    end

    def phrases
      @phrases ||= Phrases.new(self)
    end

    # One language of one project as a flat key => value dictionary.
    #
    # `project:` falls back to the client's own when it is nil, rather than
    # defaulting in the signature: callers forward an optional value here, and
    # `project: nil` would otherwise silently defeat the default.
    def dictionary(language:, project: nil)
      Dictionary.new(
        language,
        phrases.list(project: project_name(project || @project), language: language)
          .each_with_object({}) { |phrase, entries| entries[phrase.key] = phrase.value }
      )
    end

    # Every language of one project, as { "en" => Dictionary, … }.
    def dictionaries(project: nil, languages: nil)
      rows = phrases.list(project: project_name(project || @project))
      dictionaries = Dictionary.from_phrases(rows)
      return dictionaries if languages.nil?

      languages.each_with_object({}) do |language, selected|
        selected[language] = dictionaries[language] || Dictionary.new(language, {})
      end
    end

    # Accepts an id, a name or a Project and returns the name the phrases
    # endpoints filter on — they match `projects` (names), never ids.
    def project_name(project_or_id)
      raise ConfigurationError, "No project given, and no default project on the client." if project_or_id.nil?
      return project_or_id.name if project_or_id.is_a?(Project)
      return project_or_id unless project_or_id.to_s.match?(/\A[0-9a-f]{24}\z/)

      projects.find(project_or_id).name
    end

    def get(path, params: nil)
      request(:get, path, params: params)
    end

    def post(path, body:)
      request(:post, path, body: body)
    end

    def put(path, body:)
      request(:put, path, body: body)
    end

    def delete(path, params: nil)
      request(:delete, path, params: params)
    end

    def request(method, path, params: nil, body: nil)
      url = build_url(path, params)
      uri = URI.parse(url)
      attempt = 0

      loop do
        attempt += 1

        begin
          response = execute(method, uri, body)
        rescue *RETRIABLE_EXCEPTIONS => error
          raise ConnectionError, "#{method.to_s.upcase} #{url} failed: #{error.class}: #{error.message}" if attempt > max_retries

          sleep(backoff_for(attempt))
          next
        end

        status = response.code.to_i

        if RETRIABLE_STATUSES.include?(status) && attempt <= max_retries
          sleep(retry_after(response) || backoff_for(attempt))
          next
        end

        return parse(response, method: method, url: url)
      end
    end

    # Never let a credential reach a log line, an exception report or `p client`.
    def inspect
      "#<Multilocale::Client api_url=#{@api_url.inspect} auth=#{@api_key ? 'api_key' : 'access_token'} [redacted]>"
    end
    alias to_s inspect

    private

    def authorization
      return "Basic #{Encoding.base64(@api_key)}" if @api_key

      "Token #{Encoding.base64(@access_token)}"
    end

    def build_url(path, params)
      url = "#{api_url}/api/#{path.to_s.sub(%r{\A/+}, '')}"
      query = params && Encoding.query(params)
      query && !query.empty? ? "#{url}?#{query}" : url
    end

    def execute(method, uri, body)
      request = request_class(method).new(uri)
      request["Accept"] = "application/json"
      request["Authorization"] = authorization
      request["User-Agent"] = user_agent

      unless body.nil?
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      @logger&.debug("multilocale #{method.to_s.upcase} #{uri}")

      Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: open_timeout,
        read_timeout: read_timeout
      ) { |http| http.request(request) }
    end

    def request_class(method)
      case method
      when :get then Net::HTTP::Get
      when :post then Net::HTTP::Post
      when :put then Net::HTTP::Put
      when :delete then Net::HTTP::Delete
      else raise ArgumentError, "Unsupported HTTP method #{method.inspect}"
      end
    end

    def parse(response, method:, url:)
      status = response.code.to_i
      raw = response.body.to_s
      payload =
        begin
          raw.empty? ? nil : JSON.parse(raw)
        rescue JSON::ParserError
          nil
        end

      return payload if status < 400

      raise ApiError.build(
        status: status,
        payload: payload,
        raw_body: raw,
        request_method: method,
        url: url
      )
    end

    def retry_after(response)
      seconds = response["Retry-After"]
      return nil if seconds.nil?

      value = seconds.to_f
      value.positive? ? value : nil
    end

    def backoff_for(attempt)
      retry_backoff * (2**(attempt - 1))
    end
  end
end
