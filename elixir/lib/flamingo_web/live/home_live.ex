defmodule FlamingoWeb.HomeLive do
  use FlamingoWeb, :live_view

  alias Flamingo.Games

  def mount(params, _session, socket) do
    room_code = params["room"] || ""
    {:ok, assign(socket, name: "", room_code: room_code, error: nil)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex h-full min-h-screen w-full flex-col items-center justify-center gap-4">
        <.card class="w-full max-w-xs bg-white px-6 py-4">
          <div class="flex justify-center">
            <.logo />
          </div>
        </.card>

        <.card class="w-full max-w-xs p-6 text-center">
          <.form for={%{}} as={:lobby} phx-change="update_fields" id="lobby-form">
            <div class="flex flex-col gap-6">
              <input
                type="text"
                value={@name}
                name="lobby[name]"
                placeholder="Enter your name"
                maxlength="20"
                class="rounded-base border-2 border-border bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                id="name-input"
              />

              <.separator />

              <div>
                <p :if={@error} class="mb-2 text-sm text-red-400">{@error}</p>
                <div class="flex flex-row items-start gap-2">
                  <input
                    type="text"
                    value={@room_code}
                    name="lobby[room_code]"
                    placeholder="Room name"
                    class="min-w-0 flex-1 rounded-base border-2 border-border bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                    id="room-code-input"
                  />
                  <.button
                    type="button"
                    variant="neutral"
                    phx-click="join_room"
                    disabled={String.trim(@name) == "" || String.trim(@room_code) == ""}
                    id="join-button"
                  >
                    Join
                  </.button>
                </div>
                <p class="p-2 text-gray-700">or</p>
                <.button
                  type="button"
                  variant="default"
                  class="w-full"
                  phx-click="create_room"
                  disabled={String.trim(@name) == "" || String.trim(@room_code) != ""}
                  id="create-room-button"
                >
                  Create room
                </.button>
              </div>
            </div>
          </.form>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("update_fields", %{"lobby" => params}, socket) do
    {:noreply,
     assign(socket,
       name: params["name"] || "",
       room_code: params["room_code"] || "",
       error: nil
     )}
  end

  def handle_event("create_room", _params, socket) do
    name = String.trim(socket.assigns.name)

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

  def handle_event("join_room", _params, socket) do
    name = String.trim(socket.assigns.name)
    code = String.trim(socket.assigns.room_code)

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
