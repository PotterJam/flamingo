defmodule FlamingoWeb.LobbyLive do
  use FlamingoWeb, :live_view

  alias Flamingo.{Rooms, SavedLobbies}
  alias FlamingoWeb.{GameModes, RoomRoute}

  def mount(%{"room_id" => room_id}, _session, socket) do
    {:ok,
     assign(socket,
       room_id: room_id,
       resume_token: nil,
       player_id: nil,
       players: %{},
       player_order: [],
       host_id: nil,
       mode: GameModes.default(),
       settings_form: to_form(%{}, as: :settings),
       saved_lobby: nil,
       saved_lobby_form: nil
     )}
  end

  def handle_params(%{"resume_token" => token}, _uri, socket) do
    socket = assign(socket, :resume_token, token)

    if connected?(socket) do
      case Rooms.connect(socket.assigns.room_id, token) do
        {:ok, snapshot} -> {:noreply, apply_snapshot(socket, snapshot)}
        {:error, _reason} -> {:noreply, push_navigate(socket, to: ~p"/")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/")}

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      background={["grid-background transition-colors duration-300", @mode.theme().lobby]}
      changelog
    >
      <div class="flex h-screen w-full items-center justify-center px-4 py-8">
        <div class="flex h-full w-full max-w-3xl flex-col items-center justify-center gap-4">
          <%= if @player_id == @host_id do %>
            <fieldset class="w-full max-w-2xl">
              <legend class="sr-only">Game mode</legend>
              <div
                id="game-mode-selector"
                class="flex flex-wrap justify-center gap-2"
                role="radiogroup"
              >
                <button
                  :for={mode <- GameModes.all()}
                  type="button"
                  id={"game-mode-#{mode.id()}"}
                  phx-click="select_game_mode"
                  phx-value-mode={mode.id()}
                  role="radio"
                  aria-checked={to_string(mode == @mode)}
                  class={[
                    "flex h-8 min-w-24 cursor-pointer items-center justify-center rounded-full border-2 border-border px-3 py-1 text-center text-sm font-bold whitespace-nowrap shadow-rounded transition-all duration-200 hover:-translate-y-0.5 focus-visible:-translate-y-0.5 focus-visible:outline-2 focus-visible:outline-offset-2 active:translate-y-0 active:shadow-none",
                    if(mode == @mode,
                      do: mode.theme().selected,
                      else: ["bg-gray-200", mode.theme().hover]
                    )
                  ]}
                >
                  {mode.title()}
                </button>
              </div>
            </fieldset>
            <p
              id="game-mode-description"
              class="min-h-6 max-w-lg px-3 text-center text-xs text-gray-700"
              aria-live="polite"
            >
              {@mode.description()}
            </p>
          <% end %>
          <.card class="flex h-[65%] w-full flex-row gap-0 bg-white p-0">
            <div class="flex flex-1 flex-col gap-4 border-r-2 border-border p-4">
              <h2 class="text-xl font-bold">Players</h2>
              <ul class="space-y-2">
                <%= for pid <- @player_order do %>
                  <li id={"lobby-player-row-#{pid}"} class="flex min-w-0 items-center gap-2">
                    <.flamingo_avatar
                      avatar={Map.get(Map.get(@players, pid), :avatar, %{})}
                      class="h-12 w-12 shrink-0"
                      label={"#{Map.get(@players, pid).name}'s avatar"}
                    />
                    <span class="min-w-0 flex-1 truncate">{Map.get(@players, pid).name}</span>
                  </li>
                <% end %>
              </ul>
            </div>
            <%= if @player_id == @host_id do %>
              <div class="flex h-full min-h-0 w-full flex-[3] flex-col overflow-hidden">
                <.form
                  for={@settings_form}
                  phx-change="update_settings"
                  phx-submit="start_game"
                  class="min-h-0 flex-1 overflow-y-auto p-4"
                  id="settings-form"
                >
                  {@mode.settings(%{form: @settings_form})}
                </.form>
                <div class="flex w-full shrink-0 flex-col gap-4 border-t-2 border-border p-4">
                  <div :if={@saved_lobby} id="saved-lobby-share">
                    <label class="text-sm">Saved lobby</label>
                    <div class="flex flex-row items-center justify-between gap-2">
                      <p id="saved-lobby-name" class="min-w-0 truncate font-bold">{@saved_lobby}</p>
                      <.button
                        variant="outline"
                        class="shrink-0 text-xs"
                        on_confirm_click={
                          JS.dispatch("phx:copy",
                            detail: %{text: url(~p"/saved-lobby/#{@saved_lobby}")}
                          )
                        }
                        id="copy-link-button"
                      >
                        Copy link
                      </.button>
                    </div>
                  </div>
                  <.form
                    :if={!@saved_lobby && @saved_lobby_form}
                    for={@saved_lobby_form}
                    id="save-lobby-form"
                    phx-change="validate_saved_lobby"
                    phx-submit="save_lobby"
                  >
                    <label for="saved-lobby-name-input" class="text-sm">Lobby name</label>
                    <div class="mt-1 flex flex-row flex-wrap items-start gap-x-1 gap-y-2">
                      <div class="min-w-0 flex-[1_1_10rem] [&>.fieldset]:py-0">
                        <.input
                          field={@saved_lobby_form[:name]}
                          id="saved-lobby-name-input"
                          placeholder="thursday-crew"
                          maxlength="30"
                          autocomplete="off"
                          phx-debounce="200"
                          phx-mounted={JS.focus()}
                        />
                      </div>
                      <div class="ml-auto flex flex-wrap justify-end gap-1">
                        <.button
                          type="button"
                          variant="ghost"
                          class="h-10 text-xs"
                          phx-click="cancel_saving_lobby"
                          id="cancel-save-lobby-button"
                        >
                          Cancel
                        </.button>
                        <.button
                          type="submit"
                          variant="outline"
                          class="h-10 text-xs"
                          disabled={!@saved_lobby_form.source.valid?}
                          id="confirm-save-lobby-button"
                        >
                          Save
                        </.button>
                      </div>
                    </div>
                  </.form>
                  <div :if={!@saved_lobby && !@saved_lobby_form} id="room-share">
                    <label class="text-sm">Room name</label>
                    <div class="flex flex-row flex-wrap items-center justify-between gap-x-2 gap-y-1">
                      <p class="font-bold">{@room_id}</p>
                      <div class="ml-auto flex flex-wrap justify-end gap-1 whitespace-nowrap">
                        <.button
                          :if={@current_scope}
                          variant="ghost"
                          class="inline-flex items-center gap-1 text-xs"
                          phx-click="start_saving_lobby"
                          id="save-lobby-button"
                        >
                          <.icon name={:bookmark} class="size-3.5" /> Save lobby
                        </.button>
                        <.button
                          variant="ghost"
                          class="text-xs"
                          on_confirm_click={JS.dispatch("phx:copy", detail: %{text: @room_id})}
                          id="copy-name-button"
                        >
                          Copy name
                        </.button>
                        <.button
                          variant="outline"
                          class="text-xs"
                          on_confirm_click={
                            JS.dispatch("phx:copy", detail: %{text: url(~p"/join/#{@room_id}")})
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
                    type="submit"
                    form="settings-form"
                    disabled={map_size(@players) < @mode.min_players()}
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
        </div>
      </div>
      <.clipboard_handler />
    </Layouts.app>
    """
  end

  def handle_event("select_game_mode", %{"mode" => value}, socket) do
    case GameModes.from_param(value) do
      nil -> {:noreply, socket}
      mode -> {:noreply, socket |> assign(:mode, mode) |> sync_lobby()}
    end
  end

  def handle_event("update_settings", %{"settings" => params}, socket),
    do: {:noreply, socket |> put_draft(params) |> sync_lobby()}

  def handle_event("start_saving_lobby", _params, socket),
    do: {:noreply, assign(socket, :saved_lobby_form, to_form(SavedLobbies.change_saved_lobby()))}

  def handle_event("cancel_saving_lobby", _params, socket),
    do: {:noreply, assign(socket, :saved_lobby_form, nil)}

  def handle_event("validate_saved_lobby", %{"saved_lobby" => params}, socket) do
    changeset = SavedLobbies.change_saved_lobby(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :saved_lobby_form, to_form(changeset))}
  end

  def handle_event("save_lobby", %{"saved_lobby" => params}, socket) do
    with %{} = scope <- socket.assigns.current_scope,
         {:ok, saved_lobby} <- SavedLobbies.save_room(scope, socket.assigns.room_id, params) do
      {:noreply,
       socket
       |> assign(saved_lobby: saved_lobby.name, saved_lobby_form: nil)
       |> put_flash(:success, "Lobby saved. Its link will always bring everyone back here.")}
    else
      nil ->
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :saved_lobby_form, to_form(changeset))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:saved_lobby_form, nil)
         |> put_flash(:error, save_lobby_error(reason))}
    end
  end

  def handle_event("start_game", params, socket) do
    socket = socket |> put_draft(Map.get(params, "settings", %{})) |> sync_lobby()
    %{mode: mode, room_id: room_id, settings_form: form} = socket.assigns

    with {:ok, settings} <- mode.parse_settings(form.params),
         :ok <- Rooms.start_game(room_id, mode.id(), mode.engine(), settings) do
      {:noreply, socket}
    else
      {:error, errors} when is_list(errors) ->
        {:noreply,
         assign(socket, :settings_form, to_form(form.params, as: :settings, errors: errors))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot start game: #{reason}")}
    end
  end

  # The draft keeps fields the current mode doesn't show, so they carry over
  # when the host switches to a mode that does.
  defp put_draft(socket, params) do
    params = Map.merge(socket.assigns.settings_form.params, params)
    assign(socket, :settings_form, to_form(params, as: :settings))
  end

  # The room remembers the host's choice for other viewers and the next lobby.
  defp sync_lobby(socket) do
    %{room_id: room_id, mode: mode, settings_form: form} = socket.assigns
    Rooms.update_lobby(room_id, mode.id(), form.params)
    socket
  end

  defp save_lobby_error(:not_host), do: "Only the host can save this lobby."
  defp save_lobby_error(:already_saved), do: "This lobby is already saved."
  defp save_lobby_error(_reason), do: "Couldn't save this lobby. Try again."

  def handle_info({:room_snapshot, snapshot}, socket),
    do: {:noreply, apply_snapshot(socket, snapshot)}

  defp apply_snapshot(socket, %{phase: :lobby} = snapshot) do
    initial? = is_nil(socket.assigns.player_id)
    old_count = map_size(socket.assigns.players)

    if snapshot.saved_lobby && snapshot.saved_lobby != socket.assigns.saved_lobby &&
         socket.assigns.current_scope do
      SavedLobbies.record_member(socket.assigns.current_scope, snapshot.saved_lobby)
    end

    # Load the room's draft when this viewer first becomes the host; later
    # snapshots would overwrite what they are typing.
    socket =
      if snapshot.viewer_id == snapshot.host_id and
           (initial? or socket.assigns.host_id != snapshot.host_id),
         do: assign(socket, :settings_form, to_form(snapshot.settings_draft, as: :settings)),
         else: socket

    socket =
      assign(socket,
        player_id: snapshot.viewer_id,
        players: snapshot.players,
        player_order: snapshot.player_order,
        host_id: snapshot.host_id,
        mode: GameModes.get(snapshot.game_mode),
        saved_lobby: snapshot.saved_lobby
      )

    socket =
      if initial?,
        do: push_event(socket, "sync_round_audio", %{music: false, countdown_end: nil}),
        else: socket

    if initial? or map_size(snapshot.players) > old_count,
      do: push_event(socket, "play_sound", %{sound: "join"}),
      else: socket
  end

  defp apply_snapshot(socket, snapshot) do
    RoomRoute.navigate(socket, snapshot)
  end
end
