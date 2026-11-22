defmodule FlamingoWeb.LobbyHistoryLive do
  use FlamingoWeb, :live_view

  import FlamingoWeb.GameHistoryComponents

  alias Flamingo.{GameHistory, SavedLobbies}

  @page_size 20

  @tab_active_classes %{
    classic: "bg-pink-100 text-pink-900",
    constraint_roulette: "bg-purple-100 text-purple-900",
    coop: "bg-green-100 text-green-900",
    spellslingers: "bg-amber-100 text-amber-900"
  }

  def mount(%{"saved_lobby_name" => name}, _session, socket) do
    case SavedLobbies.get_saved_lobby_by_name(name) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That saved lobby doesn't exist.")
         |> push_navigate(to: ~p"/")}

      saved_lobby ->
        {:ok,
         socket
         |> assign(
           saved_lobby: saved_lobby,
           mode_filter: nil,
           filtered_count: 0,
           games_loaded: 0
         )
         |> stream(:games, [])}
    end
  end

  def handle_params(params, _uri, socket) do
    mode_filter = parse_mode_filter(params["mode"])
    lobby_id = socket.assigns.saved_lobby.id
    games = GameHistory.list_games(lobby_id, mode: mode_filter, limit: @page_size)
    filtered_count = GameHistory.count_games(lobby_id, mode: mode_filter)

    {:noreply,
     socket
     |> assign(
       mode_filter: mode_filter,
       filtered_count: filtered_count,
       games_loaded: length(games)
     )
     |> stream(:games, games, reset: true)}
  end

  def handle_event("load_more", _params, socket) do
    %{saved_lobby: lobby, mode_filter: mode_filter, games_loaded: offset} = socket.assigns
    more = GameHistory.list_games(lobby.id, mode: mode_filter, limit: @page_size, offset: offset)

    {:noreply,
     socket
     |> assign(:games_loaded, offset + length(more))
     |> stream(:games, more)}
  end

  defp active_tab_class(mode_id), do: Map.get(@tab_active_classes, mode_id, "bg-primary")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.account_menu current_scope={@current_scope} />

      <div class="mx-auto max-w-3xl space-y-4 px-6 pt-24 pb-20">
        <.breadcrumb id="history-breadcrumb">
          <:item navigate={~p"/saved-lobby/#{@saved_lobby.name}"}>{@saved_lobby.name}</:item>
          <:item>Game history</:item>
        </.breadcrumb>

        <.card id="history-games-card" class="overflow-hidden bg-white p-0">
          <div class="flex flex-wrap items-center justify-between gap-4 border-b-2 border-border p-5">
            <h1 id="history-heading" class="text-2xl font-black">Game history</h1>

            <nav
              id="history-mode-filters"
              aria-label="Filter by game mode"
              class="inline-flex flex-wrap items-center gap-0.5 rounded-base border-2 border-border bg-pink-50 p-1"
            >
              <.link
                id="filter-mode-all"
                patch={~p"/saved-lobby/#{@saved_lobby.name}/history"}
                aria-current={if is_nil(@mode_filter), do: "page"}
                class={[
                  "inline-flex items-center rounded-base border-2 px-2.5 py-1 text-xs font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2",
                  if(is_nil(@mode_filter),
                    do: "border-border bg-primary font-black text-black",
                    else: "border-transparent text-gray-600 hover:text-black"
                  )
                ]}
              >
                All
              </.link>
              <.link
                :for={mode <- history_modes()}
                id={"filter-mode-#{mode.id()}"}
                patch={~p"/saved-lobby/#{@saved_lobby.name}/history?#{%{mode: mode.id()}}"}
                aria-current={if @mode_filter == mode.id(), do: "page"}
                class={[
                  "inline-flex items-center rounded-base border-2 px-2.5 py-1 text-xs font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2",
                  if(@mode_filter == mode.id(),
                    do: ["border-border font-black", active_tab_class(mode.id())],
                    else: "border-transparent text-gray-600 hover:text-black"
                  )
                ]}
              >
                {mode.title()}
              </.link>
            </nav>
          </div>

          <div class="p-3 sm:p-4">
            <div id="history-games-list" phx-update="stream" class="space-y-0.5">
              <div
                id="history-games-empty"
                class="hidden px-3 py-10 text-center text-sm text-gray-500 only:block"
              >
                {if @mode_filter,
                  do:
                    "No #{FlamingoWeb.GameModes.get(@mode_filter).title()} games recorded in this lobby yet.",
                  else: "No finished games recorded in this lobby yet."}
              </div>
              <div :for={{dom_id, game} <- @streams.games} id={dom_id}>
                <.game_summary_row
                  game={game}
                  lobby_name={@saved_lobby.name}
                  id={"history-game-#{game.id}"}
                />
              </div>
            </div>
          </div>

          <div :if={@games_loaded < @filtered_count} class="border-t-2 border-border">
            <.button
              id="history-load-more"
              type="button"
              variant="ghost"
              phx-click="load_more"
              class="flex w-full items-center justify-center gap-2 rounded-none border-0! px-5! py-2.5! font-bold"
            >
              Load more ({@filtered_count - @games_loaded} remaining)
            </.button>
          </div>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
