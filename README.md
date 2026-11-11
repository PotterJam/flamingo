# Flamingo

## Development

Install Erlang/OTP 28, Elixir 1.20, and Docker with Compose v2, then start Docker and run:

```sh
mix dev
```

This starts local PostgreSQL, waits for it to be ready, installs project dependencies
and asset tools, creates/migrates the development database, and starts Phoenix.
It is safe to rerun: existing database data is kept in a Docker volume.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Stop Phoenix with Ctrl+C (twice if prompted). Postgres stays running for tests;
stop it with `docker compose stop db`. Do not use `docker compose down --volumes`
unless you intend to delete the local database data.

Already running local Postgres on port 5432? Skip Docker and run `mix setup`, then
`mix phx.server` (or `iex -S mix phx.server`). The dev/test defaults are a local
`postgres` user with password `postgres`. Stop the existing server before using
`mix dev`, since both use port 5432.

In an Amp orb, `.agents/setup` installs PostgreSQL and the build tools. Run
`amp orb services ensure` to start Postgres and Phoenix, initialize the development
database, and get the browser portal. The local database credentials are disposable
development defaults, not production credentials.

## Accounts

Playing and joining rooms require no account. Signing in is optional and uses
Sign in with Google only: there are no passwords and the app sends no email. An
account saves the player's avatar and lets a host save a lobby under a permanent
link. Sessions are revocable database tokens behind a 14-day remember-me cookie.

### Signing in during development

You don't need Google to work on the app. Open `/dev/log-in/<email>` to sign in as
a test account for that email, created on first use. Add `?return_to=/some/path`
to land on a page, for example
`/dev/log-in/alice@example.com?return_to=/saved-lobby/thursday-crew`. Use a
different email in each browser window to play as several people. The sign-in
page's "Sign in as test user" button does the same for `test-user@flamingo.dev`.
These routes only exist in development.

### Testing real Google sign-in

Google only sends people back to redirect URIs registered on the OAuth client, so
use the separate **Flamingo Dev** client (Testing mode, with your Google account
added as a test user). It has two redirect URIs:

* `http://localhost:4000/auth/google/callback` for your own machine.
* `https://flamingo-dev--flamingo-inc.onamp.dev/auth/google/callback` for an Amp
  orb. Orbs normally get a new portal address per thread, which Google would
  reject, so to test Google sign-in in an orb, ask that thread's agent to give the
  orb this fixed hostname. It belongs to one orb at a time, and restarting the
  orb's processes drops it, so redo this after a restart. The commands are:

  ```sh
  amp orb portal 4000 --hostname flamingo-dev--flamingo-inc.onamp.dev --take-over
  amp orb service restart web
  ```

The app reads `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` from the environment.
Orbs get them from the project's secrets in Amp Settings; locally, export them
before `mix dev`. Without them, "Sign in with Google" shows an error and the dev
sign-in still works. Tests replace Google with `Flamingo.FakeGoogleStrategy`.

Run `mix precommit` for compilation, formatting, and the full test suite. The test
alias creates and migrates `flamingo_test` (with `MIX_TEST_PARTITION` suffix when
set). Do not point development or test configuration at a shared database.

## Production prerequisites

Before deploying this version, provision a PostgreSQL database (for example, Neon)
and configure these secrets on the application host:

* `DATABASE_URL`: database connection URL from your PostgreSQL provider
* `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`: a Google OAuth "Web application"
  client whose redirect URI is `https://<PHX_HOST>/auth/google/callback`. In Google
  Auth Platform, set the audience to External and publish the app; requesting only
  `openid email profile` needs no Google review.
* `SECRET_KEY_BASE` and `PHX_HOST`: existing Phoenix deployment configuration

Database TLS is enabled by default. `DATABASE_SSL=false` is only for a deliberately
trusted connection, such as disposable local release verification. Set
`ECTO_IPV6=true` if the database hostname requires IPv6; `POOL_SIZE` defaults to 10.
TLS uses the operating system's trusted CA certificates. For Neon, start with a
direct (non-pooled) connection URL for both the app and migrations; Ecto already
maintains an application-side connection pool.
Verify connectivity and certificate trust against the chosen database before
shipping.

Fly's release command runs `/app/bin/migrate` before starting the new app release.
Fly hosts the app, not necessarily the database: this command also works with Neon
through `DATABASE_URL`. It uses the generated `Flamingo.Release` module because
production releases do not include Mix; it does not create the database.
Applying those migrations changes the configured database. Provisioning, the Google
OAuth client, and deployment must be completed separately before sign-in is live.
The app still requires one machine for in-memory games; adding Postgres does not
make active games durable or enable multi-machine room routing.

## In-app changelog

Edit `priv/changelog.json` to add user-facing changes. Keep release groups newest
first, with one group per release date (`YYYY-MM-DD`) and an `entries` list of
`{"type": "feature", "text": "What changed for players."}` objects. Supported types
are `feature`, `fix`, and `new_mode`. Use actual release dates rather than weekly
report dates, and omit weeks without user-facing changes.

The feed is compiled into the app and appears only on home and lobby screens.
Content changes require an app deployment. Run `mix precommit` before shipping.
The initial backfill comes from the weekly changelog reports, with dates checked
against successful Fly deployment runs.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
