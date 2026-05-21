defmodule FlamingoWeb.GameLive do
  use FlamingoWeb, :live_view

  alias Flamingo.{Feed, Games}

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
       final_players: %{},
       final_player_order: [],
       final_drawings: [],
       host_id: nil,
       drawer_id: nil,
       round_count: 3,
       turn_length: 45,
       word_choices: nil,
       turn_end_time: nil,
       word: nil,
       show_word: false,
       current_round: 0,
       correct_guesses: MapSet.new(),
       revealed_indices: [],
       guess_form: to_form(%{"guess" => ""}, as: :guess_form),
       score_gains: %{},
       feed: []
     )}
  end

  def handle_params(%{"player_id" => player_id}, _uri, socket) do
    room_id = socket.assigns.room_id

    if connected?(socket) do
      case Games.get_state(room_id) do
        {:ok, state} ->
          if Map.has_key?(state.players, player_id) do
            Games.subscribe(room_id)

            word_choices =
              if state.phase == :word_choice and player_id == state.drawer_id,
                do: state.word_choices,
                else: nil

            is_drawer = player_id == state.drawer_id
            show_word = is_drawer or state.phase == :turn_reveal or state.phase == :game_ended

            score_gains =
              if state.phase == :turn_reveal, do: state.score_gains, else: %{}

            final_players =
              if state.phase == :game_ended, do: state.players, else: %{}

            final_player_order =
              if state.phase == :game_ended, do: state.player_order, else: []

            final_drawings =
              if state.phase == :game_ended, do: state.final_drawings, else: []

            socket =
              assign(socket,
                player_id: player_id,
                phase: state.phase,
                players: state.players,
                player_order: state.player_order,
                host_id: state.host_id,
                drawer_id: state.drawer_id,
                final_players: final_players,
                final_player_order: final_player_order,
                final_drawings: final_drawings,
                round_count: state.round_count,
                turn_length: state.turn_length,
                current_round: state.current_round,
                word_choices: word_choices,
                turn_end_time: state.turn_end_time,
                word: state.word,
                show_word: show_word,
                correct_guesses: MapSet.new(Map.keys(state.correct_guesses)),
                revealed_indices: state.revealed_indices,
                score_gains: score_gains,
                feed:
                  state.feed.events
                  |> Enum.map(&Feed.format(&1, player_id))
                  |> Enum.reject(&is_nil/1)
              )

            socket =
              if state.phase in [:word_choice, :playing, :turn_reveal] and state.turn_end_time do
                push_event(socket, "set_timer", %{
                  end_time: DateTime.to_iso8601(state.turn_end_time)
                })
              else
                socket
              end

            socket =
              if state.phase == :playing and state.current_drawing != [] do
                push_event(socket, "drawing_state", %{events: state.current_drawing})
              else
                socket
              end

            socket =
              socket
              |> sync_round_audio()
              |> push_event("play_sound", %{sound: "join"})

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

  defp winning_player_id(players, player_order) do
    Enum.max_by(player_order, fn pid -> Map.get(players, pid).score end, fn -> nil end)
  end

  defp drawings_for_player(final_drawings, player_id) do
    final_drawings
    |> Enum.filter(&(&1.drawer_id == player_id))
    |> Enum.sort_by(& &1.turn_order)
  end

  defp sync_round_audio(socket) do
    push_event(socket, "sync_round_audio", %{
      phase: Atom.to_string(socket.assigns.phase),
      end_time:
        if(socket.assigns.turn_end_time,
          do: DateTime.to_iso8601(socket.assigns.turn_end_time),
          else: nil
        )
    })
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} background={if(@phase == :lobby, do: "grid-background", else: "")}>
      <%= if @phase == :lobby do %>
        <div class="flex h-screen w-full items-center justify-center">
          <.card class="flex h-3/5 w-full max-w-2xl flex-row gap-0 bg-white p-0">
            <div class="flex flex-1 flex-col gap-4 border-r-2 border-border p-4">
              <h2 class="text-xl font-bold">Players</h2>
              <ul class="space-y-2">
                <%= for pid <- @player_order do %>
                  <li>{Map.get(@players, pid).name}</li>
                <% end %>
              </ul>
            </div>

            <%= if @player_id == @host_id do %>
              <div class="flex h-full w-full flex-[3] flex-col gap-4 p-4">
                <.form for={%{}} as={:settings} phx-change="update_settings" id="settings-form">
                  <div class="space-y-1">
                    <div class="flex w-full justify-between">
                      <label class="text-sm">Rounds</label>
                      <span class="text-sm">{@round_count}</span>
                    </div>
                    <input
                      type="range"
                      min="1"
                      max="5"
                      value={@round_count}
                      name="settings[round_count]"
                      class="nb-slider w-full"
                      style={"--slider-progress: #{(@round_count - 1) / 4 * 100}%"}
                      phx-hook=".RoundSlider"
                      id="round-count-slider"
                    />
                  </div>

                  <div class="mt-4">
                    <label class="text-sm">Round length(s)</label>
                    <div class="mt-1 flex w-48 items-center">
                      <input
                        type="number"
                        min="30"
                        max="120"
                        value={@turn_length}
                        name="settings[turn_length]"
                        class="w-full rounded-base border-2 border-border bg-white px-3 py-2 text-sm focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                        id="round-length-input"
                      />
                    </div>
                  </div>
                </.form>

                <div class="mt-auto flex w-full flex-col gap-4">
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
                            JS.dispatch("phx:copy", detail: %{text: url(~p"/?room=#{@room_id}")})
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
                    phx-click="start_game"
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
      <% end %>
      <%= if @phase in [:word_choice, :playing, :turn_reveal] do %>
        <.flamingo_background />
        <div class="flex h-screen w-full items-center justify-center p-6">
          <div class="flex h-[675px] w-full max-w-[1200px] flex-col gap-6">
            <.game_header
              word={@word}
              show_word={@show_word or MapSet.member?(@correct_guesses, @player_id)}
              revealed_indices={@revealed_indices}
              turn_end_time={@turn_end_time}
              show_timer={@phase == :playing}
            />

            <div class="flex min-h-0 w-full flex-1 flex-row gap-3 pb-1 pr-1">
              <.player_list_panel
                players={@players}
                player_order={@player_order}
                drawer_id={@drawer_id}
                correct_guesses={@correct_guesses}
              />

              <%= cond do %>
                <% @phase == :word_choice -> %>
                  <.box class="flex w-[704px] shrink-0 items-center justify-center bg-white">
                    <%= if @player_id == @drawer_id do %>
                      <div class="relative flex flex-col items-center gap-8">
                        <.starburst_timer
                          position_class="absolute -top-36 -right-16"
                          timer_id="word-choice-timer"
                          timer_hook="FlamingoWeb.GameLive.Timer"
                          end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
                        />
                        <h2 class="text-3xl font-black">Choose a word</h2>
                        <div class="flex gap-3">
                          <.button
                            :for={word <- @word_choices}
                            phx-click="select_word"
                            phx-value-word={word}
                            class="px-6 py-3 text-base font-bold"
                          >
                            {word}
                          </.button>
                        </div>
                      </div>
                    <% else %>
                      <div class="relative flex flex-col items-center gap-3">
                        <.starburst_timer
                          position_class="absolute -bottom-32 -right-20"
                          size_class="h-28 w-28"
                          text_class="text-2xl"
                          timer_id="word-choice-timer"
                          timer_hook="FlamingoWeb.GameLive.Timer"
                          end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
                        />
                        <p class="text-3xl font-black">
                          <span class="font-hero text-[2.5rem] leading-none text-pink-400">{Map.get(@players, @drawer_id).name}</span>{" "}is picking a word
                        </p>
                      </div>
                    <% end %>
                  </.box>
                <% true -> %>
                  <div class="relative flex w-[704px] shrink-0 flex-col gap-4">
                    <%= if @phase == :turn_reveal do %>
                      <div class="absolute inset-x-0 top-0 z-10 m-[2px] flex h-[500px] items-center justify-center bg-white/75 text-center backdrop-blur-[2px]">
                        <div class="flex w-80 flex-col items-center gap-4">
                          <div>
                            <p class="text-xl font-black">The word was</p>
                            <p class="font-hero text-5xl leading-none font-black text-pink-400">
                              {@word}
                            </p>
                          </div>
                          <ul class="w-64 space-y-1">
                            <%= for {pid, gain} <- Enum.sort_by(@score_gains, fn {_pid, g} -> -g end) do %>
                              <li class="flex items-center justify-between px-3 py-1">
                                <span class="truncate">{Map.get(@players, pid).name}</span>
                                <span class={[
                                  "font-semibold",
                                  if(gain > 0, do: "text-green-700"),
                                  if(gain < 0, do: "text-red-600"),
                                  if(gain == 0, do: "text-gray-700")
                                ]}>
                                  {if(gain > 0, do: "+#{gain}", else: "#{gain}")}
                                </span>
                              </li>
                            <% end %>
                          </ul>
                          <.starburst_timer
                            position_class=""
                            size_class="h-20 w-20"
                            text_class="text-xl"
                            timer_id="turn-reveal-timer"
                            timer_hook="FlamingoWeb.GameLive.Timer"
                            end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
                          />
                        </div>
                      </div>
                    <% end %>

                    <div
                      id="drawing-canvas"
                      phx-hook="DrawingCanvas"
                      phx-update="ignore"
                      data-is-drawer={to_string(@player_id == @drawer_id)}
                      class="flex flex-col gap-2"
                    >
                      <.box class="bg-white p-0">
                        <canvas
                          width="700"
                          height="500"
                          class={[
                            "bg-white",
                            if(@player_id == @drawer_id,
                              do: "cursor-crosshair",
                              else: "cursor-default"
                            )
                          ]}
                        >
                        </canvas>
                      </.box>

                      <%= if @phase == :playing and @player_id == @drawer_id do %>
                        <.box class="bg-white p-0">
                          <.drawing_toolbar palette={palette()} />
                        </.box>
                      <% end %>
                    </div>

                    <%= if @phase == :playing and @player_id != @drawer_id do %>
                      <%= if MapSet.member?(@correct_guesses, @player_id) do %>
                        <.box class="bg-green-100 p-3 text-center font-bold text-green-800">
                          You guessed it!
                        </.box>
                      <% else %>
                        <.form
                          for={@guess_form}
                          phx-submit="guess"
                          phx-hook=".GuessForm"
                          id="guess-form"
                          class="mx-auto flex w-96 items-center gap-2"
                        >
                          <div class="min-w-0 flex-1">
                            <.input
                              field={@guess_form[:guess]}
                              type="text"
                              placeholder="Type your guess..."
                              autocomplete="off"
                              phx-mounted={JS.focus()}
                              class="w-full rounded-base border-2 border-border bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
                              id="guess-input"
                            />
                          </div>
                          <.button type="submit" variant="default" id="guess-button">
                            Guess
                          </.button>
                        </.form>
                      <% end %>
                    <% end %>
                  </div>
              <% end %>

              <.box class="flex min-h-0 w-full flex-1 flex-col bg-white p-0">
                <div
                  id="game-feed"
                  phx-hook=".ScrollFeed"
                  class="flex min-h-0 flex-1 flex-col gap-0 overflow-y-auto"
                >
                  <p
                    :for={{type, text} <- @feed}
                    class={[
                      "p-1 text-xs",
                      type == :system && "font-semibold text-pink-600",
                      type == :correct && "font-semibold text-green-600",
                      type == :close && "font-semibold text-amber-600",
                      type == :guess && "text-foreground",
                      type == :info && "text-gray-500"
                    ]}
                  >
                    {text}
                  </p>
                </div>
              </.box>
            </div>
          </div>
        </div>
      <% end %>
      <%= if @phase == :game_ended do %>
        <.flamingo_background />
        <% winner_id = winning_player_id(@final_players, @final_player_order) %>
        <% winner = winner_id && Map.get(@final_players, winner_id) %>
        <% winner_drawings = drawings_for_player(@final_drawings, winner_id) %>
        <div class="flex h-screen w-full items-center justify-center p-6">
          <div class="grid h-full w-full max-w-[1180px] grid-cols-[320px_minmax(0,1fr)] gap-6 py-8">
            <.card class="flex h-fit w-full flex-col items-center gap-6 bg-white p-8">
              <h2 class="text-3xl font-bold">Game finished</h2>
              <ul class="w-full space-y-1">
                <%= for {pid, idx} <- @final_player_order |> Enum.sort_by(fn pid -> -(Map.get(@final_players, pid).score) end) |> Enum.with_index() do %>
                  <li class="flex items-center gap-2 px-3 py-2">
                    <span class="text-lg">
                      <%= case idx do %>
                        <% 0 -> %>
                          🥇
                        <% 1 -> %>
                          🥈
                        <% 2 -> %>
                          🥉
                        <% _ -> %>
                          {idx + 1}
                      <% end %>
                    </span>
                    <span class="font-bold">{Map.get(@final_players, pid).name}</span>
                    <span class="ml-auto text-pink-500 font-semibold">
                      {Map.get(@final_players, pid).score}
                    </span>
                  </li>
                <% end %>
              </ul>
            </.card>

            <div class="min-h-0 overflow-y-auto">
              <div class="mb-4 flex items-end justify-between">
                <div>
                  <p class="text-sm font-bold uppercase tracking-wide text-pink-500">
                    Winner showcase
                  </p>
                  <h3 class="text-3xl font-black">
                    {if(winner, do: "#{winner.name}'s drawings", else: "Drawings")}
                  </h3>
                </div>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <%= for drawing <- winner_drawings do %>
                  <.box class="bg-white p-3">
                    <div class="mb-2 flex items-center justify-between gap-3">
                      <p class="truncate font-bold">{drawing.word}</p>
                      <span class="shrink-0 text-sm font-semibold text-pink-500">
                        Round {drawing.round_number}
                      </span>
                    </div>
                    <div
                      id={"final-drawing-#{drawing.turn_order}"}
                      phx-hook="DrawingCanvas"
                      phx-update="ignore"
                      data-is-drawer="false"
                      data-final-drawing-events={Jason.encode!(drawing.events)}
                    >
                      <canvas width="700" height="500" class="aspect-[7/5] w-full bg-white"></canvas>
                    </div>
                  </.box>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <div id="clipboard-handler" phx-hook=".Clipboard" phx-update="ignore"></div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Clipboard">
        export default {
          mounted() {
            window.addEventListener("phx:copy", (event) => {
              if (event.detail && event.detail.text) {
                navigator.clipboard.writeText(event.detail.text)
              }
            })
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Timer">
        export default {
          mounted() {
            const startTimer = (endTime) => {
              const endMs = new Date(endTime).getTime()
              const update = () => {
                const remaining = Math.max(0, Math.ceil((endMs - Date.now()) / 1000))
                this.el.innerText = String(remaining).padStart(2, '0')
                if (remaining > 0) requestAnimationFrame(update)
              }
              update()
            }
            const initial = this.el.dataset.endTime
            if (initial) startTimer(initial)
            this.handleEvent("set_timer", ({end_time}) => startTimer(end_time))
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".GuessForm">
        export default {
          mounted() {
            this.handleEvent("clear_guess", () => {
              this.el.reset()
            })
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".RoundSlider">
        export default {
          mounted() {
            const update = () => {
              const min = parseInt(this.el.min)
              const max = parseInt(this.el.max)
              const val = parseInt(this.el.value)
              const progress = ((val - min) / (max - min)) * 100
              this.el.style.setProperty("--slider-progress", progress + "%")
            }
            update()
            this.el.addEventListener("input", () => update())
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollFeed">
        export default {
          mounted() {
            this.el.scrollTop = this.el.scrollHeight
            this.handleEvent("scroll_feed", () => {
              this.el.scrollTop = this.el.scrollHeight
            })
          },
          updated() {
            this.el.scrollTop = this.el.scrollHeight
          }
        }
      </script>
    </Layouts.app>
    """
  end

  def handle_event("update_settings", %{"settings" => params}, socket) do
    round_count = String.to_integer(params["round_count"])

    turn_length =
      case Integer.parse(params["turn_length"]) do
        {val, _} -> max(val, 30)
        :error -> socket.assigns.turn_length
      end

    {:noreply, assign(socket, round_count: round_count, turn_length: turn_length)}
  end

  def handle_event("start_game", _params, socket) do
    settings = %{
      round_count: socket.assigns.round_count,
      turn_length: socket.assigns.turn_length
    }

    case Games.start_game(socket.assigns.room_id, socket.assigns.player_id, settings) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot start game: #{reason}")}
    end
  end

  def handle_event("select_word", %{"word" => word}, socket) do
    Games.select_word(socket.assigns.room_id, socket.assigns.player_id, word)
    {:noreply, socket}
  end

  def handle_event("draw_event", event, socket) do
    Games.draw_event(socket.assigns.room_id, socket.assigns.player_id, event)
    {:noreply, socket}
  end

  def handle_event("guess", %{"guess_form" => %{"guess" => text}}, socket) do
    Games.guess(socket.assigns.room_id, socket.assigns.player_id, text)
    {:noreply, socket}
  end

  def handle_info({:players_updated, players, player_order, host_id}, socket) do
    old_count = map_size(socket.assigns.players)
    new_count = map_size(players)

    socket = assign(socket, players: players, player_order: player_order, host_id: host_id)

    socket =
      if socket.assigns.phase != :game_ended and new_count > old_count do
        push_event(socket, "play_sound", %{sound: "join"})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(
        {:word_choice_started, drawer_id, word_choices, turn_end_time, round_count, turn_length,
         current_round},
        socket
      ) do
    is_drawer = socket.assigns.player_id == drawer_id

    socket =
      assign(socket,
        phase: :word_choice,
        drawer_id: drawer_id,
        turn_end_time: turn_end_time,
        round_count: round_count,
        turn_length: turn_length,
        current_round: current_round,
        final_players: %{},
        final_player_order: [],
        final_drawings: [],
        word_choices: if(is_drawer, do: word_choices, else: nil),
        word: nil,
        show_word: false,
        correct_guesses: MapSet.new(),
        score_gains: %{}
      )

    socket =
      socket
      |> push_event("set_timer", %{end_time: DateTime.to_iso8601(turn_end_time)})
      |> sync_round_audio()

    {:noreply, socket}
  end

  def handle_info({:turn_started, drawer_id, word, turn_end_time}, socket) do
    is_drawer = socket.assigns.player_id == drawer_id

    socket =
      assign(socket,
        phase: :playing,
        drawer_id: drawer_id,
        final_players: %{},
        final_player_order: [],
        final_drawings: [],
        word_choices: nil,
        turn_end_time: turn_end_time,
        word: word,
        show_word: is_drawer,
        correct_guesses: MapSet.new(),
        revealed_indices: []
      )

    socket =
      socket
      |> push_event("set_timer", %{end_time: DateTime.to_iso8601(turn_end_time)})
      |> sync_round_audio()

    {:noreply, socket}
  end

  def handle_info({:turn_reveal, word, turn_end_time, score_gains, players}, socket) do
    socket =
      assign(socket,
        phase: :turn_reveal,
        final_players: %{},
        final_player_order: [],
        word: word,
        show_word: true,
        turn_end_time: turn_end_time,
        score_gains: score_gains,
        players: players
      )

    socket =
      socket
      |> push_event("set_timer", %{end_time: DateTime.to_iso8601(turn_end_time)})
      |> sync_round_audio()

    {:noreply, socket}
  end

  def handle_info({:game_ended, players, final_drawings}, socket) do
    {:noreply,
     assign(socket,
       phase: :game_ended,
       final_players: players,
       final_player_order: socket.assigns.player_order,
       final_drawings: final_drawings,
       turn_end_time: nil
     )
     |> sync_round_audio()}
  end

  def handle_info({:hint_revealed, revealed_indices}, socket) do
    if socket.assigns.show_word or
         MapSet.member?(socket.assigns.correct_guesses, socket.assigns.player_id) do
      {:noreply, socket}
    else
      {:noreply, assign(socket, revealed_indices: revealed_indices)}
    end
  end

  def handle_info({:correct_guess, player_id}, socket) do
    sound =
      if player_id == socket.assigns.player_id,
        do: "correctGuess",
        else: "otherPlayerCorrect"

    {:noreply,
     socket
     |> assign(:correct_guesses, MapSet.put(socket.assigns.correct_guesses, player_id))
     |> push_event("play_sound", %{sound: sound})}
  end

  def handle_info({:incorrect_guess, player_id, _text}, socket) do
    if player_id == socket.assigns.player_id do
      {:noreply,
       socket
       |> assign(:guess_form, to_form(%{"guess" => ""}, as: :guess_form))
       |> push_event("play_sound", %{sound: "wrongGuess"})
       |> push_event("clear_guess", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:feed_event, event}, socket) do
    formatted = Feed.format(event, socket.assigns.player_id)

    if formatted do
      {:noreply,
       socket
       |> assign(:feed, socket.assigns.feed ++ [formatted])
       |> push_event("scroll_feed", %{})}
    else
      {:noreply, socket}
    end
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
