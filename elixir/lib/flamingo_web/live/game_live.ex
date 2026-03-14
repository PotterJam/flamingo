defmodule FlamingoWeb.GameLive do
  use FlamingoWeb, :live_view

  alias Flamingo.Games

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
       host_id: nil,
       drawer_id: nil,
       round_count: 3,
       round_length: 45,
       word_choices: nil,
       turn_end_time: nil,
       word: nil
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

            socket =
              assign(socket,
                player_id: player_id,
                phase: state.phase,
                players: state.players,
                player_order: state.player_order,
                host_id: state.host_id,
                drawer_id: state.drawer_id,
                round_count: state.round_count,
                round_length: state.round_length,
                word_choices: word_choices,
                turn_end_time: state.turn_end_time
              )

            socket =
              if state.phase == :word_choice and state.turn_end_time do
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

            socket = push_event(socket, "play_sound", %{sound: "join"})

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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} background={if(@phase == :lobby, do: "grid-background", else: "")}>
      <div id="sound-manager" phx-hook="SoundManager" phx-update="ignore"></div>
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
                        value={@round_length}
                        name="settings[round_length]"
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
      <%= if @phase in [:word_choice, :playing] do %>
        <.flamingo_background />
        <div class="flex h-screen w-full items-center justify-center p-6">
          <div class="flex h-[675px] w-full max-w-[1200px] flex-col gap-3">
            <.game_header />

            <div class="flex w-full flex-1 flex-row gap-3 pb-1 pr-1">
              <.player_list_panel
                players={@players}
                player_order={@player_order}
                drawer_id={@drawer_id}
              />

              <%= if @phase == :word_choice do %>
                <.box class="flex w-[704px] shrink-0 items-center justify-center bg-white">
                  <%= if @player_id == @drawer_id do %>
                    <div class="relative flex flex-col items-center gap-8">
                      <div class="absolute -top-36 -right-16">
                        <div class="relative flex items-center justify-center">
                          <svg
                            class="starburst h-32 w-32"
                            viewBox="0 0 200 200"
                            xmlns="http://www.w3.org/2000/svg"
                          >
                            <path
                              d={starburst_path()}
                              fill="var(--color-pink-300)"
                            />
                          </svg>
                          <span
                            id="word-choice-timer"
                            phx-hook=".Timer"
                            phx-update="ignore"
                            class="absolute font-timer text-3xl font-black"
                            style="font-variant-numeric: tabular-nums; letter-spacing: 0.05em; min-width: 3ch; text-align: center;"
                          >
                          </span>
                        </div>
                      </div>
                      <h2 class="font-timer text-3xl font-black">Choose a word</h2>
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
                      <div class="absolute -bottom-32 -right-20">
                        <div class="relative flex items-center justify-center">
                          <svg
                            class="starburst h-28 w-28"
                            viewBox="0 0 200 200"
                            xmlns="http://www.w3.org/2000/svg"
                          >
                            <path
                              d={starburst_path()}
                              fill="var(--color-pink-300)"
                            />
                          </svg>
                          <span
                            id="word-choice-timer"
                            phx-hook=".Timer"
                            phx-update="ignore"
                            class="absolute font-timer text-2xl font-black"
                            style="font-variant-numeric: tabular-nums; letter-spacing: 0.05em; min-width: 3ch; text-align: center;"
                          >
                          </span>
                        </div>
                      </div>
                      <p class="font-timer text-3xl font-black">
                        <span class="text-pink-400">{Map.get(@players, @drawer_id).name}</span>{" "}is picking a word
                      </p>
                    </div>
                  <% end %>
                </.box>
              <% else %>
                <div
                  id="drawing-canvas"
                  phx-hook="DrawingCanvas"
                  phx-update="ignore"
                  data-is-drawer={to_string(@player_id == @drawer_id)}
                  class="flex w-[704px] shrink-0 flex-col gap-2"
                >
                  <.box class="bg-white p-0">
                    <canvas
                      width="700"
                      height="500"
                      class={[
                        "bg-white",
                        if(@player_id == @drawer_id, do: "cursor-crosshair", else: "cursor-default")
                      ]}
                    >
                    </canvas>
                  </.box>

                  <%= if @player_id == @drawer_id do %>
                    <.box class="bg-white p-0">
                      <.drawing_toolbar palette={palette()} />
                    </.box>
                  <% end %>
                </div>
              <% end %>

              <.box class="flex w-full flex-1 flex-col bg-white p-0">
                <div class="flex-1" />
              </.box>
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
            this.handleEvent("set_timer", ({end_time}) => {
              const endMs = new Date(end_time).getTime()
              const update = () => {
                const remaining = Math.max(0, Math.ceil((endMs - Date.now()) / 1000))
                this.el.innerText = String(remaining).padStart(2, '0')
                if (remaining > 0) requestAnimationFrame(update)
              }
              update()
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
    </Layouts.app>
    """
  end

  def handle_event("update_settings", %{"settings" => params}, socket) do
    round_count = String.to_integer(params["round_count"])

    round_length =
      case Integer.parse(params["round_length"]) do
        {val, _} -> max(val, 30)
        :error -> socket.assigns.round_length
      end

    {:noreply, assign(socket, round_count: round_count, round_length: round_length)}
  end

  def handle_event("start_game", _params, socket) do
    settings = %{
      round_count: socket.assigns.round_count,
      round_length: socket.assigns.round_length
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

  def handle_info({:players_updated, players, player_order, host_id}, socket) do
    old_count = map_size(socket.assigns.players)
    new_count = map_size(players)

    socket = assign(socket, players: players, player_order: player_order, host_id: host_id)

    socket =
      if new_count > old_count do
        push_event(socket, "play_sound", %{sound: "join"})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(
        {:word_choice_started, drawer_id, word_choices, turn_end_time, round_count, round_length},
        socket
      ) do
    is_drawer = socket.assigns.player_id == drawer_id

    socket =
      assign(socket,
        phase: :word_choice,
        drawer_id: drawer_id,
        turn_end_time: turn_end_time,
        round_count: round_count,
        round_length: round_length,
        word_choices: if(is_drawer, do: word_choices, else: nil)
      )

    socket = push_event(socket, "set_timer", %{end_time: DateTime.to_iso8601(turn_end_time)})
    {:noreply, socket}
  end

  def handle_info({:round_started, drawer_id}, socket) do
    {:noreply,
     assign(socket,
       phase: :playing,
       drawer_id: drawer_id,
       word_choices: nil,
       turn_end_time: nil
     )}
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

  defp starburst_path do
    points = 10
    outer_r = 95
    inner_r = 78
    cx = 100
    cy = 100

    all_points =
      for i <- 0..(points * 2 - 1) do
        angle = :math.pi() * i / points - :math.pi() / 2
        r = if rem(i, 2) == 0, do: outer_r, else: inner_r
        {Float.round(cx + r * :math.cos(angle), 1), Float.round(cy + r * :math.sin(angle), 1)}
      end

    n = length(all_points)
    t = 0.15

    segments =
      for i <- 0..(n - 1) do
        {x0, y0} = Enum.at(all_points, rem(i - 1 + n, n))
        {x1, y1} = Enum.at(all_points, i)
        {x2, y2} = Enum.at(all_points, rem(i + 1, n))

        ax = Float.round(x1 + t * (x0 - x1), 1)
        ay = Float.round(y1 + t * (y0 - y1), 1)
        bx = Float.round(x1 + t * (x2 - x1), 1)
        by = Float.round(y1 + t * (y2 - y1), 1)

        "L#{ax},#{ay} Q#{x1},#{y1} #{bx},#{by}"
      end

    [{ax0, ay0} | _] =
      for i <- 0..(n - 1) do
        {x0, y0} = Enum.at(all_points, rem(i - 1 + n, n))
        {x1, y1} = Enum.at(all_points, i)
        {Float.round(x1 + t * (x0 - x1), 1), Float.round(y1 + t * (y0 - y1), 1)}
      end

    "M#{ax0},#{ay0} " <> Enum.join(segments, " ") <> " Z"
  end
end
