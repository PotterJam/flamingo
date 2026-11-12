defmodule FlamingoWeb.HomeLive do
  use FlamingoWeb, :live_view

  alias Flamingo.{Accounts, Avatar, Rooms, SavedLobbies}

  def mount(%{"saved_lobby_name" => name} = params, session, socket) do
    case SavedLobbies.get_saved_lobby_by_name(name) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That saved lobby doesn't exist.")
         |> push_navigate(to: ~p"/")}

      saved_lobby ->
        {:ok, socket} = mount(Map.delete(params, "saved_lobby_name"), session, socket)
        {:ok, assign(socket, saved_lobby: saved_lobby)}
    end
  end

  def mount(params, _session, socket) do
    room_code = Map.get(params, "room_code", "")
    saved_avatar = socket.assigns.current_scope && socket.assigns.current_scope.user.avatar

    {:ok,
     assign(socket,
       name: "",
       room_code: room_code,
       saved_lobby: nil,
       avatar: saved_avatar || Avatar.random(),
       error: nil
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} changelog>
      <Layouts.account_menu current_scope={@current_scope} />
      <%!-- On phones the account menu takes the top row, so the logo drops below it. --%>
      <.card class={[
        "absolute top-4 left-4 z-30 bg-white px-5 py-2",
        @current_scope && "max-sm:top-20"
      ]}>
        <.logo />
      </.card>
      <.form
        for={%{}}
        as={:lobby}
        phx-submit="submit_lobby"
        id="lobby-form"
        class="grid min-h-screen lg:grid-cols-[minmax(0,40rem)_minmax(0,1fr)]"
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

        <section
          id="avatar-customizer"
          phx-hook="AvatarCustomizer"
          phx-update="ignore"
          data-account-id={@current_scope && @current_scope.user.id}
          data-saved-avatar={to_string(!!(@current_scope && @current_scope.user.avatar))}
          aria-label="Your avatar"
          class={[
            "relative isolate flex flex-col items-center justify-center gap-8 overflow-hidden border-b-2 border-border bg-pink-200 px-3 pt-28 pb-10 lg:border-r-2 lg:border-b-0 lg:pb-32",
            @current_scope && "max-sm:pt-40"
          ]}
        >
          <div
            aria-hidden="true"
            class="absolute inset-0 -z-10 bg-[url(/images/home/doodles.png)] bg-[length:560px] opacity-25"
          >
          </div>
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

          <div class="grid grid-cols-[auto_auto_auto] grid-rows-4 items-center gap-x-3 sm:gap-x-6">
            <%!-- The hook treats the first SVG in this section as the live avatar, so the card
                 comes first in the markup and the grid places the controls around it. --%>
            <div class="col-start-2 row-span-4 row-start-1 w-44 -rotate-2 rounded-2xl border-2 border-border bg-white p-2.5 shadow-[8px_8px_0_0_#000] sm:w-72 xl:w-80">
              <div class="relative flex items-end justify-center overflow-hidden rounded-xl border-2 border-border bg-sky-200">
                <div aria-hidden="true" class="absolute inset-x-0 bottom-0 h-[18%] bg-green-300">
                </div>
                <.flamingo_avatar
                  avatar={@avatar}
                  class="pointer-events-none relative mt-[10%] mb-[6%] aspect-[130/145] h-auto w-[82%] overflow-visible drop-shadow-md"
                  label="Your customized creature"
                />
              </div>
            </div>

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

            <div id="avatar-selector-rows" class="contents">
              <div
                :for={
                  {part, row} <-
                    Enum.zip(Avatar.parts(), ~w(row-start-1 row-start-2 row-start-3 row-start-4))
                }
                class="contents"
              >
                <div class={["col-start-1 flex items-center gap-1.5 justify-self-end sm:gap-2", row]}>
                  <div class="relative flex shrink-0">
                    <button
                      type="button"
                      phx-click={JS.show(to: "#avatar-#{part}-color-picker", display: "grid")}
                      id={"avatar-#{part}-color-button"}
                      aria-label={"Choose #{part} colour"}
                      class="group flex size-10 shrink-0 cursor-pointer items-center justify-center rounded-full border-2 border-border bg-white focus-visible:outline-2 focus-visible:outline-offset-2 sm:size-12 transition-transform hover:scale-105 hover:bg-pink-50 active:scale-95"
                    >
                      <span
                        class="size-6 rounded-full border-2 border-border sm:size-7"
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
                      class="absolute top-1/2 left-full z-50 ml-1 grid -translate-y-1/2 grid-cols-[repeat(4,1.75rem)] gap-1.5 rounded-base border-2 border-border bg-white p-2 shadow-shadow"
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
                          "size-7 cursor-pointer rounded-full border-2 border-border transition-transform hover:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2 aria-pressed:ring-2 aria-pressed:ring-black aria-pressed:ring-offset-1",
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
                    class="flex size-10 shrink-0 cursor-pointer items-center justify-center rounded-full border-2 border-border bg-white focus-visible:outline-2 focus-visible:outline-offset-2 sm:size-12 transition-transform hover:scale-105 hover:bg-pink-50 active:scale-95"
                  >
                    <.icon name={:arrow_left} class="size-5 sm:size-6" />
                  </button>
                </div>
                <div class={["col-start-3 flex items-center gap-1.5 sm:gap-2", row]}>
                  <button
                    type="button"
                    data-avatar-cycle
                    data-avatar-part={part}
                    data-avatar-direction="next"
                    id={"avatar-#{part}-next"}
                    aria-label={"Next #{part} animal"}
                    class="flex size-10 shrink-0 cursor-pointer items-center justify-center rounded-full border-2 border-border bg-white focus-visible:outline-2 focus-visible:outline-offset-2 sm:size-12 transition-transform hover:scale-105 hover:bg-pink-50 active:scale-95"
                  >
                    <.icon name={:arrow_right} class="size-5 sm:size-6" />
                  </button>
                  <button
                    type="button"
                    data-avatar-draw
                    data-avatar-part={part}
                    id={"avatar-#{part}-draw"}
                    aria-label={"Draw your own #{part}"}
                    title={"Draw your own #{part}"}
                    class="flex size-10 shrink-0 cursor-pointer items-center justify-center rounded-full border-2 border-border bg-white focus-visible:outline-2 focus-visible:outline-offset-2 sm:size-12 transition-transform hover:scale-105 hover:bg-pink-50 active:scale-95"
                  >
                    <.icon
                      name={:pencil}
                      class="size-5 sm:size-6"
                    />
                  </button>
                </div>
              </div>
            </div>
          </div>

          <button
            type="button"
            data-avatar-random
            id="randomize-avatar-button"
            class="group relative flex cursor-pointer items-center gap-1.5 rounded-full border-2 border-border bg-yellow-200 px-7 py-3 text-lg font-black transition-all hover:scale-105 hover:bg-yellow-300 focus-visible:outline-2 focus-visible:outline-offset-2 active:scale-95"
          >
            <.icon name={:dice_5} class="size-6 transition-transform group-hover:rotate-12" /> Random
          </button>

          <dialog
            id="avatar-drawing-editor"
            data-avatar-drawing-editor
            aria-labelledby="avatar-drawing-heading"
            class="m-auto max-h-[calc(100dvh-2rem)] w-[calc(100%-2rem)] max-w-xl overflow-y-auto rounded-base border-2 border-border bg-pink-50 p-4 shadow-shadow backdrop:bg-gray-950/40 sm:p-6"
          >
            <div class="mb-4 flex items-center justify-between gap-2">
              <div>
                <p class="text-[0.65rem] font-black tracking-[0.16em] text-pink-500 uppercase">
                  Make it yours
                </p>
                <h2 id="avatar-drawing-heading" class="text-lg font-black capitalize">
                  Draw your own <span data-avatar-drawing-title>part</span>
                </h2>
              </div>
              <div
                class="h-16 w-14 shrink-0"
                data-avatar-drawing-preview
                aria-label="Character preview"
              >
              </div>
            </div>

            <div class="mb-3 flex gap-2" role="group" aria-label="Brush size">
              <button
                :for={
                  {label, width, size} <- [
                    {"Fine", 2, "size-1"},
                    {"Regular", 6, "size-2"},
                    {"Bold", 10, "size-3"}
                  ]
                }
                type="button"
                id={"avatar-brush-#{width}"}
                data-avatar-brush={width}
                aria-pressed={to_string(width == 6)}
                class="flex flex-1 items-center justify-center gap-2 rounded-full border-2 border-border bg-white px-3 py-2 text-xs font-bold transition-colors hover:bg-pink-100 aria-pressed:bg-pink-200 focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                <span aria-hidden="true" class={["rounded-full bg-gray-900", size]}></span>
                {label}
              </button>
            </div>

            <svg
              data-avatar-drawing-surface
              viewBox="0 0 130 145"
              class="h-[min(45dvh,20rem)] w-full touch-none cursor-crosshair rounded-lg border-2 border-dashed border-pink-300 bg-white"
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
              <g
                data-avatar-drawing-strokes
                fill="none"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
              </g>
            </svg>

            <p class="mt-2 text-xs text-gray-600">
              Zoomed in for drawing. The pink area keeps this part inside your character.
            </p>
            <p
              data-avatar-drawing-status
              role="status"
              class="text-xs font-bold text-pink-700"
            >
            </p>

            <div class="mt-4 flex items-center justify-between gap-2">
              <div class="flex gap-1">
                <button
                  type="button"
                  data-avatar-drawing-undo
                  class="flex size-10 items-center justify-center rounded-full transition-colors hover:bg-white"
                  aria-label="Undo last stroke"
                >
                  <.icon name={:undo_2} class="size-4" />
                </button>
                <button
                  type="button"
                  data-avatar-drawing-clear
                  class="flex size-10 items-center justify-center rounded-full transition-colors hover:bg-white"
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
          </dialog>
        </section>

        <div
          id="lobby-fields-panel"
          class="flex flex-col items-center justify-center gap-6 px-4 pt-10 pb-36 *:w-full *:max-w-2xl sm:px-10 lg:pt-28"
        >
          <label for="name-input" class="block">
            <span class="mb-1 block text-sm font-bold">Your name</span>
            <input
              type="text"
              value={@name}
              name="lobby[name]"
              placeholder="Enter your name"
              maxlength="20"
              class="w-full rounded-base border-2 border-border bg-white px-4 py-3 text-lg shadow-shadow placeholder:text-gray-400 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
              id="name-input"
              phx-update="ignore"
            />
          </label>

          <p :if={@error} id="lobby-error" class="text-sm font-bold text-red-600">{@error}</p>

          <.box :if={@saved_lobby} class="bg-white p-5">
            <p class="text-xs text-gray-500">Saved lobby</p>
            <p id="saved-lobby-name" class="mb-4 truncate text-2xl font-black">
              {@saved_lobby.name}
            </p>
            <.button
              type="submit"
              name="lobby[action]"
              value="join_saved_lobby"
              variant="default"
              class="w-full py-3 text-lg font-black"
              disabled={String.trim(@name) == ""}
              id="join-saved-lobby-button"
              phx-update="ignore"
            >
              Join lobby
            </.button>
          </.box>

          <div :if={!@saved_lobby} class="grid gap-5 sm:grid-cols-2">
            <button
              type="submit"
              name="lobby[action]"
              value="create"
              disabled={String.trim(@name) == "" || String.trim(@room_code) != ""}
              id="create-room-button"
              phx-update="ignore"
              class="group relative flex min-h-64 cursor-pointer flex-col justify-end overflow-hidden rounded-base border-2 border-border bg-pink-300 p-5 text-left shadow-shadow transition-colors enabled:hover:bg-pink-400 focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed"
            >
              <img
                src={~p"/images/home/mode-classic.png"}
                alt=""
                class="absolute -top-2 right-0 w-40 group-disabled:opacity-60"
              />
              <span class="relative text-3xl font-black group-disabled:opacity-50">
                Create room
              </span>
              <span class="relative text-sm group-disabled:opacity-50">
                Start a game and share the code
              </span>
            </button>
            <.box class="relative flex min-h-64 flex-col justify-end gap-3 overflow-hidden bg-white p-5">
              <img
                src={~p"/images/home/mode-teams.png"}
                alt=""
                class="absolute -top-3 -right-3 w-44"
              />
              <h2 class="relative text-3xl font-black">Join a friend</h2>
              <div class="relative flex gap-2">
                <input
                  type="text"
                  value={@room_code}
                  name="lobby[room_code]"
                  placeholder="Room name"
                  aria-label="Room name"
                  class="min-w-0 flex-1 rounded-base border-2 border-border bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                  id="room-code-input"
                  phx-update="ignore"
                />
                <.button
                  type="submit"
                  name="lobby[action]"
                  value="join"
                  variant="neutral"
                  disabled={String.trim(@name) == "" || String.trim(@room_code) == ""}
                  id="join-button"
                  phx-update="ignore"
                  class="font-black"
                >
                  Join
                </.button>
              </div>
            </.box>
          </div>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  def handle_event("save_avatar", %{"avatar" => avatar}, socket) do
    if scope = socket.assigns.current_scope do
      case Accounts.update_avatar(scope, avatar) do
        {:ok, user} ->
          {:reply, %{saved: true},
           assign(socket, current_scope: %{scope | user: user}, avatar: user.avatar)}

        {:error, _changeset} ->
          {:reply, %{saved: false}, socket}
      end
    else
      {:reply, %{saved: false}, socket}
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

  defp submit_lobby(%{assigns: %{saved_lobby: %{}}} = socket, _action),
    do: join_saved_lobby(socket)

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

  defp join_saved_lobby(socket) do
    name = String.trim(socket.assigns.name)

    with {:name, true} <- {:name, name != ""},
         {:ok, room_id} <- Rooms.open_saved_lobby(socket.assigns.saved_lobby.name),
         {:ok, resume_token, _snapshot} <- Rooms.join(room_id, name, socket.assigns.avatar) do
      {:noreply, push_navigate(socket, to: ~p"/game/#{room_id}?resume_token=#{resume_token}")}
    else
      {:name, false} -> {:noreply, assign(socket, error: "Name cannot be empty")}
      _ -> {:noreply, assign(socket, error: "Couldn't open the saved lobby. Try again.")}
    end
  end
end
