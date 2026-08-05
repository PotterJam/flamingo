defmodule FlamingoWeb.ScribbleLive do
  use FlamingoWeb, :live_view

  alias Flamingo.{DrawingShare, Rooms, Words}

  @min_turn_length 15
  @max_turn_length 120

  @palette ~w(
    #000000 #FFFFFF #C1C1C1 #505050 #EF120B #740A08
    #FF7700 #C23900 #FFE404 #E8A202 #08C202 #00461A
    #00FF91 #04785E #00B2FF #02569E #2220D3 #0E0865
    #A302BA #550069 #DF69A7 #883454 #FFAC8A #CC7C4D
    #A0522D #63300D
  )

  def mount(%{"room_id" => room_id} = _params, _session, socket) do
    {:ok,
     socket
     |> assign(
       room_id: room_id,
       player_id: nil,
       participation: :active,
       phase: :lobby,
       players: %{},
       player_order: [],
       final_players: %{},
       final_player_order: [],
       final_drawings: [],
       selected_player_id: nil,
       host_id: nil,
       drawer_id: nil,
       round_count: 3,
       turn_length: 45,
       custom_words: "",
       custom_word_count: 0,
       custom_words_error: nil,
       settings_form:
         to_form(
           %{
             "round_count" => "3",
             "turn_length" => "45",
             "custom_words" => "",
             "include_default_words" => false
           },
           as: :settings
         ),
       word_choices: nil,
       turn_end_time: nil,
       word: nil,
       show_word: false,
       current_round: 0,
       correct_guesses: MapSet.new(),
       revealed_indices: [],
       feed_ids: MapSet.new(),
       guess_form: to_form(%{"guess" => ""}, as: :guess_form),
       score_gains: %{}
     )
     |> stream_configure(:feed, dom_id: &"feed-#{&1.id}")
     |> stream(:feed, [])}
  end

  def handle_params(%{"resume_token" => resume_token}, _uri, socket) do
    room_id = socket.assigns.room_id

    if connected?(socket) do
      case Rooms.connect(room_id, resume_token) do
        {:ok, snapshot} ->
          socket =
            socket
            |> apply_snapshot(snapshot)

          {:noreply, push_event(socket, "play_sound", %{sound: "join"})}

        {:error, :not_found} ->
          {:noreply, push_navigate(socket, to: ~p"/")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  defp palette, do: @palette

  defp winning_player_id(players, player_order) do
    Enum.max_by(player_order, fn pid -> Map.get(players, pid).score end, fn -> nil end)
  end

  defp selected_or_winning_player_id(players, player_order, selected_player_id) do
    if selected_player_id && Map.has_key?(players, selected_player_id) do
      selected_player_id
    else
      winning_player_id(players, player_order)
    end
  end

  defp drawings_for_player(final_drawings, player_id) do
    final_drawings
    |> Enum.filter(&(&1.drawer_id == player_id))
    |> Enum.sort_by(& &1.round_number)
  end

  defp drawing_share_url(drawing, players) do
    player = Map.fetch!(players, drawing.drawer_id)

    encoded =
      drawing
      |> Map.put(:drawer_name, player.name)
      |> DrawingShare.encode()

    url(~p"/drawing") <> "##{encoded}"
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
    assigns =
      assign(assigns,
        min_turn_length: @min_turn_length,
        max_turn_length: @max_turn_length
      )

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
              <div class="flex h-full min-h-0 w-full flex-[3] flex-col overflow-hidden">
                <.form
                  for={@settings_form}
                  phx-change="update_settings"
                  phx-submit="start_game"
                  class="min-h-0 flex-1 overflow-y-auto p-4"
                  id="settings-form"
                >
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
                      name={@settings_form[:round_count].name}
                      class="nb-slider w-full"
                      style={"--slider-progress: #{(@round_count - 1) / 4 * 100}%"}
                      phx-hook=".RoundSlider"
                      id="round-count-slider"
                    />
                  </div>

                  <div class="mt-4">
                    <label class="text-sm">Round length(s)</label>
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

                  <div class="mt-4">
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
                      Leave empty to use the standard word list. Commas are not supported.
                    </p>
                    <div class="mt-3">
                      <.input
                        field={@settings_form[:include_default_words]}
                        type="checkbox"
                        label="Include standard words"
                        id="include-default-words-input"
                      />
                    </div>
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
      <% end %>
      <%= if @phase in [:word_choice, :playing, :turn_reveal] do %>
        <.flamingo_background />
        <div class="flex h-screen w-full items-center justify-center p-6">
          <div class="flex h-[675px] w-full max-w-[1200px] flex-col gap-6">
            <div
              :if={@participation == :spectator}
              id="spectator-notice"
              class="mx-auto -mb-3 flex items-center gap-2 rounded-full border-2 border-pink-300 bg-white px-4 py-2 text-sm font-bold text-pink-700 shadow-sm"
            >
              <.icon name={:eye} class="h-4 w-4" /> Spectating this turn
            </div>
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
                    <%= if @player_id == @drawer_id and @participation == :active do %>
                      <div class="relative flex flex-col items-center gap-8">
                        <.starburst_timer
                          position_class="absolute -top-36 -right-16"
                          timer_id="word-choice-timer"
                          timer_hook="FlamingoWeb.ScribbleLive.Timer"
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
                          timer_hook="FlamingoWeb.ScribbleLive.Timer"
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
                            timer_hook="FlamingoWeb.ScribbleLive.Timer"
                            end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
                          />
                        </div>
                      </div>
                    <% end %>

                    <div
                      id="drawing-canvas"
                      phx-hook="DrawingCanvas"
                      phx-update="ignore"
                      data-is-drawer={
                        to_string(@player_id == @drawer_id and @participation == :active)
                      }
                      class="flex flex-col gap-2"
                    >
                      <.box class="bg-white p-0">
                        <canvas
                          width="700"
                          height="500"
                          class={[
                            "bg-white",
                            if(@player_id == @drawer_id and @participation == :active,
                              do: "cursor-crosshair",
                              else: "cursor-default"
                            )
                          ]}
                        >
                        </canvas>
                      </.box>

                      <%= if @phase == :playing and @player_id == @drawer_id and @participation == :active do %>
                        <.box class="bg-white p-0">
                          <.drawing_toolbar palette={palette()} />
                        </.box>
                      <% end %>
                    </div>

                    <%= if @phase == :playing and @player_id != @drawer_id and @participation == :active do %>
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
                          <span
                            id="guess-letter-count"
                            class="mr-2 w-12 shrink-0 text-right font-hero text-lg leading-none font-medium text-black"
                          >
                          </span>
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
                  phx-update="stream"
                  class="flex min-h-0 flex-1 flex-col gap-0 overflow-y-auto"
                >
                  <p
                    :for={{dom_id, entry} <- @streams.feed}
                    id={dom_id}
                    class={[
                      "p-1 text-xs",
                      entry.kind == :system && "font-semibold text-pink-600",
                      entry.kind == :correct && "font-semibold text-green-600",
                      entry.kind == :close && "font-semibold text-amber-600",
                      entry.kind == :guess && "text-foreground",
                      entry.kind == :info && "text-gray-500"
                    ]}
                  >
                    {entry.text}
                  </p>
                </div>
              </.box>
            </div>
          </div>
        </div>
      <% end %>
      <%= if @phase == :game_ended do %>
        <.flamingo_background />
        <% selected_player_id =
          selected_or_winning_player_id(
            @final_players,
            @final_player_order,
            @selected_player_id
          ) %>
        <% selected_drawings = drawings_for_player(@final_drawings, selected_player_id) %>
        <div class="flex h-screen w-full items-center justify-center">
          <div class="grid h-full w-fit grid-cols-[320px_320px] items-center justify-center gap-28">
            <.card class="flex h-fit w-full flex-col items-center gap-6 bg-white p-8">
              <h2 class="text-3xl font-bold">Game finished</h2>
              <ul
                id="final-score-rows"
                class="w-full space-y-1"
                phx-hook="FinalDrawingShowcase"
                data-selected-player-id={selected_player_id}
              >
                <%= for {pid, idx} <- @final_player_order |> Enum.sort_by(fn pid -> -(Map.get(@final_players, pid).score) end) |> Enum.with_index() do %>
                  <li class={[
                    "flex items-center transition-colors",
                    pid == selected_player_id && "bg-pink-100",
                    pid != selected_player_id && "hover:bg-pink-50"
                  ]}>
                    <button
                      type="button"
                      class={[
                        "flex min-w-0 flex-1 items-center gap-2 px-3 py-2 text-left"
                      ]}
                      phx-click="select_player"
                      phx-value-player-id={pid}
                      data-player-id={pid}
                      data-selected={if(pid == selected_player_id, do: "true", else: "false")}
                    >
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
                    </button>
                    <button
                      :if={pid == selected_player_id}
                      type="button"
                      class="mr-2 flex h-8 w-8 shrink-0 items-center justify-center text-pink-600 transition-colors hover:bg-pink-200"
                      data-replay-final-drawings
                      aria-label="Replay selected drawings"
                    >
                      <.icon name={:refresh_cw} class="h-4 w-4" />
                    </button>
                    <span :if={pid != selected_player_id} class="mr-2 h-8 w-8 shrink-0"></span>
                  </li>
                <% end %>
              </ul>
            </.card>

            <div class="flex h-full min-h-0 flex-col">
              <div class="no-scrollbar flex min-h-0 flex-1 flex-col overflow-y-auto pr-2 [justify-content:safe_center]">
                <div class="flex w-full flex-col gap-4 py-4">
                  <%= if selected_drawings == [] do %>
                    <div class="border-2 border-border bg-white p-6 text-center font-bold">
                      No drawings to show
                    </div>
                  <% end %>
                  <%= for drawing <- selected_drawings do %>
                    <% share_url = drawing_share_url(drawing, @final_players) %>
                    <div class="border-2 border-border bg-white p-3">
                      <div class="mb-2 flex items-center justify-between gap-3">
                        <span
                          class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-pink-400 text-xs font-black text-white"
                          aria-label={"Round #{drawing.round_number}"}
                        >
                          {drawing.round_number}
                        </span>
                        <p class="truncate text-right font-bold">{drawing.word}</p>
                        <.button
                          variant="neutral"
                          size="sm"
                          class="shrink-0 px-2"
                          on_confirm_click={JS.dispatch("phx:copy", detail: %{text: share_url})}
                          id={"copy-final-drawing-#{drawing.drawer_id}-round-#{drawing.round_number}"}
                          data-drawing-share-url={share_url}
                        >
                          <span class="flex items-center gap-1">
                            <.icon name={:copy} class="h-4 w-4" /> Copy link
                          </span>
                        </.button>
                      </div>
                      <div
                        id={"final-drawing-#{drawing.drawer_id}-round-#{drawing.round_number}"}
                        phx-hook="DrawingCanvas"
                        phx-update="ignore"
                        data-is-drawer="false"
                        data-final-drawing-replay="true"
                        data-final-drawing-events={Jason.encode!(drawing.ops)}
                      >
                        <canvas width="700" height="500" class="aspect-[7/5] w-full bg-white">
                        </canvas>
                      </div>
                    </div>
                  <% end %>
                </div>
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
            const input = this.el.querySelector("#guess-input")
            const count = this.el.querySelector("#guess-letter-count")
            const formatCount = (text) => {
              if (!text.trim()) return ""

              return text
                .trim()
                .split(" ")
                .map((word) => Array.from(word).length)
                .join(" ")
            }
            const update = () => {
              count.textContent = formatCount(input.value)
            }

            update()
            input.focus()
            input.addEventListener("input", update)
            this.el.addEventListener("submit", () => {
              // Let LiveView serialize the submitted value before clearing the visible input.
              setTimeout(() => {
                this.el.reset()
                update()
                input.focus()
              }, 0)
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
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollFeed">
        export default {
          mounted() {
            // Follow new messages only while the user is at (or near) the
            // bottom; never yank the feed around while they're reading back.
            this.pinned = true
            this.el.addEventListener("scroll", () => {
              const distanceFromBottom =
                this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
              this.pinned = distanceFromBottom < 32
            })
            this.scrollToBottom()
            this.handleEvent("scroll_feed", () => this.pinned && this.scrollToBottom())
          },
          updated() {
            if (this.pinned) this.scrollToBottom()
          },
          scrollToBottom() {
            // Wait a frame so layout has settled; scrolling while the panel is
            // mid-patch (height not yet computed) silently clamps to the top.
            requestAnimationFrame(() => {
              this.el.scrollTop = this.el.scrollHeight
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  def handle_event("update_settings", %{"settings" => params}, socket) do
    round_count = parse_integer(params["round_count"], socket.assigns.round_count)

    turn_length =
      case Integer.parse(params["turn_length"]) do
        {val, _} -> val |> max(@min_turn_length) |> min(@max_turn_length)
        :error -> socket.assigns.turn_length
      end

    custom_words = Map.get(params, "custom_words", "")
    {custom_word_count, custom_words_error} = custom_words_summary(custom_words)

    {:noreply,
     assign(socket,
       round_count: round_count,
       turn_length: turn_length,
       custom_words: custom_words,
       custom_word_count: custom_word_count,
       custom_words_error: custom_words_error,
       settings_form: to_form(params, as: :settings)
     )}
  end

  def handle_event("start_game", %{"settings" => params}, socket) do
    custom_words = Map.get(params, "custom_words", "")

    case Words.parse_custom_words(custom_words) do
      {:ok, words} ->
        settings = %{
          round_count: socket.assigns.round_count,
          turn_length: socket.assigns.turn_length,
          custom_words: words,
          include_default_words: params["include_default_words"] == "true"
        }

        case Rooms.start_game(socket.assigns.room_id, settings) do
          :ok ->
            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Cannot start game: #{reason}")}
        end

      {:error, _reason} ->
        {custom_word_count, custom_words_error} = custom_words_summary(custom_words)

        {:noreply,
         assign(socket,
           custom_words: custom_words,
           custom_word_count: custom_word_count,
           custom_words_error: custom_words_error,
           settings_form: to_form(params, as: :settings)
         )}
    end
  end

  def handle_event("select_word", %{"word" => word}, socket) do
    Rooms.select_word(socket.assigns.room_id, word)
    {:noreply, socket}
  end

  def handle_event("draw_event", event, socket) do
    Rooms.draw_event(socket.assigns.room_id, event)
    {:noreply, socket}
  end

  def handle_event("guess", %{"guess_form" => %{"guess" => text}}, socket) do
    socket =
      case Rooms.guess(socket.assigns.room_id, text) do
        :incorrect -> push_event(socket, "play_sound", %{sound: "wrongGuess"})
        _result -> socket
      end

    {:noreply, socket}
  end

  def handle_event("select_player", %{"player-id" => player_id}, socket) do
    {:noreply, assign(socket, selected_player_id: player_id)}
  end

  defp parse_integer(value, fallback) do
    case Integer.parse(value || "") do
      {parsed, _} -> parsed
      :error -> fallback
    end
  end

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
    custom_words
    |> String.split(~r/\R/)
    |> Enum.count(&(String.trim(&1) != ""))
  end

  def handle_info({:room_snapshot, snapshot}, socket) do
    {:noreply, apply_snapshot(socket, snapshot)}
  end

  def handle_info({:draw_event, event}, socket) do
    {:noreply, push_event(socket, "draw_event", event)}
  end

  defp apply_snapshot(socket, snapshot) do
    initial? = is_nil(socket.assigns.player_id)
    old_phase = socket.assigns.phase
    old_turn_end_time = socket.assigns.turn_end_time
    old_count = map_size(socket.assigns.players)
    old_feed_ids = socket.assigns.feed_ids
    feed_ids = MapSet.new(snapshot.feed, & &1.id)
    feed_changed? = feed_ids != old_feed_ids
    newly_correct = MapSet.difference(snapshot.correct_guesses, socket.assigns.correct_guesses)
    game_ended? = snapshot.phase == :game_ended
    custom_words = Enum.join(snapshot.custom_words, "\n")
    sync_settings? = initial? or old_phase != :lobby or snapshot.phase != :lobby

    round_count = if sync_settings?, do: snapshot.round_count, else: socket.assigns.round_count
    turn_length = if sync_settings?, do: snapshot.turn_length, else: socket.assigns.turn_length
    custom_words = if sync_settings?, do: custom_words, else: socket.assigns.custom_words

    custom_word_count =
      if sync_settings?, do: length(snapshot.custom_words), else: socket.assigns.custom_word_count

    custom_words_error =
      if sync_settings?, do: nil, else: socket.assigns.custom_words_error

    settings_form =
      if sync_settings? do
        to_form(
          %{
            "round_count" => Integer.to_string(snapshot.round_count),
            "turn_length" => Integer.to_string(snapshot.turn_length),
            "custom_words" => custom_words,
            "include_default_words" => snapshot.include_default_words
          },
          as: :settings
        )
      else
        socket.assigns.settings_form
      end

    final_players = if game_ended?, do: snapshot.final_players, else: %{}
    final_player_order = if game_ended?, do: snapshot.final_player_order, else: []
    final_drawings = if game_ended?, do: snapshot.final_drawings, else: []

    socket =
      socket
      |> assign(
        player_id: snapshot.viewer_id,
        participation: snapshot.participation,
        phase: snapshot.phase,
        players: snapshot.players,
        player_order: snapshot.player_order,
        host_id: snapshot.host_id,
        drawer_id: snapshot.drawer_id,
        final_players: final_players,
        final_player_order: final_player_order,
        final_drawings: final_drawings,
        selected_player_id:
          if(game_ended?,
            do:
              selected_or_winning_player_id(
                final_players,
                final_player_order,
                socket.assigns.selected_player_id
              ),
            else: nil
          ),
        round_count: round_count,
        turn_length: turn_length,
        custom_words: custom_words,
        custom_word_count: custom_word_count,
        custom_words_error: custom_words_error,
        settings_form: settings_form,
        current_round: snapshot.current_round,
        word_choices: snapshot.word_choices,
        turn_end_time: snapshot.turn_end_time,
        word: snapshot.word,
        show_word: snapshot.word_visible?,
        correct_guesses: snapshot.correct_guesses,
        revealed_indices: snapshot.revealed_indices,
        feed_ids: feed_ids,
        score_gains: snapshot.score_gains
      )

    socket =
      if feed_changed? do
        socket
        |> stream(:feed, snapshot.feed, reset: true)
        |> push_event("scroll_feed", %{})
      else
        socket
      end

    socket =
      if snapshot.turn_end_time && snapshot.phase in [:word_choice, :playing, :turn_reveal] &&
           (initial? || old_phase != snapshot.phase || old_turn_end_time != snapshot.turn_end_time) do
        push_event(socket, "set_timer", %{end_time: DateTime.to_iso8601(snapshot.turn_end_time)})
      else
        socket
      end

    drawing_visible? = snapshot.phase in [:playing, :turn_reveal]
    drawing_was_visible? = old_phase in [:playing, :turn_reveal]

    socket =
      if drawing_visible? && (initial? || not drawing_was_visible?) do
        push_event(socket, "drawing_state", %{events: snapshot.current_drawing})
      else
        socket
      end

    socket =
      if initial? or old_phase != snapshot.phase, do: sync_round_audio(socket), else: socket

    socket =
      if not initial? and snapshot.phase != :game_ended and map_size(snapshot.players) > old_count,
        do: push_event(socket, "play_sound", %{sound: "join"}),
        else: socket

    case if(initial?, do: [], else: MapSet.to_list(newly_correct)) do
      [player_id | _] ->
        sound = if player_id == snapshot.viewer_id, do: "correctGuess", else: "otherPlayerCorrect"
        push_event(socket, "play_sound", %{sound: sound})

      [] ->
        socket
    end
  end
end
