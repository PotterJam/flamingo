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

In development, the sign-in page has a "Sign in as test user" button that skips
Google; it is not compiled into production. To try real Google sign-in locally,
create a separate Google OAuth client with the redirect
`http://localhost:4000/auth/google/callback` and set `GOOGLE_CLIENT_ID` and
`GOOGLE_CLIENT_SECRET`. Tests replace Google with `Flamingo.FakeGoogleStrategy`.

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

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
