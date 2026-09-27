# Flamingo

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

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
