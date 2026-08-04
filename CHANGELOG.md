# Changelog

All notable changes to this gem are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version is
the one in `lib/multilocale/version.rb`.

## [Unreleased]

## [0.1.0] - 2026-08-04

First release of the rewritten gem. The repository previously held nothing but
a licence file; nothing published under this name before.

### Added

- `Multilocale::Client` for the REST API: `Authorization: Basic base64(secret)`,
  timeouts, exponential-backoff retries on 429 and 5xx, and errors mapped onto
  `AuthenticationError` / `PermissionError` / `NotFoundError` /
  `RateLimitedError` / `ServerError` / `ConnectionError`.
- `client.projects` — list, find by id or name, create, update.
- `client.phrases` — list with filters and paging, upsert (batched), update,
  delete, plus `client.dictionary` / `client.dictionaries`.
- `Multilocale::LocaleFile` — reads and writes i18n-shaped
  `config/locales/*.yml` (and JSON), nesting dotted keys on the way out and
  flattening them on the way back.
- `Multilocale::Sync` — `pull` and `push`, driven by `multilocale.json`.
- `multilocale-ruby` command: `pull`, `push`, `projects`, `phrases`, `version`,
  with `--json` output. Credentials come from the environment only.
- `example/` — a four-language Sinatra application with its translations
  committed, so a clone runs offline.

[unreleased]: https://github.com/multilocale/multilocale-ruby-gem/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/multilocale/multilocale-ruby-gem/releases/tag/v0.1.0
