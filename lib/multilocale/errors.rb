# frozen_string_literal: true

module Multilocale
  # Base class for everything this gem raises, so callers can rescue one thing.
  class Error < StandardError; end

  # Raised before any request is made: no credential, no project, a config file
  # that does not say which project it describes.
  class ConfigurationError < Error; end

  # The request never got an HTTP response (DNS, TLS, timeout, reset) and the
  # retry budget is spent.
  class ConnectionError < Error; end

  # The server answered with a status >= 400.
  class ApiError < Error
    attr_reader :status, :body, :request_method, :url

    def initialize(message, status: nil, body: nil, request_method: nil, url: nil)
      super(message)
      @status = status
      @body = body
      @request_method = request_method
      @url = url
    end

    STATUS_CLASSES = {
      401 => "AuthenticationError",
      403 => "PermissionError",
      404 => "NotFoundError",
      429 => "RateLimitedError"
    }.freeze

    # Maps an HTTP status onto the narrowest error class. 5xx is a single
    # ServerError: the API returns the same `{status, message}` envelope for all
    # of them and callers treat them identically (retry, then give up).
    def self.class_for(status)
      name = STATUS_CLASSES[status]
      return Multilocale.const_get(name) if name
      return ServerError if status >= 500

      self
    end

    def self.build(status:, payload:, raw_body:, request_method:, url:)
      message = payload.is_a?(Hash) ? payload["message"] : nil
      message = "HTTP #{status}" if message.nil? || message.to_s.empty?

      class_for(status).new(
        "#{message} (#{request_method.to_s.upcase} #{url} -> #{status})#{hint_for(status)}",
        status: status,
        body: payload || raw_body,
        request_method: request_method,
        url: url
      )
    end

    # The two failures every new integration hits, answered in the message
    # itself rather than in a doc the reader is not looking at.
    def self.hint_for(status)
      case status
      when 401
        "\nCheck MULTILOCALE_API_KEY: the API expects Basic base64(secret) — the key secret alone, " \
          "not key:secret."
      when 403
        "\nThe key is valid but not allowed here: a missing scope (projects:read, phrases:write, …) " \
          "or a key scoped to a different project."
      else
        ""
      end
    end
  end

  class AuthenticationError < ApiError; end
  class PermissionError < ApiError; end
  class NotFoundError < ApiError; end
  class RateLimitedError < ApiError; end
  class ServerError < ApiError; end
end
