# frozen_string_literal: true

module Multilocale
  # Percent-encoding helpers written by hand on purpose: `base64` and `cgi` are
  # bundled gems on modern Rubies, and this gem has zero runtime dependencies.
  module Encoding
    UNRESERVED = /[^A-Za-z0-9\-._~]/

    module_function

    # RFC 3986 unreserved-set encoding. Used for path segments (project names
    # can contain spaces and slashes) and as the manual layer for phrase keys.
    def percent_encode(value)
      value.to_s.b.gsub(UNRESERVED) { |byte| format("%%%02X", byte.ord) }
    end

    # `Authorization: Basic <base64(secret)>` — one value, no colon, no
    # newlines. `pack("m0")` is the dependency-free strict-Base64 encoder.
    def base64(value)
      [value.to_s].pack("m0")
    end

    # Phrase keys cross TWO decoders on the way in: Express decodes the query
    # string, then the handler calls decodeURIComponent() on the result again
    # (multilocale/api/handlers/phrasesHandler.js). A key is therefore
    # documented as "URL-encoded" and must be encoded once here, on top of the
    # transport's own encoding.
    #
    # It only matters for keys containing a literal '%' — 'discount.100%_off'
    # arrives as 'discount.100' plus a decode error without this — but getting
    # it wrong silently corrupts exactly the keys nobody thinks to test.
    def phrase_key(key)
      percent_encode(key)
    end

    # Query strings, with spaces as %20 rather than '+': the second decode a
    # phrase key goes through is decodeURIComponent, which leaves '+' alone.
    def query(params)
      params
        .reject { |_, value| value.nil? }
        .map { |name, value| "#{percent_encode(name)}=#{percent_encode(value)}" }
        .join("&")
    end
  end
end
