defmodule FlamingoWeb.ScribbleLive do
  use FlamingoWeb, :live_view

  alias Flamingo.{DrawingShare, Rooms}
  alias FlamingoWeb.RoomRoute

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
       resume_token: nil,
       player_id: nil,
       participation: :active,
       phase: nil,
       players: %{},
       player_order: [],
       final_players: %{},
       final_player_order: [],
       final_drawings: [],
       selected_player_id: nil,
       host_id: nil,
       drawer_id: nil,
       constraint: nil,
       round_count: 3,
       game_variant: :classic,
       word_choices: nil,
       turn_end_time: nil,
       word: nil,
       show_word: false,
       current_round: 0,
       correct_guesses: MapSet.new(),
       drawing_vote: nil,
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
            |> assign(:resume_token, resume_token)
            |> route_snapshot(snapshot)

          {:noreply, push_event(socket, "play_sound", %{sound: "join"})}

        {:error, _reason} ->
          {:noreply, push_navigate(socket, to: ~p"/")}
      end
    else
      {:noreply, assign(socket, :resume_token, resume_token)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  defp palette, do: @palette

  defp constraint_label(:hidden_canvas), do: "Draw blind — your canvas is hidden"
  defp constraint_label(:single_stroke), do: "One stroke — don't lift your pen"
  defp constraint_label(:straight_lines), do: "Straight lines only"
  defp constraint_label(:rotating_canvas), do: "Moving target — the canvas is rotating"
  defp constraint_label(:mirror), do: "Mirror mode — horizontal movement is reversed"
  defp constraint_label(_constraint), do: nil

  defp constraint_mode(:hidden_canvas), do: "draw blind"
  defp constraint_mode(:single_stroke), do: "one stroke"
  defp constraint_mode(:straight_lines), do: "straight lines only"
  defp constraint_mode(:rotating_canvas), do: "moving target"
  defp constraint_mode(:mirror), do: "mirror mode"
  defp constraint_mode(_constraint), do: nil

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
    ~H"""
    <Layouts.app flash={@flash} background="">
      <%= if @phase in [:word_choice, :playing, :turn_reveal] do %>
        <.flamingo_background game_mode={@game_variant} />
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
                current_round={@current_round + 1}
                round_count={@round_count}
              />

              <%= cond do %>
                <% @phase == :word_choice -> %>
                  <.box class="flex w-[704px] shrink-0 items-center justify-center bg-white">
                    <%= if @player_id == @drawer_id and @participation == :active do %>
                      <div class="relative flex flex-col items-center gap-8">
                        <.starburst_timer
                          position_class="absolute -top-36 -right-16"
                          timer_id="word-choice-timer"
                          end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
                        />
                        <h2 class="text-3xl font-black">Choose a word</h2>
                        <.word_choice_buttons
                          choices={@word_choices}
                          id="scribble-word-choices"
                          id_prefix="scribble-word-choice"
                          event="select_word"
                        />
                      </div>
                    <% else %>
                      <div class="relative flex flex-col items-center gap-3">
                        <.starburst_timer
                          position_class="absolute -bottom-32 -right-20"
                          size_class="h-28 w-28"
                          text_class="text-2xl"
                          timer_id="word-choice-timer"
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
                    <div
                      :if={@constraint}
                      id="constraint-banner"
                      class="absolute inset-x-8 -top-5 z-20 flex items-center justify-center"
                    >
                      <span class="border-2 border-border bg-yellow-200 px-4 py-1 font-hero text-lg font-black shadow-shadow">
                        {constraint_label(@constraint)}
                      </span>
                    </div>
                    <%= if @phase == :turn_reveal do %>
                      <div
                        id="turn-reveal-overlay"
                        class={[
                          "absolute inset-x-0 top-0 z-10 m-[2px] flex h-[500px] items-center justify-center text-center",
                          if(
                            @constraint == :hidden_canvas and @player_id == @drawer_id and
                              @participation == :active,
                            do: "bg-white/20",
                            else: "bg-white/75 backdrop-blur-[2px]"
                          )
                        ]}
                      >
                        <div class="flex w-full flex-col items-center gap-4 px-6">
                          <div>
                            <p class="text-xl font-black">The word was</p>
                            <p class="font-hero text-5xl leading-none font-black text-pink-400">
                              {@word}
                            </p>
                          </div>
                          <ul
                            id="turn-reveal-score-gains"
                            class="grid w-fit grid-flow-col grid-rows-5 auto-cols-[18rem] gap-x-4 gap-y-1"
                          >
                            <%= for {pid, gain} <- Enum.sort_by(@score_gains, fn {_pid, g} -> -g end) do %>
                              <li
                                id={"score-gain-row-#{pid}"}
                                class="flex min-w-0 items-center gap-2 px-3 py-1"
                              >
                                <.flamingo_avatar
                                  avatar={Map.get(Map.get(@players, pid), :avatar, %{})}
                                  class="h-8 w-8 shrink-0"
                                  label={"#{Map.get(@players, pid).name}'s avatar"}
                                />
                                <span class="min-w-0 flex-1 truncate">
                                  {Map.get(@players, pid).name}
                                </span>
                                <span class={[
                                  "shrink-0",
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
                            end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
                          />
                        </div>
                      </div>
                    <% end %>

                    <.drawing_canvas
                      id="drawing-canvas"
                      is_drawer={@player_id == @drawer_id and @participation == :active}
                      constraint={@constraint}
                      phase={@phase}
                      show_toolbar={
                        @phase == :playing and @player_id == @drawer_id and
                          @participation == :active
                      }
                      palette={palette()}
                    />

                    <%= if @phase == :playing and @player_id != @drawer_id and @participation == :active do %>
                      <div id="guess-row" class="relative z-10 flex w-full items-center gap-2">
                        <div id="drawing-votes" class="flex shrink-0">
                          <.button
                            :for={{vote, icon} <- [{:down, :thumbs_down}, {:up, :thumbs_up}]}
                            id={"vote-drawing-#{vote}"}
                            type="button"
                            variant="ghost"
                            size="sm"
                            class="drawing-vote flex h-10 w-10 items-center justify-center"
                            data-vote={vote}
                            phx-click={
                              JS.set_attribute({"aria-pressed", "false"}, to: "#drawing-votes button")
                              |> JS.set_attribute({"aria-pressed", "true"})
                              |> JS.push("vote_drawing")
                              |> JS.transition("drawing-vote-pop",
                                to: "#vote-drawing-#{vote} svg",
                                time: 280,
                                blocking: false
                              )
                            }
                            phx-value-vote={vote}
                            aria-label={"Thumbs #{vote}"}
                            aria-pressed={to_string(@drawing_vote == vote)}
                          >
                            <.icon name={icon} class="h-5 w-5" />
                          </.button>
                        </div>
                        <%= if MapSet.member?(@correct_guesses, @player_id) do %>
                          <.box class="min-w-0 flex-1 bg-green-100 p-3 text-center font-bold text-green-800">
                            You guessed it!
                          </.box>
                        <% else %>
                          <.word_submission_form
                            form={@guess_form}
                            field={@guess_form[:guess]}
                            id="guess-form"
                            input_id="guess-input"
                            button_id="guess-button"
                            submit="guess"
                            placeholder="Type your guess..."
                            button_label="Guess"
                            class="min-w-0 flex-1"
                            hook="FlamingoWeb.ScribbleLive.GuessForm"
                            mounted={JS.focus()}
                          >
                            <:prefix>
                              <span
                                id="guess-letter-count"
                                class="absolute left-0 top-full mt-1 font-hero text-sm leading-none font-medium text-black"
                              >
                              </span>
                            </:prefix>
                          </.word_submission_form>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
              <% end %>

              <.box class="relative z-10 flex min-h-0 w-full flex-1 flex-col bg-white p-0">
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
                      entry.kind == :like && "font-semibold text-emerald-600",
                      entry.kind == :dislike && "font-semibold text-red-600",
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
        <.flamingo_background game_mode={@game_variant} />
        <% selected_player_id =
          selected_or_winning_player_id(
            @final_players,
            @final_player_order,
            @selected_player_id
          ) %>
        <% selected_drawings = drawings_for_player(@final_drawings, selected_player_id) %>
        <div class="flex h-screen w-full items-center justify-center">
          <div class="grid h-full w-fit grid-cols-[500px_320px] items-center justify-center gap-28">
            <div class="relative">
              <.button
                :if={@player_id == @host_id}
                id="return-to-lobby"
                phx-click="return_to_lobby"
                class="absolute bottom-full left-0 mb-6"
              >
                Return to lobby
              </.button>
              <.card class="flex h-fit w-full flex-col items-center gap-6 bg-white p-8">
                <h2 class="text-3xl font-bold">Game finished</h2>
                <ul
                  id="final-score-rows"
                  class="w-full space-y-1"
                  phx-hook="FinalDrawingShowcase"
                  data-selected-player-id={selected_player_id}
                >
                  <%= for {pid, idx} <- @final_player_order |> Enum.sort_by(fn pid -> -(Map.get(@final_players, pid).score) end) |> Enum.with_index() do %>
                    <li
                      id={"final-score-row-#{pid}"}
                      class={[
                        "flex min-w-0 items-center transition-colors",
                        pid == selected_player_id && "bg-pink-100",
                        pid != selected_player_id && "hover:bg-pink-50"
                      ]}
                    >
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
                        <.flamingo_avatar
                          avatar={Map.get(Map.get(@final_players, pid), :avatar, %{})}
                          class="h-10 w-10 shrink-0"
                          label={"#{Map.get(@final_players, pid).name}'s avatar"}
                        />
                        <span class="min-w-0 flex-1 truncate font-bold">
                          {Map.get(@final_players, pid).name}
                        </span>
                        <span
                          :if={
                            @final_players[pid].thumbs_up > 0 or @final_players[pid].thumbs_down > 0
                          }
                          id={"final-votes-#{pid}"}
                          class="mr-4 flex shrink-0 items-center gap-2 text-sm font-semibold"
                        >
                          <span
                            :if={@final_players[pid].thumbs_up > 0}
                            class="flex items-center gap-1 text-green-700"
                            aria-label={"#{@final_players[pid].thumbs_up} thumbs up"}
                          >
                            <.icon name={:thumbs_up} class="h-4 w-4" />
                            {@final_players[pid].thumbs_up}
                          </span>
                          <span
                            :if={@final_players[pid].thumbs_down > 0}
                            class="flex items-center gap-1 text-red-600"
                            aria-label={"#{@final_players[pid].thumbs_down} thumbs down"}
                          >
                            <.icon name={:thumbs_down} class="h-4 w-4" />
                            {@final_players[pid].thumbs_down}
                          </span>
                        </span>
                        <span class="shrink-0 text-pink-500 font-semibold">
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
                <p :if={@player_id != @host_id} class="text-sm text-gray-600">
                  Waiting for the host to return to the lobby.
                </p>
              </.card>
            </div>

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
                    <% drawing_constraint = constraint_mode(Map.get(drawing, :constraint)) %>
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
                          variant="outline"
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
                      <p
                        :if={drawing_constraint}
                        id={"final-drawing-constraint-#{drawing.drawer_id}-round-#{drawing.round_number}"}
                        class="mt-2 text-center text-sm font-bold text-yellow-600"
                      >
                        drawn with {drawing_constraint}
                      </p>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <.clipboard_handler />
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
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollFeed">
        export default {
          mounted() {
            // Follow new messages only while the user is at (or near) the
            // bottom; never yank the feed around while they're reading back.
            this.pinned = true
            this.el.addEventListener("scroll", () => {
              // A stream reset briefly clamps scrollTop to zero. Preserve the
              // user's pre-patch position until the replacement has settled.
              if (this.patching) return

              const distanceFromBottom =
                this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
              this.pinned = distanceFromBottom < 32
            })
            this.scrollToBottom()
            this.handleEvent("scroll_feed", () => this.pinned && this.scrollToBottom())
          },
          beforeUpdate() {
            this.previousScrollTop = this.el.scrollTop
            this.patching = true
          },
          updated() {
            if (this.pinned) this.scrollToBottom()
            else this.restoreScrollPosition()
          },
          scrollToBottom() {
            // Wait a frame so layout has settled; scrolling while the panel is
            // mid-patch (height not yet computed) silently clamps to the top.
            requestAnimationFrame(() => {
              this.el.scrollTop = this.el.scrollHeight
              this.finishScroll()
            })
          },
          restoreScrollPosition() {
            requestAnimationFrame(() => {
              this.el.scrollTop = this.previousScrollTop
              this.finishScroll()
            })
          },
          finishScroll() {
            requestAnimationFrame(() => {
              this.patching = false
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  def handle_event("return_to_lobby", _params, socket) do
    case Rooms.return_to_lobby(socket.assigns.room_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot return to lobby: #{reason}")}
    end
  end

  def handle_event("select_word", %{"choice" => word}, socket) do
    Rooms.select_word(socket.assigns.room_id, word)
    {:noreply, socket}
  end

  def handle_event("draw_event", event, socket) do
    Rooms.draw_event(socket.assigns.room_id, event)
    {:noreply, socket}
  end

  def handle_event("vote_drawing", %{"vote" => vote}, socket) when vote in ["up", "down"] do
    Rooms.command(socket.assigns.room_id, {:vote_drawing, if(vote == "up", do: :up, else: :down)})
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

  def handle_info({:room_snapshot, snapshot}, socket) do
    {:noreply, route_snapshot(socket, snapshot)}
  end

  def handle_info({:draw_event, event}, socket) do
    {:noreply, push_event(socket, "draw_event", event)}
  end

  defp route_snapshot(socket, snapshot) do
    if RoomRoute.screen(snapshot) == :scribble do
      apply_snapshot(socket, snapshot)
    else
      RoomRoute.navigate(socket, snapshot)
    end
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
        round_count: snapshot.round_count,
        game_variant: snapshot.game_variant,
        constraint: snapshot.constraint,
        current_round: snapshot.current_round,
        word_choices: snapshot.word_choices,
        turn_end_time: snapshot.turn_end_time,
        word: snapshot.word,
        show_word: snapshot.word_visible?,
        correct_guesses: snapshot.correct_guesses,
        drawing_vote: snapshot.drawing_vote,
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
