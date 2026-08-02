defmodule FlamingoWeb.HomeLive do
  use FlamingoWeb, :live_view

  alias Flamingo.{Avatar, Games}

  def mount(params, _session, socket) do
    room_code = params["room"] || ""

    {:ok,
     assign(socket,
       name: "",
       room_code: room_code,
       avatar: Avatar.random(),
       error: nil
     )}
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

        <.card class="w-full max-w-2xl p-6">
          <.form
            for={%{}}
            as={:lobby}
            phx-change="update_fields"
            phx-submit="submit_lobby"
            id="lobby-form"
          >
            <button
              type="submit"
              name="lobby[action]"
              value="auto"
              class="sr-only"
              aria-hidden="true"
              tabindex="-1"
            >
              Submit
            </button>
            <div class="grid gap-6 sm:grid-cols-[220px_1fr]">
              <section
                id="avatar-customizer"
                class="flex flex-col gap-3 border-b-2 border-border pb-6 sm:border-r-2 sm:border-b-0 sm:pr-6 sm:pb-0"
              >
                <div class="flex items-center justify-between gap-2">
                  <h2 class="font-hero text-2xl leading-none font-black">Your flamingo</h2>
                  <button
                    type="button"
                    phx-click="randomize_avatar"
                    id="randomize-avatar-button"
                    class="border-2 border-border bg-yellow-200 px-2 py-1 text-xs font-bold shadow-[2px_2px_0_#000] transition-transform hover:-translate-y-0.5 active:translate-x-0.5 active:translate-y-0.5 active:shadow-none"
                  >
                    Surprise me
                  </button>
                </div>

                <div class="mx-auto flex h-32 w-32 items-center justify-center border-2 border-border bg-pink-100 shadow-[3px_3px_0_#000]">
                  <.flamingo_avatar
                    avatar={@avatar}
                    class="h-28 w-28"
                    label="Your customized flamingo"
                  />
                </div>

                <fieldset>
                  <legend class="mb-1 text-xs font-bold uppercase tracking-wide">Feathers</legend>
                  <div class="flex justify-between gap-1">
                    <label
                      :for={
                        {color, index} <-
                          Enum.with_index(~w(#f472b6 #fb7185 #c084fc #fb923c #2dd4bf #facc15))
                      }
                      class="relative cursor-pointer"
                    >
                      <input
                        type="radio"
                        name="lobby[body]"
                        value={index}
                        checked={@avatar["body"] == index}
                        aria-label={"Feather color #{index + 1}"}
                        class="peer sr-only"
                      />
                      <span
                        class="block h-6 w-6 border-2 border-border transition-transform peer-checked:-translate-y-1 peer-checked:shadow-[2px_2px_0_#000]"
                        style={"background-color: #{color}"}
                      >
                      </span>
                    </label>
                  </div>
                </fieldset>

                <div :for={trait <- ~w(neck beak eyes tuft accessory)} class="space-y-1">
                  <label
                    for={"avatar-#{trait}-control"}
                    class="flex justify-between text-xs font-bold uppercase tracking-wide"
                  >
                    <span>{trait}</span>
                    <span class="text-pink-500">{Avatar.label(trait, @avatar[trait])}</span>
                  </label>
                  <input
                    type="range"
                    min="0"
                    max={Avatar.max(trait)}
                    value={@avatar[trait]}
                    name={"lobby[#{trait}]"}
                    class="nb-slider w-full"
                    id={"avatar-#{trait}-control"}
                  />
                </div>
              </section>

              <div class="flex flex-col justify-center gap-6 text-center">
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
                      type="submit"
                      name="lobby[action]"
                      value="join"
                      variant="neutral"
                      disabled={String.trim(@name) == "" || String.trim(@room_code) == ""}
                      id="join-button"
                    >
                      Join
                    </.button>
                  </div>
                  <p class="p-2 text-gray-700">or</p>
                  <.button
                    type="submit"
                    name="lobby[action]"
                    value="create"
                    variant="default"
                    class="w-full"
                    disabled={String.trim(@name) == "" || String.trim(@room_code) != ""}
                    id="create-room-button"
                  >
                    Create room
                  </.button>
                </div>
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
       avatar: Avatar.normalize(params),
       error: nil
     )}
  end

  def handle_event("randomize_avatar", _params, socket) do
    {:noreply, assign(socket, avatar: Avatar.random())}
  end

  def handle_event("create_room", _params, socket) do
    create_room(socket)
  end

  def handle_event("join_room", _params, socket) do
    join_room(socket)
  end

  def handle_event("submit_lobby", %{"lobby" => params}, socket) do
    socket =
      assign(socket,
        name: params["name"] || "",
        room_code: params["room_code"] || "",
        avatar: Avatar.normalize(params),
        error: nil
      )

    submit_lobby(socket, params["action"])
  end

  defp submit_lobby(socket, "create"), do: create_room(socket)
  defp submit_lobby(socket, "join"), do: join_room(socket)

  defp submit_lobby(socket, _action) do
    if String.trim(socket.assigns.room_code) == "" do
      create_room(socket)
    else
      join_room(socket)
    end
  end

  defp create_room(socket) do
    name = String.trim(socket.assigns.name)

    if name == "" do
      {:noreply, assign(socket, error: "Name cannot be empty")}
    else
      with {:ok, room_id} <- Games.create_room(),
           {:ok, player_id, _state} <- Games.join(room_id, name, socket.assigns.avatar) do
        {:noreply, push_navigate(socket, to: ~p"/game/#{room_id}?player_id=#{player_id}")}
      else
        _ -> {:noreply, assign(socket, error: "Failed to create room")}
      end
    end
  end

  defp join_room(socket) do
    name = String.trim(socket.assigns.name)
    code = String.trim(socket.assigns.room_code)

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "Name cannot be empty")}

      code == "" ->
        {:noreply, assign(socket, error: "Room code cannot be empty")}

      true ->
        case Games.join(code, name, socket.assigns.avatar) do
          {:ok, player_id, _state} ->
            {:noreply, push_navigate(socket, to: ~p"/game/#{code}?player_id=#{player_id}")}

          {:error, :not_found} ->
            {:noreply, assign(socket, error: "Room not found")}
        end
    end
  end
end
