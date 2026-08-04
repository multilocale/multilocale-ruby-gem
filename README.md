# multilocale (Ruby)

Ruby client for [Multilocale](https://www.multilocale.com), the translation
management platform. It reads and writes projects and phrases over the REST
API, and syncs them into the locale files the [i18n
gem](https://github.com/ruby-i18n/i18n) — and therefore Rails — already load.

```ruby
client = Multilocale.client                                   # MULTILOCALE_API_KEY
client.dictionary(project: "website", language: "es").to_h
#=> { "cart.title" => "Carrito", "nav.language" => "Idioma", … }
```

```console
$ multilocale-ruby pull
website: 412 phrases in 6 languages
  wrote config/locales/en.yml
  wrote config/locales/es.yml
  …
```

- No runtime dependencies: `net/http`, `json` and `yaml` from the standard library.
- No network call while a page is being served. Translations are downloaded at
  build time and committed, so the site renders offline and stays up when
  multilocale.com does not.
- Ruby >= 3.2.

## Install

```ruby
# Gemfile
gem "multilocale", "~> 0.1"
```

```console
gem install multilocale
```

> **0.1.0 is not on RubyGems yet.** Until it is, install from a checkout —
> `gem "multilocale", path: "…"` in your Gemfile, or `rake build && gem install
> pkg/multilocale-0.1.0.gem`. `example/` in this repository already resolves the
> gem from `path: ".."`, so it needs nothing extra.

## The workflow this gem is for

1. **Phrases live in a project on multilocale.com.** A project has a name, a
   default locale and a complete locale list. A phrase is one
   `{key, value, language}` row, so a key translated into 12 locales is 12 rows.
2. **`multilocale-ruby pull` writes them to disk** as
   `config/locales/<locale>.yml`, nested the way i18n expects.
3. **You commit the result.** The files are part of the application, reviewed
   in the same pull request as the code that renders them.
4. **The i18n gem renders them.** Nothing in the request path talks to
   Multilocale.

Editing a locale file by hand and sending it back up is `multilocale-ruby push
--yes`.

## Authenticate

Create a key at [app.multilocale.com](https://app.multilocale.com) → **API
keys**, and export the secret:

```console
export MULTILOCALE_API_KEY=…
```

The API expects `Authorization: Basic base64(secret)` — the secret alone,
base64'd, **with no colon and no key/secret pair**. This gem does that for you;
it is worth knowing because a hand-rolled `curl` with `-u key:secret` is the
single most common first failure.

The secret selects the organization *and* the project, so there is no tenant
parameter to pass, and a key scoped to one project cannot read another's
phrases even if you ask for it.

Scopes are `projects:read`, `projects:write`, `phrases:read`, `phrases:write`.
New keys get the read scopes only; `pull` needs `projects:read` +
`phrases:read`, `push` also needs `phrases:write`.

There is deliberately **no `--api-key` flag**. A secret on the command line is
readable in the process table and lives in your shell history forever.

## Configure

`multilocale.json` in the repository root, the same file the
[npm CLI](https://www.npmjs.com/package/multilocale) reads:

```json
{
  "projectId": "website",
  "defaultLocale": "en",
  "locales": ["en", "es", "fr", "it"],
  "paths": ["config/locales/%lang%.yml"]
}
```

- `projectId` accepts an id **or** a name. Names are unique per organization,
  which is what makes this portable between accounts.
- `paths` are resolved relative to `multilocale.json`, so `rake` from a
  subdirectory writes the same files as `rake` from the root.
- `%lang%` is replaced with each locale.

Every command works with no flags once this file exists. Nothing ever prompts —
an interactive picker in a CI job is a hung build.

## Command line

```console
multilocale-ruby pull                       # API   -> config/locales/*.yml
multilocale-ruby push --yes                 # files -> API (overwrites remote values)
multilocale-ruby projects                   # what this credential can see
multilocale-ruby phrases --language es      # one dictionary, key = value
multilocale-ruby pull --json                # machine-readable report
```

The executable is `multilocale-ruby`, not `multilocale`: that name belongs to
the npm CLI, and two tools fighting over one name on `PATH` helps nobody.

## In a Rails application

```ruby
# lib/tasks/multilocale.rake
require "multilocale"

namespace :multilocale do
  desc "Download the project's phrases into config/locales"
  task :pull do
    result = Multilocale::Sync.new(
      client: Multilocale.client,
      config: Multilocale::ConfigFile.discover(Rails.root)
    ).pull

    puts "#{result.phrases} phrases in #{result.languages.size} languages"
  end
end
```

`config/locales/*.yml` is already on `I18n.load_path`, so `t("cart.title")`
works with no further wiring. `example/` in this repository is the same thing in
Sinatra, small enough to read in one sitting.

## Library

```ruby
client = Multilocale::Client.new(api_key: ENV["MULTILOCALE_API_KEY"])

client.projects.list                                  # => [Multilocale::Project]
client.projects.find("website")                       # by id or by name
client.projects.create(name: "docs", default_locale: "en", locales: %w[en fr])
client.projects.update(id, locales: %w[en fr de])     # replaces the locale list

client.phrases.list(project: "website", language: "es")
client.phrases.list(project: "website", key: "cart.title")
client.phrases.upsert(key: "cart.title", value: "Cart", language: "en", projects: ["website"])
client.phrases.update(phrase_id, value: "Basket")
client.phrases.delete(key: "cart.title", project: "website")

client.dictionary(project: "website", language: "es")  # => Multilocale::Dictionary
client.dictionaries(project: "website")                # => { "en" => …, "es" => … }
```

Every call raises a `Multilocale::Error` subclass on failure —
`AuthenticationError` (401), `PermissionError` (403), `NotFoundError` (404),
`RateLimitedError` (429), `ServerError` (5xx), `ConnectionError`. 429 and 5xx
are retried with exponential backoff; 4xx is not, because retrying a missing
scope only burns rate limit.

### Things worth knowing before you write

- **`locales:` on a project update is a replacement, not a merge.** Read the
  project, add to `project.locales`, send the whole list back. Omitting a
  locale removes it.
- **`delete` removes every language of a key**, not one row — and rows shared
  with other projects are deleted, not detached from this one.
- **`upsert` overwrites.** It is not a patch: send the whole row.
- **A phrase needs `projects: [name]`.** Without it the row exists in the
  organization but belongs to no project, and no download will include it.
- **`list` without `limit` returns everything.** Pass `limit`/`skip` only when
  you want a page; they cap at 2001 and 10000.

## Locale files

`config/locales/es.yml`, as written by `pull`:

```yaml
# Generated by `multilocale-ruby pull`. Edit the phrases on multilocale.com, not here.
---
es:
  cart:
    title: Carrito
  greeting: "¡Hola, %{name}!"
```

Two details that matter to Ruby specifically:

- **Dotted keys are nested.** i18n resolves `t("cart.title")` by walking
  hashes, so a flat `"cart.title":` key would never be found. `push` flattens
  them again on the way back.
- **No `locale:` entry is injected.** The npm CLI writes one into every
  dictionary it generates; in a Rails locale file it would show up as the
  translation `t("locale")`.

`%{name}` and `%{count}` survive machine translation: Multilocale checks that
every `{…}` placeholder in the source is still present in the translation and
repairs it if not.

Pluralisation is ordinary i18n — store `items.one` and `items.other` as two
keys and call `t("items", count: 3)`.

## Example application

```console
cd example
bundle install
bundle exec ruby app.rb        # http://localhost:4567
```

Four locales, translations committed, no credentials needed. `/en/`, `/es/`,
`/fr/`, `/it/`. It resolves the gem from `path: ".."`, so it runs against the
code in this checkout and works before the gem is on RubyGems.

## Documentation

- REST API and CLI guides: <https://www.multilocale.com/developers/>
- Issues: <https://github.com/multilocale/multilocale-ruby-gem/issues>

## License

MIT.
