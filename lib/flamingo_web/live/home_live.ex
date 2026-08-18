defmodule FlamingoWeb.HomeLive do
  use FlamingoWeb, :live_view

  alias Flamingo.{Avatar, Rooms}

  def mount(params, _session, socket) do
    room_code = Map.get(params, "room_code", "")

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
      <div class="flex min-h-screen w-full flex-col items-center justify-center gap-4 px-4 py-8 max-[359px]:px-1">
        <.card class="w-full max-w-xs bg-white px-6 py-4">
          <div class="flex justify-center">
            <.logo />
          </div>
        </.card>

        <.card class="w-full max-w-[44rem] overflow-visible bg-white p-0">
          <.form
            for={%{}}
            as={:lobby}
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

            <div class="grid lg:grid-cols-[minmax(400px,4fr)_minmax(300px,3fr)]">
              <section
                id="avatar-customizer"
                phx-hook="AvatarCustomizer"
                phx-update="ignore"
                class="relative flex flex-col items-center justify-center bg-white px-3 py-5 max-[359px]:px-1 sm:p-4"
              >
                <input
                  :for={part <- Avatar.parts()}
                  type="hidden"
                  id={"avatar-#{part}-input"}
                  name={"lobby[#{part}]"}
                  value={@avatar[part]}
                />
                <input
                  :for={part <- Avatar.parts()}
                  type="hidden"
                  id={"avatar-#{part}-color-input"}
                  name={"lobby[#{part}_color]"}
                  value={@avatar["#{part}_color"]}
                />
                <input
                  :for={part <- Avatar.parts()}
                  type="hidden"
                  id={"avatar-#{part}-drawing-input"}
                  name={"lobby[#{part}_drawing]"}
                  value={@avatar["#{part}_drawing"]}
                />

                <div class="relative h-56 w-full max-w-xl sm:h-64">
                  <.flamingo_avatar
                    avatar={@avatar}
                    class="pointer-events-none absolute top-[43%] left-1/2 z-10 h-30 w-24 -translate-x-1/2 -translate-y-1/2 drop-shadow-sm sm:h-40 sm:w-32"
                    label="Your customized creature"
                  />

                  <template
                    :for={{_animal, index} <- Avatar.animals()}
                    data-avatar-template={index}
                  >
                    <.flamingo_avatar avatar={
                      Map.merge(@avatar, %{
                        "head" => index,
                        "body" => index,
                        "legs" => index,
                        "feet" => index
                      })
                    } />
                  </template>

                  <div
                    id="avatar-selector-rows"
                    class="absolute inset-x-0 top-1/2 z-20 flex -translate-y-1/2 flex-col gap-3"
                  >
                    <div
                      :for={part <- Avatar.parts()}
                      class="grid grid-cols-[minmax(4rem,1fr)_6rem_minmax(4.5rem,1fr)] items-center min-[360px]:grid-cols-[minmax(4rem,1fr)_8rem_minmax(4.5rem,1fr)] sm:grid-cols-[minmax(6rem,1fr)_10rem_minmax(7rem,1fr)]"
                    >
                      <div class="flex items-center justify-end gap-1 sm:gap-2">
                        <div class="relative flex shrink-0">
                          <button
                            type="button"
                            phx-click={
                              JS.show(
                                to: "#avatar-#{part}-color-picker",
                                display: "grid"
                              )
                            }
                            id={"avatar-#{part}-color-button"}
                            aria-label={"Choose #{part} colour"}
                            class="group flex size-8 shrink-0 items-center justify-center transition-transform hover:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2 active:scale-95 sm:size-9"
                          >
                            <span
                              class="size-6 rounded-full border-2 border-border transition-transform group-hover:scale-110 max-[359px]:size-5 sm:size-[1.6rem]"
                              style={"background-color: #{Avatar.color(@avatar["#{part}_color"])}"}
                            >
                            </span>
                          </button>

                          <div
                            id={"avatar-#{part}-color-picker"}
                            role="group"
                            aria-label={"Choose #{part} colour"}
                            phx-click-away={JS.hide(to: "#avatar-#{part}-color-picker")}
                            phx-window-keydown={JS.hide(to: "#avatar-#{part}-color-picker")}
                            phx-key="escape"
                            style="display: none"
                            class="absolute top-1/2 right-[calc(100%-0.25rem)] z-50 grid -translate-y-1/2 grid-cols-[repeat(2,1.25rem)] gap-1 rounded-md border-2 border-border bg-white p-0.5 max-[359px]:right-[calc(100%-0.375rem)]"
                          >
                            <button
                              :for={{color, index} <- Avatar.colors()}
                              type="button"
                              phx-click={JS.hide(to: "#avatar-#{part}-color-picker")}
                              data-avatar-color-option
                              data-avatar-part={part}
                              data-avatar-value={index}
                              data-avatar-color={color}
                              id={"avatar-#{part}-color-option-#{index}"}
                              aria-label={"Select colour #{index + 1}"}
                              aria-pressed={to_string(@avatar["#{part}_color"] == index)}
                              class={[
                                "size-5 rounded-full transition-transform hover:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2",
                                @avatar["#{part}_color"] == index && "scale-110"
                              ]}
                              style={"background-color: #{color}"}
                            >
                            </button>
                          </div>
                        </div>
                        <button
                          type="button"
                          data-avatar-cycle
                          data-avatar-part={part}
                          data-avatar-direction="previous"
                          id={"avatar-#{part}-previous"}
                          aria-label={"Previous #{part} animal"}
                          class="flex size-8 shrink-0 items-center justify-center transition-transform hover:-translate-x-0.5 hover:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2 active:scale-95 sm:size-9"
                        >
                          <.icon
                            name={:chevron_left}
                            class="size-5 stroke-[3] max-[359px]:size-4 sm:size-5"
                          />
                        </button>
                      </div>

                      <span aria-hidden="true"></span>

                      <div class="flex min-w-0 items-center gap-1 sm:gap-2">
                        <button
                          type="button"
                          data-avatar-cycle
                          data-avatar-part={part}
                          data-avatar-direction="next"
                          id={"avatar-#{part}-next"}
                          aria-label={"Next #{part} animal"}
                          class="flex size-8 shrink-0 items-center justify-center transition-transform hover:translate-x-0.5 hover:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2 active:scale-95 sm:size-9"
                        >
                          <.icon
                            name={:chevron_right}
                            class="size-5 stroke-[3] max-[359px]:size-4 sm:size-5"
                          />
                        </button>
                        <button
                          type="button"
                          data-avatar-draw
                          data-avatar-part={part}
                          id={"avatar-#{part}-draw"}
                          aria-label={"Draw your own #{part}"}
                          title={"Draw your own #{part}"}
                          class="group flex size-7 shrink-0 items-center justify-center text-gray-500 transition-all hover:-translate-y-0.5 hover:text-pink-500 focus-visible:outline-2 focus-visible:outline-offset-2 active:translate-y-0 sm:size-8"
                        >
                          <.icon
                            name={:pencil}
                            class="size-4 transition-transform group-hover:-rotate-6"
                          />
                        </button>
                      </div>
                    </div>
                  </div>

                  <div
                    data-avatar-drawing-editor
                    hidden
                    class="absolute inset-x-0 top-1/2 z-40 mx-auto w-[min(100%,22rem)] -translate-y-1/2 rounded-base border-2 border-border bg-pink-50 p-3 shadow-shadow"
                  >
                    <div class="mb-2 flex items-center justify-between gap-2">
                      <div>
                        <p class="text-[0.65rem] font-black tracking-[0.16em] text-pink-500 uppercase">
                          Make it yours
                        </p>
                        <h2 class="text-sm font-black capitalize">
                          Draw your own <span data-avatar-drawing-title>part</span>
                        </h2>
                      </div>
                      <span class="rounded-full border-2 border-border bg-yellow-200 px-2 py-0.5 text-[0.65rem] font-bold">
                        Draw in the glow
                      </span>
                    </div>

                    <svg
                      data-avatar-drawing-surface
                      viewBox="0 0 130 145"
                      class="h-36 w-full touch-none cursor-crosshair rounded-lg border-2 border-dashed border-pink-300 bg-white"
                      aria-label="Drawing surface"
                    >
                      <rect
                        data-avatar-drawing-guide
                        x="12"
                        y="2"
                        width="106"
                        height="66"
                        rx="10"
                        fill="#fce7f3"
                      />
                      <path
                        data-avatar-drawing-shadow
                        fill="none"
                        stroke="#111827"
                        stroke-width="10"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      />
                      <path
                        data-avatar-drawing-path
                        fill="none"
                        stroke="#f472b6"
                        stroke-width="6"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      />
                    </svg>

                    <div class="mt-2 flex items-center justify-between gap-2">
                      <div class="flex gap-1">
                        <button
                          type="button"
                          data-avatar-drawing-undo
                          class="flex size-8 items-center justify-center rounded-full transition-colors hover:bg-white"
                          aria-label="Undo last stroke"
                        >
                          <.icon name={:undo_2} class="size-4" />
                        </button>
                        <button
                          type="button"
                          data-avatar-drawing-clear
                          class="flex size-8 items-center justify-center rounded-full transition-colors hover:bg-white"
                          aria-label="Clear drawing"
                        >
                          <.icon name={:trash_2} class="size-4" />
                        </button>
                      </div>
                      <div class="flex gap-2">
                        <button
                          type="button"
                          data-avatar-drawing-cancel
                          class="rounded-full px-3 py-1.5 text-xs font-bold transition-colors hover:bg-white"
                        >
                          Cancel
                        </button>
                        <button
                          type="button"
                          data-avatar-drawing-save
                          class="rounded-full border-2 border-border bg-pink-400 px-4 py-1 text-xs font-black text-white transition-all hover:-translate-y-0.5 hover:bg-pink-500 active:translate-y-0"
                        >
                          Use drawing
                        </button>
                      </div>
                    </div>
                  </div>

                  <button
                    type="button"
                    data-avatar-random
                    id="randomize-avatar-button"
                    class="group absolute top-[85%] left-1/2 flex -translate-x-1/2 items-center gap-1.5 rounded-full border-2 border-border bg-yellow-200 px-3 py-1 text-xs font-black transition-all hover:-translate-y-0.5 hover:bg-yellow-300 focus-visible:outline-2 focus-visible:outline-offset-2 active:scale-95"
                  >
                    <.icon
                      name={:dice_5}
                      class="size-3.5 transition-transform group-hover:rotate-12"
                    /> Random
                  </button>
                </div>
              </section>

              <div id="lobby-fields-panel" class="flex items-center bg-white">
                <section class="grid w-full gap-4 p-5 sm:grid-cols-2 sm:p-6 lg:grid-cols-1 lg:p-6">
                  <input
                    type="text"
                    value={@name}
                    name="lobby[name]"
                    placeholder="Enter your name"
                    maxlength="20"
                    class="rounded-base border-2 border-border bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                    id="name-input"
                  />

                  <div class="sm:col-span-2 lg:col-span-1">
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
                    <p id="lobby-or-divider" class="p-2 text-center text-gray-700">or</p>
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
      with {:ok, room_id} <- Rooms.create_room(),
           {:ok, resume_token, _snapshot} <- Rooms.join(room_id, name, socket.assigns.avatar) do
        {:noreply, push_navigate(socket, to: ~p"/game/#{room_id}?resume_token=#{resume_token}")}
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
        case Rooms.join(code, name, socket.assigns.avatar) do
          {:ok, resume_token, _snapshot} ->
            {:noreply, push_navigate(socket, to: ~p"/game/#{code}?resume_token=#{resume_token}")}

          {:error, :not_found} ->
            {:noreply, assign(socket, error: "Room not found")}
        end
    end
  end
end
