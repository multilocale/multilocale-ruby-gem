# AGENTS.md — multilocale Ruby gem

Client gem for the Multilocale REST API, plus a four-language Sinatra
application under `example/` that renders what it downloads.

Read `README.md` first for the user-facing workflow. This file is what an agent
needs on top of it: where the code lives, how to run it, and the product traps
that look like bugs in your code but are not.

## Layout

| Path                     | What it is                                                    |
| ------------------------ | ------------------------------------------------------------- |
| `lib/multilocale.rb`     | Entry point, `Multilocale.client`                              |
| `lib/multilocale/client.rb` | HTTP, auth, retries, error mapping                          |
| `lib/multilocale/projects.rb`, `phrases.rb` | The two REST resources             |
| `lib/multilocale/project.rb`, `phrase.rb` | Wire documents with Ruby readers     |
| `lib/multilocale/dictionary.rb` | Flat keys ⇄ nested hashes                                |
| `lib/multilocale/locale_file.rb` | Reads and writes `config/locales/*.yml`                 |
| `lib/multilocale/config_file.rb` | `multilocale.json`                                      |
| `lib/multilocale/sync.rb` | `pull` / `push`                                              |
| `lib/multilocale/cli.rb`, `exe/multilocale-ruby` | The command                     |
| `spec/`                  | RSpec, against a real HTTP stub server (`spec/support/stub_api.rb`) |
| `example/`               | Sinatra + i18n application, translations committed             |
| `multilocale.json`       | Project config, shared with the npm CLI                        |
| `scripts/publishExample.mjs` | Mirrors this directory to the public GitHub repository     |

## Run it

```console
bundle install
bundle exec rake                 # syntax check + the spec suite
bundle exec rake build           # pkg/multilocale-<version>.gem

cd example
bundle install
bundle exec ruby app.rb          # http://localhost:4567 — /en/ /es/ /fr/ /it/
```

The suite makes real HTTP requests to a stub server on a loopback socket, so
the bytes on the wire (the `Authorization` scheme, the double-encoded phrase
key, the JSON body shapes) are asserted rather than mocked. It needs no
network, no credential and no account.

## How `example/` resolves the gem, and the override (`Gemfile.local`)

`example/Gemfile` declares `gem "multilocale", "~> 0.1", path: ".."`. The
version requirement is the one a reader writes in their own Gemfile; `path:` is
what makes a bare `git clone && cd example && bundle install` work. Bundler
checks the local gemspec against the requirement, so the two cannot drift.

This deliberately differs from `multilocale/examples/*`, whose committed
manifests name the published npm package. Those are *consumer* repositories;
this is the **gem's own repository**, so its example must demonstrate the code
committed beside it, not the last release — and there is no release yet:
**nothing has ever been published under the gem name `multilocale` on RubyGems**
(the name is free; the API answers 404). The example previously named the
published gem and was therefore uninstallable from a fresh clone —
`Could not find gem 'multilocale (~> 0.1)'` — while CI hid it by writing a
`Gemfile.local` before installing. Both are fixed; do not reintroduce either.

To run the example against a real RubyGems release once one exists:

```console
cd example
echo 'gem "multilocale", "~> 0.1"' > Gemfile.local
bundle install
bundle info multilocale          # a version, not a Path:
```

Delete the file and re-run `bundle install` to go back to this working copy.

`Gemfile.local` is gitignored here **and** in `multilocale/libraries/.gitignore`,
and `scripts/publishExample.mjs` mirrors only git-tracked files *and* names it in
`exclude`, so it takes two independent mistakes for the override to reach the
public repository.

Bundler refuses to see the same gem declared twice, so the override *replaces*
the `gem "multilocale"` line rather than adding to it — that is why the Gemfile
has an `if File.exist?(override)` around it, and why this is not spelled the
same way as the npm examples' `pnpm-workspace.yaml` `overrides` block.

**Lockfiles are not committed** (`Gemfile.lock`, `example/Gemfile.lock`). For
the root one that is the ordinary convention for a gem: it resolves against
whatever its consumers already have, so a lockfile here would only describe one
machine.

`example/` is an application and could reasonably commit one — since the Gemfile
says `path: ".."` its `PATH` section is the relative `remote: ..`, not an
absolute developer path, so it would be portable. It is left uncommitted only
because a lockfile generated on one machine records that machine's `PLATFORMS`,
and a macOS-only lock breaks the Linux CI job until someone remembers
`bundle lock --add-platform x86_64-linux`. Every dependency is `~>`-pinned, so
a fresh `bundle install` resolves the same minor versions anyway. A
`Gemfile.local` that reintroduces an absolute `path:` will write one into the
lockfile — another reason both stay gitignored.

## Product facts you must not get wrong

- **`Authorization: Basic base64(secret)`** — the key secret alone, base64'd,
  no colon, no key/secret pair. See `multilocale/api/handlers/withKey.js`. The
  secret selects both the organization and the project.
- **No `@multilocale/*` npm package is alive.** `@multilocale/react` is 404 on
  npm. The maintained packages are the `multilocale` npm CLI and this gem; the
  runtime that renders translations is the ecosystem's own (here: the i18n gem).
- **A phrase is one row per language.** `phrases.list` returns rows, not keys.
- **`DELETE /api/phrases?key&project` deletes every language of that key**, and
  deletes rows shared with other projects instead of detaching them. Surface
  that blast radius before you call it; the CLI requires `--yes`.
- **Project `locales` is replaced wholesale on update.** Never send a subset.
- **Phrase keys cross two decoders.** Express decodes the query string, then
  the handler calls `decodeURIComponent` on the result again, so a key is sent
  double-encoded (`Multilocale::Encoding.phrase_key`). Only keys containing a
  literal `%` show the difference — which is exactly why it is easy to break
  and hard to notice.
- **`limit` is optional and unbounded when omitted**; when passed it clamps at
  2001, and `skip` at 10000.
- **`machineTranslated` used to be `googleTranslate`.** Old rows only have the
  latter, and `Phrase#machine_translated?` reads both.
- **`/api/translate` and `/api/translate-to-all-languages` need an operator
  session**, not an API key. They are deliberately absent from this gem.

## Traps in the npm CLI this gem deliberately does not copy

Relevant when a repository uses both tools, or when you are tempted to make the
two behave identically:

- `multilocale import` and `unused` read `paths` from the **project** and
  destructure it undefended, throwing `Cannot read properties of undefined` when
  it is unset. `ConfigFile#paths` returns `[]`, and `paths!` explains what to add.
- `download` resolves `project.paths || config.paths`: a value set server-side
  wins over the local `multilocale.json`. This gem only ever uses the local one.
- `download` injects a `"locale": "<lang>"` entry into every generated file.
  This gem does not — in a Rails locale file that entry *is* a translation.
- `import` accepts flat JSON only; nested objects are stored as objects and
  machine-translated into garbage, spending credits.
- `unused` greps `.js/.jsx/.ts/.tsx/.cjs/.mjs` only, so it reports every Ruby
  key as unused. Do not wire it into CI here.
- The CLI's format whitelist is `cjs`, `esm`, `json`, `js`, `swift` — **there is
  no YAML writer**, which is the whole reason this gem exists. `LocaleFile`
  supports `yaml` and `json`, inferred from the path extension. Keep `format`
  out of `multilocale.json` unless it is one they both understand: `npx
  multilocale download` raises `Invalid format: yaml`.

## Config in this repository

`multilocale.json` points at the project name `multilocale-ruby-example` and at
`example/config/locales/%lang%.yml`. The name — rather than an id — is
deliberate: names are unique per organization, so a reader who creates a
project with that name in their own account gets a working `pull` with no
edits. No such project exists in the Multilocale account that owns this
monorepo; create one before running `pull` against production.

The committed `example/config/locales/*.yml` are generated from
`spec/fixtures/phrases.json`, and `spec/sync_spec.rb` regenerates and compares
them byte for byte. If you change the fixture, the spec fails until the
committed files are regenerated, and vice versa. That is the only thing keeping
the example honest offline.

## Publishing

`multilocale/libraries/ruby-gem` is the source of truth;
`github.com/multilocale/multilocale-ruby-gem` is a read-only mirror.

```console
node scripts/publishExample.mjs --dry-run    # always first
node scripts/publishExample.mjs
```

The engine (`shell/publishDirectoryToRepo.js`) refuses a dirty working tree and
publishes only git-tracked files. It is passed no `versionFile`: the mirror is
not what anyone installs, RubyGems is, and the public repository already has a
commit without a version file — which the version guard would (correctly)
refuse to publish over. The version that matters is bumped in
`lib/multilocale/version.rb` and shipped with `gem push`, which is a separate,
explicitly authorised action.
