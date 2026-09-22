defmodule FlamingoWeb.LobbyLive do
  use FlamingoWeb, :live_view

  alias Flamingo.{GameSettings, Rooms, Words}
  alias FlamingoWeb.RoomRoute

  @turn_length_range GameSettings.turn_length_range()

  def mount(%{"room_id" => room_id}, _session, socket) do
    defaults = GameSettings.defaults()

    {:ok,
     assign(socket,
       room_id: room_id,
       resume_token: nil,
       player_id: nil,
       players: %{},
       player_order: [],
       host_id: nil,
       round_count: 3,
       turn_length: defaults.turn_length,
       game_mode: :scribble,
       game_variant: :classic,
       word_list: defaults.word_list,
       custom_words: "",
       custom_word_count: 0,
       custom_words_error: nil,
       settings_form: to_form(%{}, as: :settings)
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

  defp selected_game_mode(:telephone, _variant), do: "telephone"
  defp selected_game_mode(:scribble, :constraint_roulette), do: "constraint_roulette"
  defp selected_game_mode(_mode, _variant), do: "classic"

  defp lobby_background(:telephone, _variant),
    do: "grid-background lobby-background-telephone transition-colors duration-300"

  defp lobby_background(:scribble, :constraint_roulette),
    do: "grid-background lobby-background-constraint transition-colors duration-300"

  defp lobby_background(_mode, _variant),
    do: "grid-background lobby-background-classic transition-colors duration-300"

  defp game_mode_description("constraint_roulette"),
    do: "Like classic but with a little bit of spice"

  defp game_mode_description("telephone"),
    do: "Cycle through guessing and drawing before revealing the chaos"

  defp game_mode_description(_mode),
    do: "Take turns drawing a word while everyone guesses"

  defp game_mode_option_class("constraint_roulette", selected?) do
    if selected?, do: "bg-purple-400", else: "bg-gray-200 hover:bg-purple-400"
  end

  defp game_mode_option_class("telephone", selected?) do
    if selected?, do: "bg-sky-400", else: "bg-gray-200 hover:bg-sky-400"
  end

  defp game_mode_option_class(_mode, selected?) do
    if selected?, do: "bg-pink-300", else: "bg-gray-200 hover:bg-pink-300"
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        min_turn_length: @turn_length_range.first,
        max_turn_length: @turn_length_range.last
      )

    ~H"""
    <Layouts.app flash={@flash} background={lobby_background(@game_mode, @game_variant)}>
      <div class="flex h-screen w-full items-center justify-center px-4 py-8">
        <div class="flex h-full w-full max-w-3xl flex-col items-center justify-center gap-4">
          <%= if @player_id == @host_id do %>
            <fieldset class="w-full max-w-sm">
              <legend class="sr-only">Game mode</legend>
              <div id="game-mode-selector" class="grid grid-cols-3 gap-2" role="radiogroup">
                <button
                  :for={
                    {value, title} <- [
                      {"classic", "Classic"},
                      {"constraint_roulette", "Roulette"},
                      {"telephone", "Telephone"}
                    ]
                  }
                  type="button"
                  id={"game-mode-#{value}"}
                  phx-click="select_game_mode"
                  phx-value-mode={value}
                  role="radio"
                  aria-checked={
                    if(selected_game_mode(@game_mode, @game_variant) == value,
                      do: "true",
                      else: "false"
                    )
                  }
                  class={[
                    "flex h-8 cursor-pointer items-center justify-center rounded-full border-2 border-border px-3 py-1 text-center text-sm font-bold shadow-rounded transition-all duration-200 hover:-translate-y-0.5 focus-visible:-translate-y-0.5 focus-visible:outline-2 focus-visible:outline-offset-2 active:translate-y-0 active:shadow-none",
                    game_mode_option_class(
                      value,
                      selected_game_mode(@game_mode, @game_variant) == value
                    )
                  ]}
                >
                  {title}
                </button>
              </div>
            </fieldset>
            <p
              id="game-mode-description"
              class="min-h-6 max-w-lg px-3 text-center text-xs text-gray-700"
              aria-live="polite"
            >
              {game_mode_description(selected_game_mode(@game_mode, @game_variant))}
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
                  <input
                    type="hidden"
                    name={@settings_form[:game_mode].name}
                    value={selected_game_mode(@game_mode, @game_variant)}
                  />
                  <div class="space-y-1">
                    <div class="flex w-full justify-between">
                      <label for="round-count-slider" class="text-sm">Rounds</label>
                      <span class="text-sm">{@round_count}</span>
                    </div>
                    <.input
                      field={@settings_form[:round_count]}
                      type="range"
                      min="1"
                      max="5"
                      value={@round_count}
                      class="w-full"
                      id="round-count-slider"
                    />
                  </div>
                  <div class="mt-4">
                    <label class="block text-sm">Round length(s)</label>
                    <div class="mt-1 flex w-48 items-center">
                      <.input
                        type="number"
                        min={@min_turn_length}
                        max={@max_turn_length}
                        value={@turn_length}
                        name={@settings_form[:turn_length].name}
                        class="w-full rounded-base border-2 border-border bg-white px-3 py-2 text-sm focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                        id="round-length-input"
                      />
                    </div>
                  </div>
                  <div class="mt-4 space-y-1">
                    <.input
                      field={@settings_form[:word_list]}
                      type="select"
                      label="Word theme"
                      options={Words.word_list_options()}
                      id="word-list-select"
                    />
                  </div>
                  <div :if={@word_list == :custom} id="custom-words-settings" class="mt-4">
                    <div class="flex items-end justify-between gap-3">
                      <label for="custom-words-input" class="text-sm">Custom words</label>
                      <span id="custom-word-count" class="text-xs text-gray-500">
                        {@custom_word_count} / 3000
                      </span>
                    </div>
                    <.input
                      field={@settings_form[:custom_words]}
                      type="textarea"
                      rows="4"
                      required
                      placeholder={"Add your own words, one per line" <> "\nflamingo\nsandcastle"}
                      class="mt-1 min-h-24 w-full resize-y rounded-base border-2 border-border bg-white px-3 py-2 text-sm leading-5 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                      phx-hook=".CustomWords"
                      id="custom-words-input"
                    />
                    <p
                      :if={@custom_words_error}
                      id="custom-words-error"
                      class="mt-1 text-xs text-red-600"
                    >
                      {@custom_words_error}
                    </p>
                    <p :if={!@custom_words_error} class="mt-1 text-xs text-gray-500">
                      Add at least one word or phrase per line. Commas are not supported.
                    </p>
                  </div>
                </.form>
                <div class="flex w-full shrink-0 flex-col gap-4 border-t-2 border-border p-4">
                  <div>
                    <label class="text-sm">Room name</label>
                    <div class="flex flex-row items-center justify-between">
                      <p class="font-bold">{@room_id}</p>
                      <div class="flex gap-1">
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
        </div>
      </div>
      <.clipboard_handler />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CustomWords">
        export default {
          mounted() {
            this.validate = () => {
              const words = this.el.value.split(/\r?\n/).map(word => word.trim()).filter(Boolean)
              const message = this.el.value.includes(",")
                ? "Enter one word per line without commas."
                : words.length > 3000
                  ? "Custom word lists can contain at most 3000 words."
                  : ""

              this.el.setCustomValidity(message)
            }

            this.validate()
            this.el.addEventListener("input", this.validate)
          },
          updated() {
            this.validate()
          },
          destroyed() {
            this.el.removeEventListener("input", this.validate)
          }
        }
      </script>
    </Layouts.app>
    """
  end

  def handle_event("select_game_mode", %{"mode" => mode}, socket) do
    {game_mode, game_variant} =
      parse_game_mode(mode, socket.assigns.game_mode, socket.assigns.game_variant)

    params = Map.put(socket.assigns.settings_form.params, "game_mode", mode)

    {:noreply,
     assign(socket,
       game_mode: game_mode,
       game_variant: game_variant,
       settings_form: to_form(params, as: :settings)
     )}
  end

  def handle_event("update_settings", %{"settings" => params}, socket) do
    round_count = parse_integer(params["round_count"], socket.assigns.round_count)

    turn_length =
      case Integer.parse(params["turn_length"]) do
        {val, _} -> val |> max(@turn_length_range.first) |> min(@turn_length_range.last)
        :error -> socket.assigns.turn_length
      end

    word_list = Words.parse_word_list(params["word_list"], socket.assigns.word_list)
    custom_words = Map.get(params, "custom_words", socket.assigns.custom_words)

    params =
      params
      |> Map.put("word_list", Atom.to_string(word_list))
      |> Map.put("custom_words", custom_words)

    {game_mode, game_variant} =
      parse_game_mode(params["game_mode"], socket.assigns.game_mode, socket.assigns.game_variant)

    {custom_word_count, custom_words_error} = custom_words_summary(custom_words)

    {:noreply,
     assign(socket,
       round_count: round_count,
       turn_length: turn_length,
       game_mode: game_mode,
       game_variant: game_variant,
       word_list: word_list,
       custom_words: custom_words,
       custom_word_count: custom_word_count,
       custom_words_error: custom_words_error,
       settings_form: to_form(params, as: :settings)
     )}
  end

  def handle_event("start_game", %{"settings" => params}, socket) do
    word_list = Words.parse_word_list(params["word_list"], socket.assigns.word_list)
    custom_words = Map.get(params, "custom_words", socket.assigns.custom_words)

    with {:ok, words} <- words_for_start(word_list, custom_words),
         :ok <- validate_custom_selection(word_list, words) do
      {game_mode, game_variant} =
        parse_game_mode(
          params["game_mode"],
          socket.assigns.game_mode,
          socket.assigns.game_variant
        )

      settings = %{
        round_count: socket.assigns.round_count,
        turn_length: socket.assigns.turn_length,
        custom_words: words,
        include_default_words: false,
        word_list: word_list,
        game_mode: game_mode,
        game_variant: game_variant
      }

      case Rooms.start_game(socket.assigns.room_id, settings) do
        :ok -> {:noreply, socket}
        {:error, reason} -> {:noreply, put_flash(socket, :error, "Cannot start game: #{reason}")}
      end
    else
      {:error, reason} ->
        {custom_word_count, custom_words_error} =
          case reason do
            :empty_custom_words -> {0, "Add at least one custom word."}
            _reason -> custom_words_summary(custom_words)
          end

        {:noreply,
         assign(socket,
           word_list: word_list,
           custom_words: custom_words,
           custom_word_count: custom_word_count,
           custom_words_error: custom_words_error,
           settings_form:
             to_form(
               params
               |> Map.put("word_list", Atom.to_string(word_list))
               |> Map.put("custom_words", custom_words),
               as: :settings
             )
         )}
    end
  end

  defp parse_integer(value, fallback) do
    case Integer.parse(value || "") do
      {parsed, _} -> parsed
      :error -> fallback
    end
  end

  defp parse_game_mode("telephone", _mode, _variant), do: {:telephone, :classic}

  defp parse_game_mode("constraint_roulette", _mode, _variant),
    do: {:scribble, :constraint_roulette}

  defp parse_game_mode("classic", _mode, _variant), do: {:scribble, :classic}
  defp parse_game_mode(_value, mode, variant), do: {mode, variant}
  defp words_for_start(:custom, custom_words), do: Words.parse_custom_words(custom_words)
  defp words_for_start(_word_list, _custom_words), do: {:ok, []}
  defp validate_custom_selection(:custom, []), do: {:error, :empty_custom_words}
  defp validate_custom_selection(_word_list, _words), do: :ok

  defp custom_words_summary(custom_words) do
    case Words.parse_custom_words(custom_words) do
      {:ok, words} ->
        {length(words), nil}

      {:error, :too_many_custom_words} ->
        {custom_word_line_count(custom_words), "Use at most 3000 custom words."}

      {:error, :invalid_custom_words} ->
        {custom_word_line_count(custom_words), "Enter one word per line without commas."}
    end
  end

  defp custom_word_line_count(custom_words) do
    custom_words |> String.split(~r/\R/) |> Enum.count(&(String.trim(&1) != ""))
  end

  def handle_info({:room_snapshot, snapshot}, socket),
    do: {:noreply, apply_snapshot(socket, snapshot)}

  defp apply_snapshot(socket, %{phase: :lobby} = snapshot) do
    initial? = is_nil(socket.assigns.player_id)
    old_count = map_size(socket.assigns.players)

    socket =
      if initial? do
        custom_words = Enum.join(snapshot.custom_words, "\n")

        assign(socket,
          round_count: snapshot.round_count,
          turn_length: snapshot.turn_length,
          game_mode: snapshot.mode,
          game_variant: snapshot.game_variant,
          word_list: snapshot.word_list,
          custom_words: custom_words,
          custom_word_count: length(snapshot.custom_words),
          settings_form:
            to_form(
              %{
                "round_count" => Integer.to_string(snapshot.round_count),
                "turn_length" => Integer.to_string(snapshot.turn_length),
                "game_mode" => selected_game_mode(snapshot.mode, snapshot.game_variant),
                "word_list" => Atom.to_string(snapshot.word_list),
                "custom_words" => custom_words
              },
              as: :settings
            )
        )
      else
        socket
      end

    socket =
      assign(socket,
        player_id: snapshot.viewer_id,
        players: snapshot.players,
        player_order: snapshot.player_order,
        host_id: snapshot.host_id
      )

    socket =
      if initial?,
        do: push_event(socket, "sync_round_audio", %{phase: "lobby", end_time: nil}),
        else: socket

    if initial? or map_size(snapshot.players) > old_count,
      do: push_event(socket, "play_sound", %{sound: "join"}),
      else: socket
  end

  defp apply_snapshot(socket, snapshot) do
    Rooms.prepare_handoff(socket.assigns.room_id)

    push_navigate(socket,
      to: RoomRoute.path(snapshot, socket.assigns.room_id, socket.assigns.resume_token),
      replace: true
    )
  end
end
