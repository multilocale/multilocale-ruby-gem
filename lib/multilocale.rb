# frozen_string_literal: true

require_relative "multilocale/version"
require_relative "multilocale/errors"
require_relative "multilocale/encoding"
require_relative "multilocale/project"
require_relative "multilocale/phrase"
require_relative "multilocale/dictionary"
require_relative "multilocale/locale_file"
require_relative "multilocale/config_file"
require_relative "multilocale/projects"
require_relative "multilocale/phrases"
require_relative "multilocale/client"
require_relative "multilocale/sync"

# Ruby client for the Multilocale translation API (https://www.multilocale.com).
#
#   client = Multilocale.client                       # reads MULTILOCALE_API_KEY
#   client.dictionary(project: "website", language: "es").to_h
#   #=> { "cart.title" => "Carrito", … }
#
# The gem talks to the REST API and writes i18n-shaped locale files; the i18n
# gem renders them. It deliberately does not wrap I18n itself — a translation
# backend that makes a network call per lookup is how a marketing page ends up
# depending on someone else's uptime.
module Multilocale
  class << self
    # Builds a client from the environment, or from explicit keywords.
    def client(**options)
      Client.new(**options)
    end

    # Convenience for the common one-liner: one language of one project.
    def dictionary(project:, language:, **options)
      client(**options).dictionary(project: project, language: language)
    end
  end
end
