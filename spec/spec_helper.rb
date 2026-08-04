# frozen_string_literal: true

require "json"

require "multilocale"
require "multilocale/cli"

require_relative "support/stub_api"

FIXTURES = File.expand_path("fixtures", __dir__)
GEM_ROOT = File.expand_path("..", __dir__)

# The API-shaped rows the stub serves. The same fixture generates the committed
# example/config/locales files, so a change to either shows up as a diff.
def fixture_phrases
  JSON.parse(File.read(File.join(FIXTURES, "phrases.json")))
end

# Every spec passes an explicit api_key and api_url, so a developer's exported
# MULTILOCALE_* variables can neither leak into a request nor point the suite
# at production.
module StubApiHelper
  def stub_api
    @stub_api ||= StubApi.new
  end

  def client(**options)
    Multilocale::Client.new(**{ api_key: "s3cret", api_url: stub_api.url, max_retries: 0 }.merge(options))
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)

  config.include StubApiHelper
  config.after { @stub_api&.stop }
end
