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
      Game started!
    </div>
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

  def handle_info({:players_updated, players, player_order, host_id}, socket) do
    {:noreply, assign(socket, players: players, player_order: player_order, host_id: host_id)}
  end

  def handle_info({:game_started, round_count, round_length}, socket) do
    {:noreply, assign(socket, phase: :playing, round_count: round_count, round_length: round_length)}
  end

  def terminate(_reason, socket) do
    if Map.has_key?(socket.assigns, :room_id) and Map.has_key?(socket.assigns, :player_id) do
      Games.leave(socket.assigns.room_id, socket.assigns.player_id)
    end
  end
end
