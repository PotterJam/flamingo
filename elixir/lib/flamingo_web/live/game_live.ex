defmodule FlamingoWeb.GameLive do
  use FlamingoWeb, :live_view

  alias Flamingo.Games

  def mount(%{"room_id" => room_id} = _params, _session, socket) do
    {:ok,
     assign(socket,
       room_id: room_id,
       player_id: nil,
       phase: :lobby,
       players: %{},
       player_order: [],
       host_id: nil,
       round_count: 3,
       round_length: 45
     )}
  end

  def handle_params(%{"player_id" => player_id}, _uri, socket) do
    room_id = socket.assigns.room_id

    if connected?(socket) do
      case Games.get_state(room_id) do
        {:ok, state} ->
          if Map.has_key?(state.players, player_id) do
            Games.subscribe(room_id)

            {:noreply,
             assign(socket,
               player_id: player_id,
               phase: state.phase,
               players: state.players,
               player_order: state.player_order,
               host_id: state.host_id,
               round_count: state.round_count,
               round_length: state.round_length
             )}
          else
            {:noreply, push_navigate(socket, to: ~p"/")}
          end

        {:error, :not_found} ->
          {:noreply, push_navigate(socket, to: ~p"/")}
      end
    else
      {:noreply, assign(socket, player_id: player_id)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex h-screen w-full items-center justify-center">
        <%= if @phase == :lobby do %>
          <.card class="flex h-3/5 w-full max-w-2xl flex-row gap-0 bg-white p-0">
            <div class="flex flex-1 flex-col gap-4 border-r-2 border-border p-4">
              <h2 class="text-xl font-bold">Players</h2>
              <ul class="space-y-2">
                <%= for pid <- @player_order do %>
                  <li>{Map.get(@players, pid).name}</li>
                <% end %>
              </ul>
            </div>

            <%= if @player_id == @host_id do %>
              <div class="flex h-full w-full flex-[3] flex-col gap-4 p-4">
                <div class="space-y-3">
                  <div class="flex w-full justify-between">
                    <label class="text-sm">Rounds</label>
                    <span class="text-sm">{@round_count}</span>
                  </div>
                  <input
                    type="range"
                    min="1"
                    max="5"
                    value={@round_count}
                    phx-change="update_round_count"
                    name="round_count"
                    class="nb-slider w-full"
                    style={"--slider-progress: #{(@round_count - 1) / 4 * 100}%"}
                    id="round-count-slider"
                  />
                </div>

                <div>
                  <label class="text-sm">Round length(s)</label>
                  <div class="mt-1 flex w-48 items-center">
                    <input
                      type="number"
                      min="30"
                      max="120"
                      value={@round_length}
                      phx-change="update_round_length"
                      name="round_length"
                      class="w-full rounded-base border-2 border-border bg-white px-3 py-2 text-sm focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                      id="round-length-input"
                    />
                  </div>
                </div>

                <div class="mt-auto flex w-full flex-col gap-4">
                  <div>
                    <label class="text-sm">Room name</label>
                    <div class="flex flex-row items-center justify-between">
                      <p class="font-bold">{@room_id}</p>
                      <div class="flex gap-1">
                        <.button
                          variant="ghost"
                          class="text-xs"
                          phx-click={JS.dispatch("phx:copy", detail: %{text: @room_id})}
                          id="copy-name-button"
                        >
                          Copy name
                        </.button>
                        <.button
                          variant="outline"
                          class="text-xs"
                          phx-click={
                            JS.dispatch("phx:copy", detail: %{text: url(~p"/game/#{@room_id}")})
                          }
                          id="copy-link-button"
                        >
                          Copy link
                        </.button>
                      </div>
                    </div>
                  </div>

                  <.button
                    variant="default"
                    phx-click="start_game"
                    disabled={map_size(@players) < 2}
                    id="start-game-button"
                  >
                    Start Game
                  </.button>
                </div>
              </div>
            <% else %>
              <div class="my-auto flex-[3] text-center">
                The host is configuring the game
              </div>
            <% end %>
          </.card>
        <% else %>
          <div>
            Game started!
          </div>
        <% end %>
      </div>

      <div id="clipboard-handler" phx-hook=".Clipboard" phx-update="ignore"></div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Clipboard">
        export default {
          mounted() {
            window.addEventListener("phx:copy", (event) => {
              if (event.detail && event.detail.text) {
                navigator.clipboard.writeText(event.detail.text)
              }
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  def handle_event("update_round_count", %{"round_count" => count}, socket) do
    {:noreply, assign(socket, round_count: String.to_integer(count))}
  end

  def handle_event("update_round_length", %{"round_length" => length}, socket) do
    value = max(String.to_integer(length), 30)
    {:noreply, assign(socket, round_length: value)}
  end

  def handle_event("start_game", _params, socket) do
    settings = %{
      round_count: socket.assigns.round_count,
      round_length: socket.assigns.round_length
    }

    case Games.start_game(socket.assigns.room_id, socket.assigns.player_id, settings) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot start game: #{reason}")}
    end
  end

  def handle_info({:players_updated, players, player_order, host_id}, socket) do
    {:noreply, assign(socket, players: players, player_order: player_order, host_id: host_id)}
  end

  def handle_info({:game_started, round_count, round_length}, socket) do
    {:noreply,
     assign(socket, phase: :playing, round_count: round_count, round_length: round_length)}
  end

  def terminate(_reason, socket) do
    if Map.has_key?(socket.assigns, :room_id) and Map.has_key?(socket.assigns, :player_id) do
      Games.leave(socket.assigns.room_id, socket.assigns.player_id)
    end
  end
end
