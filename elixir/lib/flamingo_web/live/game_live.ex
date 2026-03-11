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
       round_length: 30
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
      <div :if={@phase == :lobby}>
        <h1>Room: {@room_id}</h1>

        <h2>Players</h2>
        <ul>
          <li :for={pid <- @player_order}>
            {Map.get(@players, pid).name}
            <span :if={pid == @host_id}>(host)</span>
          </li>
        </ul>

        <form :if={@player_id == @host_id} phx-submit="start_game">
          <div>
            <label>Rounds:</label>
            <input type="range" min="1" max="5" value={@round_count} name="round_count" />
          </div>

          <div>
            <label>Round length (seconds):</label>
            <input type="number" min="30" value={@round_length} name="round_length" />
          </div>

          <button type="submit" disabled={map_size(@players) < 2}>
            Start Game
          </button>
        </form>
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
                  <.icon name="hero-paint-brush" class="h-5 w-5" />
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
    </Layouts.app>
    """
  end

  def handle_event("start_game", %{"round_count" => count, "round_length" => length}, socket) do
    settings = %{
      round_count: String.to_integer(count),
      round_length: max(String.to_integer(length), 30)
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
