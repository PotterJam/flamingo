defmodule FlamingoWeb.GameLive do
  use FlamingoWeb, :live_view

  alias Flamingo.Games

  @palette ~w(
    #000000 #FFFFFF #C1C1C1 #505050 #EF120B #740A08
    #FF7700 #C23900 #FFE404 #E8A202 #08C202 #00461A
    #00FF91 #04785E #00B2FF #02569E #2220D3 #0E0865
    #A302BA #550069 #DF69A7 #883454 #FFAC8A #CC7C4D
    #A0522D #63300D
  )

  def mount(%{"room_id" => room_id} = _params, _session, socket) do
    {:ok,
     assign(socket,
       room_id: room_id,
       player_id: nil,
       phase: :lobby,
       players: %{},
       player_order: [],
       host_id: nil,
       drawer_id: nil,
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

            socket =
              assign(socket,
                player_id: player_id,
                phase: state.phase,
                players: state.players,
                player_order: state.player_order,
                host_id: state.host_id,
                drawer_id: state.drawer_id,
                round_count: state.round_count,
                round_length: state.round_length
              )

            socket =
              if state.phase == :playing and state.current_drawing != [] do
                push_event(socket, "drawing_state", %{events: state.current_drawing})
              else
                socket
              end

            {:noreply, socket}
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

  defp palette, do: @palette

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
                <.form for={%{}} as={:settings} phx-change="update_settings" id="settings-form">
                  <div class="space-y-1">
                    <div class="flex w-full justify-between">
                      <label class="text-sm">Rounds</label>
                      <span class="text-sm">{@round_count}</span>
                    </div>
                    <input
                      type="range"
                      min="1"
                      max="5"
                      value={@round_count}
                      name="settings[round_count]"
                      class="nb-slider w-full"
                      style={"--slider-progress: #{(@round_count - 1) / 4 * 100}%"}
                      phx-hook=".RoundSlider"
                      id="round-count-slider"
                    />
                  </div>

                  <div class="mt-4">
                    <label class="text-sm">Round length(s)</label>
                    <div class="mt-1 flex w-48 items-center">
                      <input
                        type="number"
                        min="30"
                        max="120"
                        value={@round_length}
                        name="settings[round_length]"
                        class="w-full rounded-base border-2 border-border bg-white px-3 py-2 text-sm focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                        id="round-length-input"
                      />
                    </div>
                  </div>
                </.form>

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

      <div :if={@phase == :playing}>
        <div
          id="drawing-canvas"
          phx-hook="DrawingCanvas"
          phx-update="ignore"
          data-is-drawer={to_string(@player_id == @drawer_id)}
        >
          <canvas
            width="700"
            height="500"
            class={[
              "border-2 border-gray-800 bg-white",
              if(@player_id == @drawer_id, do: "cursor-crosshair", else: "cursor-default")
            ]}
          >
          </canvas>

          <%= if @player_id == @drawer_id do %>
            <div class="mt-2 flex items-center gap-3">
              <div class="grid grid-cols-13 grid-rows-2 border border-gray-300">
                <button
                  :for={color <- palette()}
                  data-color={color}
                  class="h-7 w-7 cursor-pointer border border-gray-200"
                  style={"background-color: #{color}"}
                >
                </button>
              </div>

              <div class="flex gap-1">
                <button
                  :for={size <- [6, 9, 15]}
                  data-size={size}
                  class="flex h-10 w-10 cursor-pointer items-center justify-center rounded border border-gray-300 bg-white"
                >
                  <div
                    class="rounded-full bg-black"
                    style={"width: #{size * 2}px; height: #{size * 2}px"}
                  >
                  </div>
                </button>
              </div>

              <div class="flex gap-1">
                <button
                  data-tool="pen"
                  class="flex h-10 w-10 cursor-pointer items-center justify-center rounded border border-gray-300 bg-white text-sm"
                >
                  <.icon name="hero-pencil" class="h-5 w-5" />
                </button>
                <button
                  data-tool="fill"
                  class="flex h-10 w-10 cursor-pointer items-center justify-center rounded border border-gray-300 bg-white text-sm"
                >
                  <.icon name="hero-arrows-pointing-out" class="h-5 w-5" />
                </button>
              </div>

              <div class="flex gap-1">
                <button
                  data-action="undo"
                  class="flex h-10 w-10 cursor-pointer items-center justify-center rounded border border-gray-300 bg-white text-sm"
                >
                  <.icon name="hero-arrow-uturn-left" class="h-5 w-5" />
                </button>
                <button
                  data-action="redo"
                  class="flex h-10 w-10 cursor-pointer items-center justify-center rounded border border-gray-300 bg-white text-sm"
                >
                  <.icon name="hero-arrow-uturn-right" class="h-5 w-5" />
                </button>
                <button
                  data-action="clear"
                  class="flex h-10 w-10 cursor-pointer items-center justify-center rounded border border-gray-300 bg-white text-sm"
                >
                  <.icon name="hero-trash" class="h-5 w-5" />
                </button>
              </div>
            </div>
          <% end %>
        </div>
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
      <script :type={Phoenix.LiveView.ColocatedHook} name=".RoundSlider">
        export default {
          mounted() {
            const update = () => {
              const min = parseInt(this.el.min)
              const max = parseInt(this.el.max)
              const val = parseInt(this.el.value)
              const progress = ((val - min) / (max - min)) * 100
              this.el.style.setProperty("--slider-progress", progress + "%")
            }
            update()
            this.el.addEventListener("input", () => update())
          }
        }
      </script>
    </Layouts.app>
    """
  end

  def handle_event("update_settings", %{"settings" => params}, socket) do
    round_count = String.to_integer(params["round_count"])

    round_length =
      case Integer.parse(params["round_length"]) do
        {val, _} -> max(val, 30)
        :error -> socket.assigns.round_length
      end

    {:noreply, assign(socket, round_count: round_count, round_length: round_length)}
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

  def handle_event("draw_event", event, socket) do
    Games.draw_event(socket.assigns.room_id, socket.assigns.player_id, event)
    {:noreply, socket}
  end

  def handle_info({:players_updated, players, player_order, host_id}, socket) do
    {:noreply, assign(socket, players: players, player_order: player_order, host_id: host_id)}
  end

  def handle_info({:game_started, round_count, round_length, drawer_id}, socket) do
    {:noreply,
     assign(socket,
       phase: :playing,
       round_count: round_count,
       round_length: round_length,
       drawer_id: drawer_id
     )}
  end

  def handle_info({:draw_event, from_player_id, event}, socket) do
    if from_player_id == socket.assigns.player_id do
      {:noreply, socket}
    else
      {:noreply, push_event(socket, "draw_event", event)}
    end
  end

  def terminate(_reason, socket) do
    if Map.has_key?(socket.assigns, :room_id) and Map.has_key?(socket.assigns, :player_id) do
      Games.leave(socket.assigns.room_id, socket.assigns.player_id)
    end
  end
end
