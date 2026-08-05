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
       active_part: "head",
       error: nil
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex min-h-screen w-full flex-col items-center justify-center gap-4 px-4 py-8">
        <.card class="w-full max-w-xs bg-white px-6 py-4">
          <div class="flex justify-center">
            <.logo />
          </div>
        </.card>

        <.card class="w-full max-w-4xl overflow-hidden bg-white p-0">
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
            <div class="grid lg:grid-cols-[minmax(270px,0.8fr)_minmax(440px,1.2fr)]">
              <section
                id="avatar-customizer"
                class="relative flex flex-col items-center justify-center overflow-hidden border-b-2 border-border bg-pink-100 p-6 lg:border-r-2 lg:border-b-0"
              >
                <div class="absolute inset-x-0 top-0 flex items-center justify-between p-4">
                  <span class="rounded-full border-2 border-border bg-white px-3 py-1 text-[11px] font-black uppercase tracking-[0.18em]">
                    Your creature
                  </span>
                  <button
                    type="button"
                    phx-click="randomize_avatar"
                    id="randomize-avatar-button"
                    class="group flex items-center gap-1.5 rounded-full border-2 border-border bg-yellow-200 px-3 py-1 text-xs font-black shadow-[2px_2px_0_#000] transition-all hover:-translate-y-0.5 hover:shadow-[3px_3px_0_#000] active:translate-x-0.5 active:translate-y-0.5 active:shadow-none"
                  >
                    <.icon
                      name={:sparkles}
                      class="size-3.5 transition-transform group-hover:rotate-12"
                    /> Remix
                  </button>
                </div>

                <div class="mt-9 flex size-56 items-center justify-center rounded-full border-2 border-border bg-white shadow-[6px_6px_0_#000] sm:size-64">
                  <.flamingo_avatar
                    avatar={@avatar}
                    class="h-48 w-48 drop-shadow-sm sm:h-56 sm:w-56"
                    label="Your customized creature"
                  />
                </div>

                <div
                  class="mt-5 flex flex-wrap justify-center gap-2"
                  aria-label="Current creature recipe"
                >
                  <button
                    :for={part <- Avatar.parts()}
                    type="button"
                    phx-click="select_avatar_part"
                    phx-value-part={part}
                    class={[
                      "rounded-full border-2 border-border px-2.5 py-1 text-xs font-bold capitalize transition-all hover:-translate-y-0.5",
                      @active_part == part && "bg-pink-300 shadow-[2px_2px_0_#000]",
                      @active_part != part && "bg-white"
                    ]}
                  >
                    {part}: {Avatar.animal_label(@avatar[part])}
                  </button>
                </div>
              </section>

              <div class="flex flex-col">
                <section class="border-b-2 border-border p-5 sm:p-6">
                  <div class="mb-5">
                    <p class="text-xs font-black uppercase tracking-[0.2em] text-pink-500">
                      Build your own
                    </p>
                    <h2 class="font-hero text-3xl leading-tight font-black">
                      Mix. Match. Make it weird.
                    </h2>
                    <p class="mt-1 text-sm text-gray-600">
                      Choose one part at a time — your creature updates instantly.
                    </p>
                  </div>

                  <div
                    class="grid grid-cols-4 border-2 border-border bg-white"
                    role="tablist"
                    aria-label="Creature parts"
                  >
                    <button
                      :for={{part, index} <- Enum.with_index(Avatar.parts())}
                      type="button"
                      role="tab"
                      aria-selected={@active_part == part}
                      phx-click="select_avatar_part"
                      phx-value-part={part}
                      id={"avatar-part-#{part}"}
                      class={[
                        "relative px-2 py-3 text-xs font-black uppercase tracking-wide transition-colors sm:text-sm",
                        index > 0 && "border-l-2 border-border",
                        @active_part == part && "bg-pink-300",
                        @active_part != part && "hover:bg-pink-100"
                      ]}
                    >
                      <span class="block capitalize">{part}</span>
                      <span
                        :if={@active_part == part}
                        class="absolute inset-x-3 -bottom-0.5 h-1 bg-black"
                      >
                      </span>
                    </button>
                  </div>

                  <div
                    :for={part <- Avatar.parts()}
                    id={"avatar-#{part}-panel"}
                    role="tabpanel"
                    hidden={@active_part != part}
                    class="pt-5"
                  >
                    <fieldset>
                      <legend class="mb-2 text-xs font-black uppercase tracking-[0.16em] text-gray-500">
                        Pick an animal
                      </legend>
                      <div class="grid grid-cols-5 gap-2">
                        <label :for={{animal, index} <- Avatar.animals()} class="group cursor-pointer">
                          <input
                            type="radio"
                            name={"lobby[#{part}]"}
                            value={index}
                            checked={@avatar[part] == index}
                            aria-label={"#{part} animal: #{animal}"}
                            class="peer sr-only"
                          />
                          <span class="flex min-h-16 flex-col items-center justify-center gap-1 border-2 border-gray-300 bg-white px-1 py-2 text-center text-[10px] font-black uppercase transition-all group-hover:-translate-y-0.5 group-hover:border-black peer-checked:-translate-y-1 peer-checked:border-black peer-checked:bg-yellow-100 peer-checked:shadow-[3px_3px_0_#000] sm:text-xs">
                            <span class="text-lg leading-none" aria-hidden="true">
                              {Enum.at(["🦩", "🐱", "🐸", "🐰", "🦆"], index)}
                            </span>
                            {animal}
                          </span>
                        </label>
                      </div>
                    </fieldset>

                    <fieldset class="mt-5">
                      <legend class="mb-2 text-xs font-black uppercase tracking-[0.16em] text-gray-500">
                        Pick a colour
                      </legend>
                      <div class="flex flex-wrap gap-2.5">
                        <label :for={{color, index} <- Avatar.colors()} class="group cursor-pointer">
                          <input
                            type="radio"
                            name={"lobby[#{part}_color]"}
                            value={index}
                            checked={@avatar["#{part}_color"] == index}
                            aria-label={"#{part} colour #{index + 1}"}
                            class="peer sr-only"
                          />
                          <span
                            class="block size-8 rounded-full border-2 border-border transition-all group-hover:scale-110 peer-checked:-translate-y-1 peer-checked:shadow-[2px_3px_0_#000] peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2"
                            style={"background-color: #{color}"}
                          >
                          </span>
                        </label>
                      </div>
                    </fieldset>
                  </div>
                </section>

                <section class="grid gap-4 bg-gray-50 p-5 sm:grid-cols-2 sm:p-6">
                  <input
                    type="text"
                    value={@name}
                    name="lobby[name]"
                    placeholder="Enter your name"
                    maxlength="20"
                    class="rounded-base border-2 border-border bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                    id="name-input"
                  />

                  <div class="sm:col-span-2">
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
                </section>
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

  def handle_event("select_avatar_part", %{"part" => part}, socket) do
    if part in Avatar.parts() do
      {:noreply, assign(socket, active_part: part)}
    else
      {:noreply, socket}
    end
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
