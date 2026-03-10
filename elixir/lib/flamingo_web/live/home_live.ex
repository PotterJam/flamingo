defmodule FlamingoWeb.HomeLive do
  use FlamingoWeb, :live_view

  alias Flamingo.Games

  def mount(_params, _session, socket) do
    {:ok, assign(socket, create_name: "", join_name: "", join_code: "", error: nil)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1>Flamingo</h1>

      <div>
        <h2>Create Room</h2>
        <form phx-submit="create_room">
          <input type="text" name="name" value={@create_name} placeholder="Your name" required />
          <button type="submit">Create Room</button>
        </form>
      </div>

      <div>
        <h2>Join Room</h2>
        <form phx-submit="join_room">
          <input type="text" name="name" value={@join_name} placeholder="Your name" required />
          <input type="text" name="code" value={@join_code} placeholder="Room code" required />
          <button type="submit">Join Room</button>
        </form>
      </div>

      <p :if={@error} style="color: red;">{@error}</p>
    </Layouts.app>
    """
  end

  def handle_event("create_room", %{"name" => name}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, assign(socket, error: "Name cannot be empty")}
    else
      with {:ok, room_id} <- Games.create_room(),
           {:ok, player_id, _state} <- Games.join(room_id, name) do
        {:noreply, push_navigate(socket, to: ~p"/game/#{room_id}?player_id=#{player_id}")}
      else
        _ -> {:noreply, assign(socket, error: "Failed to create room")}
      end
    end
  end

  def handle_event("join_room", %{"name" => name, "code" => code}, socket) do
    name = String.trim(name)
    code = String.trim(code)

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "Name cannot be empty")}

      code == "" ->
        {:noreply, assign(socket, error: "Room code cannot be empty")}

      true ->
        case Games.join(code, name) do
          {:ok, player_id, _state} ->
            {:noreply, push_navigate(socket, to: ~p"/game/#{code}?player_id=#{player_id}")}

          {:error, :not_found} ->
            {:noreply, assign(socket, error: "Room not found")}
        end
    end
  end
end
