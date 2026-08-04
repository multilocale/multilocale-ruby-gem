# frozen_string_literal: true

# A four-language page whose every string comes from config/locales/*.yml —
# files written by `multilocale-ruby pull`, rendered by the i18n gem.
#
#   bundle install
#   bundle exec ruby app.rb        # http://localhost:4567
#
# There is no API call while serving a request, and no credential in this
# process: translations are synced at build time and committed, so the page
# renders offline and stays up when multilocale.com does not.

require "i18n"
require "multilocale"
require "sinatra/base"

LOCALES_PATH = File.join(__dir__, "config", "locales")

I18n.load_path = Dir[File.join(LOCALES_PATH, "*.yml")]
I18n.available_locales = I18n.load_path.map { |path| File.basename(path, ".yml").to_sym }.sort
I18n.default_locale = :en
I18n.enforce_available_locales = true
I18n.backend.load_translations

class ExampleApp < Sinatra::Base
  set :views, File.join(__dir__, "views")
  set :port, ENV.fetch("PORT", 4567)
  set :bind, ENV.fetch("HOST", "127.0.0.1")

  # The same reader `multilocale-ruby push` uses: it loads a locale file and
  # flattens it back into the flat `key => value` shape Multilocale stores. Here
  # it just counts the keys, which gives the pluralised line on the page a real
  # number instead of a hardcoded one.
  LOCALE_FILE = Multilocale::LocaleFile.new(
    path_template: "config/locales/%lang%.yml",
    base_dir: __dir__
  )

  helpers do
    # Rails ships `t` as a view helper; plain Sinatra does not, so the one line
    # that makes the templates below look like any other Ruby application is
    # this one. It is still the i18n gem doing the lookup.
    def t(key, **options)
      I18n.t(key, **options)
    end
  end

  get "/" do
    redirect "/#{I18n.default_locale}/"
  end

  get "/:locale/?" do
    locale = params["locale"].to_sym
    halt 404, "No such locale: #{params['locale']}" unless I18n.available_locales.include?(locale)

    I18n.with_locale(locale) do
      erb :index, locals: {
        locale: locale,
        phrase_count: LOCALE_FILE.read(locale).size,
        gem_version: Multilocale::VERSION
      }
    end
  end

  run! if __FILE__ == $PROGRAM_NAME
end
