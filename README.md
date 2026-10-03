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

Playing and joining rooms still require no account. Register at `/users/register`
and use the emailed magic link to confirm and sign in. Authentication is magic-link
only; there are no account passwords. Choosing to stay logged in
sets a remember-me cookie backed by a revocable database session token.

Development email stays in the local Swoosh mailbox at `/dev/mailbox`; it is not
sent externally. The mailbox route is not compiled into production. Tests use
Swoosh's test adapter and an isolated SQL sandbox.

Run `mix precommit` for compilation, formatting, and the full test suite. The test
alias creates and migrates `flamingo_test` (with `MIX_TEST_PARTITION` suffix when
set). Do not point development or test configuration at a shared database.

## Production prerequisites

Before deploying this version, provision a PostgreSQL database (for example, Neon)
and configure these secrets on the application host:

* `DATABASE_URL`: database connection URL from your PostgreSQL provider
* `RESEND_API_KEY`: API key for the Swoosh Resend adapter
* `MAIL_FROM`: sender address on a verified sending domain
* `SECRET_KEY_BASE` and `PHX_HOST`: existing Phoenix deployment configuration

Database TLS is enabled by default. `DATABASE_SSL=false` is only for a deliberately
trusted connection, such as disposable local release verification. Set
`ECTO_IPV6=true` if the database hostname requires IPv6; `POOL_SIZE` defaults to 10.
TLS uses the operating system's trusted CA certificates. For Neon, start with a
direct (non-pooled) connection URL for both the app and migrations; Ecto already
maintains an application-side connection pool.
Verify connectivity and certificate trust against the chosen database before
shipping. The mail adapter is configured in `config/runtime.exs` and can be changed
if we select another provider.

Fly's release command runs `/app/bin/migrate` before starting the new app release.
Fly hosts the app, not necessarily the database: this command also works with Neon
through `DATABASE_URL`. It uses the generated `Flamingo.Release` module because
production releases do not include Mix; it does not create the database.
Applying those migrations changes the configured database. Provisioning, production
mail delivery, and deployment must be completed separately before auth is live.
The app still requires one machine for in-memory games; adding Postgres does not
make active games durable or enable multi-machine room routing.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
