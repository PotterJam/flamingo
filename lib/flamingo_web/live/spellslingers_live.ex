defmodule FlamingoWeb.SpellslingersLive do
  use FlamingoWeb, :live_view

  alias Flamingo.GameModes.Spellslingers
  alias Flamingo.Rooms
  alias FlamingoWeb.RoomRoute

  def mount(%{"room_id" => room_id}, _session, socket) do
    {:ok,
     assign(socket,
       room_id: room_id,
       resume_token: nil,
       viewer_id: nil,
       phase: :arena_aim,
       participation: :spectator,
       players: %{},
       player_order: [],
       host_id: nil,
       online: %{},
       current_id: nil,
       wind: 0,
       walk_left: 0,
       walk_budget: 0,
       units: [],
       cooldowns: %{},
       events: [],
       final_result: nil,
       books: [],
       chosen_books: %{},
       my_spells: [],
       map_name: nil,
       turn_end_time: nil,
       selected_spell: "ember",
       quick_used: false,
       last_cast_id: nil,
       pending_board: nil
     )}
  end

  def handle_params(%{"resume_token" => token}, _uri, socket) do
    if connected?(socket) do
      case Rooms.connect(socket.assigns.room_id, token) do
        {:ok, snapshot} ->
          {:noreply, socket |> assign(:resume_token, token) |> route_snapshot(snapshot)}

        {:error, _reason} ->
          {:noreply, push_navigate(socket, to: ~p"/")}
      end
    else
      {:noreply, assign(socket, :resume_token, token)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, push_navigate(socket, to: ~p"/")}

  def render(assigns) do
    assigns =
      assign(assigns,
        my_turn?: my_turn?(assigns),
        spell_groups: spell_groups(assigns.my_spells, assigns.books),
        selected_def: Enum.find(Spellslingers.spells(), &(&1.id == assigns.selected_spell)),
        floating?: floating?(assigns),
        wizards: wizards(assigns)
      )

    ~H"""
    <Layouts.app flash={@flash} background="">
      <.flamingo_background mode={FlamingoWeb.GameModes.Spellslingers} />
      <main
        id="spellslingers-game"
        class={[
          "group min-h-dvh px-3 pt-20 pb-4 sm:px-6",
          "[&.arena-full]:fixed [&.arena-full]:inset-0 [&.arena-full]:z-60 [&.arena-full]:min-h-0 [&.arena-full]:overflow-hidden [&.arena-full]:bg-indigo-950 [&.arena-full]:p-3"
        ]}
      >
        <div class="mx-auto flex w-full max-w-6xl flex-col gap-3 group-[.arena-full]:h-full group-[.arena-full]:max-w-none">
          <header
            id="arena-header"
            class="flex h-14 items-center justify-between gap-3 rounded-base border-2 border-border bg-white pr-2 pl-4 shadow-rounded"
          >
            <div class="flex min-w-0 items-center gap-3">
              <span
                class="size-4 shrink-0 rounded-full border-2 border-border"
                style={"background: #{player_color(@players, @current_id)}"}
              />
              <p id="arena-turn" class="truncate text-lg font-black">
                <%= cond do %>
                  <% @phase == :game_ended -> %>
                    The duel is over
                  <% @phase == :arena_books -> %>
                    {@map_name}: choose two spellbooks
                  <% @my_turn? and @phase == :arena_aim -> %>
                    Your turn! Aim, then hold to charge and release.
                  <% @phase == :arena_resolve and @surging? -> %>
                    Wild magic! Meteors are falling…
                  <% @phase == :arena_resolve -> %>
                    {player_name(@players, @current_id)}'s spell is flying…
                  <% true -> %>
                    {player_name(@players, @current_id)} is casting
                <% end %>
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-4">
              <div id="arena-wind" class="flex items-center gap-2 text-sm font-bold">
                <.icon name={:wind} class="size-5" />
                <div class="relative h-3 w-28 overflow-hidden rounded-full border-2 border-border bg-sky-50">
                  <div class="absolute inset-y-0 left-1/2 w-0.5 bg-border/40" />
                  <div
                    class={[
                      "absolute inset-y-0 transition-all duration-500",
                      if(@wind < 0, do: "bg-sky-500", else: "bg-amber-400")
                    ]}
                    style={wind_bar_style(@wind)}
                  />
                </div>
                <span class="w-12 tabular-nums">
                  {cond do
                    @wind < 0 -> "← #{abs(@wind)}"
                    @wind > 0 -> "#{@wind} →"
                    true -> "calm"
                  end}
                </span>
              </div>
              <.button
                size="icon"
                variant="outline"
                id="arena-fullscreen"
                phx-click={JS.dispatch("arena:fullscreen", to: "#arena-canvas")}
                aria-label="Toggle full screen"
                title="Full screen (F)"
              >
                <.icon name={:maximize} class="size-5 group-[.arena-full]:hidden" />
                <.icon name={:minimize} class="hidden size-5 group-[.arena-full]:block" />
              </.button>
              <%!-- Always rendered so the header never changes shape; it greys out between turns --%>
              <.starburst_timer
                position_class={
                  if(counting_down?(@phase),
                    do: "shrink-0 transition-opacity duration-300",
                    else: "shrink-0 opacity-40 transition-opacity duration-300"
                  )
                }
                size_class="h-11 w-11"
                text_class="text-sm"
                timer_id="arena-timer"
                end_time={timer_end(@phase, @turn_end_time)}
                fill={if counting_down?(@phase), do: "#fcd34d", else: "#e5e7eb"}
                stroke="#111827"
                stroke_width="7"
              />
            </div>
          </header>

          <div class="grid gap-3 lg:grid-cols-[1fr_15rem] group-[.arena-full]:min-h-0 group-[.arena-full]:flex-1 group-[.arena-full]:grid-cols-[minmax(0,1fr)_15rem]">
            <div class={[
              "self-start",
              "group-[.arena-full]:flex group-[.arena-full]:min-h-0 group-[.arena-full]:items-center group-[.arena-full]:justify-center group-[.arena-full]:self-stretch group-[.arena-full]:[container-type:size]"
            ]}>
              <div class={[
                "relative overflow-hidden rounded-base border-2 border-border bg-sky-200 shadow-rounded",
                "group-[.arena-full]:w-[min(100cqw,calc(200cqh-8px))]"
              ]}>
                <canvas
                  id="arena-canvas"
                  phx-hook="SpellArena"
                  phx-update="ignore"
                  width="1000"
                  height="500"
                  tabindex="0"
                  class="block aspect-[2/1] w-full cursor-crosshair touch-none outline-none"
                  aria-label="Spellslingers arena"
                />
                <div
                  :if={@phase == :arena_books}
                  id="arena-books"
                  class="absolute inset-0 flex items-center justify-center bg-black/30 p-3 backdrop-blur-[2px]"
                >
                  <.card class="max-h-full w-full max-w-4xl overflow-y-auto bg-white p-4">
                    <div class="mb-3 flex flex-wrap items-end justify-between gap-2">
                      <div>
                        <h2 class="font-retro-display text-xl">Pick two spellbooks</h2>
                        <p class="text-xs text-gray-600">
                          Everyone knows Ember Bolt, Blink and Arcane Ward. Each book adds four spells.
                        </p>
                      </div>
                      <span
                        id="books-chosen-count"
                        class="rounded-full border-2 border-border bg-amber-100 px-3 py-1 text-sm font-black tabular-nums"
                      >
                        {length(Map.get(@chosen_books, @viewer_id, []))} / 2 chosen
                      </span>
                    </div>
                    <div class="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-5">
                      <button
                        :for={book <- @books}
                        type="button"
                        id={"book-#{book.id}"}
                        phx-click="choose_book"
                        phx-value-book={book.id}
                        aria-pressed={to_string(book.id in Map.get(@chosen_books, @viewer_id, []))}
                        disabled={@participation != :active}
                        class={[
                          "group relative flex cursor-pointer flex-col overflow-hidden rounded-base border-2 border-border bg-white text-left transition-all duration-150",
                          "hover:-translate-y-1 hover:shadow-rounded disabled:cursor-default disabled:hover:translate-y-0 disabled:hover:shadow-none",
                          book.id in Map.get(@chosen_books, @viewer_id, []) &&
                            "-translate-y-1 shadow-rounded"
                        ]}
                        style={
                          if book.id in Map.get(@chosen_books, @viewer_id, []),
                            do:
                              "background: #{book.color}1f; outline: 3px solid #{book.color}; outline-offset: 2px"
                        }
                      >
                        <div
                          class="flex items-center gap-2 border-b-2 border-border px-2.5 py-2 text-white"
                          style={"background: #{book.color}"}
                        >
                          <%= if book.id in Map.get(@chosen_books, @viewer_id, []) do %>
                            <span class="flex size-5 shrink-0 items-center justify-center rounded-full border-2 border-border bg-white text-gray-900">
                              <.icon name={:check} class="size-3" />
                            </span>
                          <% else %>
                            <.icon name={book_icon(book.id)} class="size-5 shrink-0" />
                          <% end %>
                          <span class="min-w-0 flex-1 truncate font-black">{book.name}</span>
                        </div>
                        <div class="flex flex-1 flex-col gap-2 p-2.5">
                          <p class="text-[11px] leading-snug text-gray-600">{book.blurb}</p>
                          <ul class="space-y-1">
                            <li
                              :for={spell <- my_spells(book.spells)}
                              class="flex items-center gap-1.5 text-xs font-bold"
                              title={spell.blurb}
                            >
                              <span
                                class="flex size-5 shrink-0 items-center justify-center rounded-full border border-border"
                                style={"background: #{book.color}2e; color: #{book.color}"}
                              >
                                <.icon name={spell.icon} class="size-3" />
                              </span>
                              <span class="leading-tight">{spell.name}</span>
                            </li>
                          </ul>
                          <div class="mt-auto flex min-h-6 items-center -space-x-1.5 pt-1">
                            <.flamingo_avatar
                              :for={id <- choosers(@chosen_books, book.id)}
                              avatar={get_in(@players, [id, :avatar]) || %{}}
                              class="size-6 rounded-full border-2 border-white bg-white"
                              label={player_name(@players, id)}
                            />
                          </div>
                        </div>
                      </button>
                    </div>
                  </.card>
                </div>
                <div
                  :if={@phase == :game_ended && @final_result}
                  id="arena-results"
                  class="absolute inset-0 flex items-center justify-center bg-black/30 p-4 backdrop-blur-[2px]"
                >
                  <.card class="w-full max-w-md bg-white p-6 text-center">
                    <.icon name={:trophy} class="mx-auto size-10 text-amber-500" />
                    <h2 class="mt-2 font-retro-display text-2xl">
                      {if @final_result.winner_id,
                        do: "#{player_name(@players, @final_result.winner_id)} wins!",
                        else: "Everyone fell!"}
                    </h2>
                    <ol class="mt-4 space-y-2 text-left">
                      <li
                        :for={row <- @final_result.standings}
                        id={"standing-#{row.id}"}
                        class="flex items-center gap-3 rounded-base border-2 border-border px-3 py-2"
                      >
                        <span class="w-6 font-black">{row.place}.</span>
                        <.flamingo_avatar
                          avatar={get_in(@players, [row.id, :avatar]) || %{}}
                          class="size-8"
                          label=""
                        />
                        <span class="flex-1 truncate font-bold">{player_name(@players, row.id)}</span>
                        <span class="text-xs text-gray-600">{row.damage} dmg dealt</span>
                      </li>
                    </ol>
                    <.button
                      :if={@viewer_id == @host_id}
                      id="arena-return-to-lobby"
                      class="mt-5"
                      phx-click="return_to_lobby"
                    >
                      Back to lobby
                    </.button>
                    <p :if={@viewer_id != @host_id} class="mt-5 text-sm text-gray-600">
                      Waiting for the host to head back to the lobby…
                    </p>
                  </.card>
                </div>
              </div>
            </div>

            <aside class="flex flex-col gap-3 lg:h-0 lg:min-h-full group-[.arena-full]:h-full group-[.arena-full]:min-h-0">
              <.card class="max-h-72 min-h-0 shrink-0 overflow-y-auto bg-white p-3 lg:max-h-[60%]">
                <h2 class="mb-2 text-sm font-black tracking-wide uppercase">Wizards</h2>
                <ul id="arena-wizards" class="space-y-2">
                  <li
                    :for={wizard <- @wizards}
                    id={"wizard-#{wizard.id}"}
                    class={[
                      "flex items-center gap-2 rounded-base px-1 py-0.5",
                      wizard.id == @current_id && @phase != :game_ended && "bg-amber-100",
                      wizard.dead && "opacity-40"
                    ]}
                  >
                    <.flamingo_avatar
                      avatar={get_in(@players, [wizard.id, :avatar]) || %{}}
                      class="size-9 shrink-0"
                      label=""
                    />
                    <div class="min-w-0 flex-1">
                      <div class="flex items-center gap-1 text-sm font-bold">
                        <span
                          class="size-2.5 shrink-0 rounded-full"
                          style={"background: #{player_color(@players, wizard.id)}"}
                        />
                        <span class="truncate">{player_name(@players, wizard.id)}</span>
                        <.icon :if={wizard.dead} name={:skull} class="size-3.5" />
                        <span
                          :if={!wizard.dead && !Map.get(@online, wizard.id, false)}
                          class="text-xs font-normal text-gray-500"
                        >
                          away
                        </span>
                      </div>
                      <div class="mt-1 h-2 overflow-hidden rounded-full border border-border bg-gray-100">
                        <div
                          class="h-full bg-green-500 transition-all duration-500"
                          style={"width: #{round(wizard.hp * 100 / wizard.max_hp)}%"}
                        />
                      </div>
                    </div>
                    <span class="w-7 text-right text-xs font-bold tabular-nums">{wizard.hp}</span>
                  </li>
                </ul>
              </.card>
              <.card class="min-h-24 flex-1 overflow-y-auto bg-white p-3">
                <h2 class="mb-2 text-sm font-black tracking-wide uppercase">Chronicle</h2>
                <ul id="arena-events" class="space-y-1 text-xs">
                  <li
                    :for={{event, index} <- Enum.with_index(@events)}
                    class={if(index == 0, do: "font-bold", else: "text-gray-600")}
                  >
                    {event}
                  </li>
                </ul>
              </.card>
            </aside>
          </div>

          <section
            :if={@participation == :active and @phase in [:arena_aim, :arena_resolve]}
            id="arena-controls"
            class="flex flex-wrap items-end gap-x-4 gap-y-2 rounded-base border-2 border-border bg-white p-3 shadow-rounded"
          >
            <div
              id="spell-detail"
              class="flex h-7 w-full min-w-0 items-center gap-2 rounded-base bg-amber-50 px-2.5 text-xs"
            >
              <%= if @selected_def do %>
                <.icon name={@selected_def.icon} class="size-4 shrink-0" />
                <span class="shrink-0 font-black">{@selected_def.name}</span>
                <span class="min-w-0 truncate text-gray-700">{@selected_def.blurb}</span>
                <span class="ml-auto flex shrink-0 gap-1 text-[10px] font-bold">
                  <span
                    :if={@selected_def.damage > 0}
                    class="rounded-full border border-border bg-white px-1.5 py-0.5"
                  >
                    {@selected_def.damage} damage
                  </span>
                  <span
                    :if={@selected_def.cooldown > 0}
                    class="rounded-full border border-border bg-white px-1.5 py-0.5"
                  >
                    {@selected_def.cooldown}-turn cooldown
                  </span>
                  <span
                    :if={@selected_def.quick}
                    class="rounded-full border border-sky-600 bg-sky-100 px-1.5 py-0.5 text-sky-700"
                  >
                    Quick: your turn goes on
                  </span>
                </span>
              <% end %>
            </div>
            <div id="spellbook" class="flex min-w-0 flex-1 flex-wrap items-end gap-x-4 gap-y-2">
              <div
                :for={group <- @spell_groups}
                id={"spell-group-#{group.id}"}
                class="flex flex-col gap-1.5"
              >
                <p
                  class="flex items-center gap-1.5 text-[10px] font-black tracking-widest uppercase"
                  style={"color: #{group.color}"}
                >
                  <span class="h-1 w-3 rounded-full" style={"background: #{group.color}"} />
                  {group.name}
                </p>
                <div class="flex gap-1.5">
                  <button
                    :for={{spell, index} <- group.spells}
                    type="button"
                    id={"spell-#{spell.id}"}
                    phx-click="select_spell"
                    phx-value-spell={spell.id}
                    title={spell.blurb}
                    aria-pressed={to_string(@selected_spell == spell.id)}
                    disabled={Map.get(@cooldowns, spell.id, 0) > 0 or (spell.quick and @quick_used)}
                    class={[
                      "relative flex h-[4.75rem] w-16 cursor-pointer flex-col items-center justify-center gap-1 overflow-hidden rounded-base border-2 border-border px-0.5 pt-1 text-center transition-all duration-150",
                      "disabled:cursor-not-allowed disabled:hover:translate-y-0",
                      if(@selected_spell == spell.id,
                        do: "-translate-y-1 bg-amber-300 shadow-rounded",
                        else: "bg-white hover:-translate-y-0.5 hover:bg-amber-50"
                      ),
                      (spell.quick and @quick_used) && "opacity-40"
                    ]}
                  >
                    <span class="absolute top-0.5 left-1 text-[10px] font-black text-gray-400">
                      {key_label(index)}
                    </span>
                    <.icon
                      :if={spell.quick}
                      name={:zap}
                      class="absolute top-1 right-1 size-3 fill-sky-400 text-sky-600"
                    />
                    <span
                      class="flex size-8 shrink-0 items-center justify-center rounded-full border-2 border-border"
                      style={"background: #{group.color}2e; color: #{group.color}"}
                    >
                      <.icon name={spell.icon} class="size-4" />
                    </span>
                    <span class="line-clamp-2 text-[10px] leading-tight font-bold">
                      {spell.name}
                    </span>
                    <span
                      :if={Map.get(@cooldowns, spell.id, 0) > 0}
                      class="absolute inset-0 flex flex-col items-center justify-center gap-0.5 bg-gray-800 text-white"
                    >
                      <.icon name={:hourglass} class="size-3.5" />
                      <span class="text-lg leading-none font-black">
                        {Map.get(@cooldowns, spell.id)}
                      </span>
                    </span>
                  </button>
                </div>
              </div>
            </div>

            <div
              id="arena-moves"
              class="flex w-full flex-row items-center justify-center gap-3 sm:w-auto sm:flex-col sm:gap-2"
            >
              <div class="flex items-center gap-1.5">
                <.button
                  size="icon"
                  variant="outline"
                  id="walk-left"
                  phx-click="walk"
                  phx-value-dir="-1"
                  disabled={!(@my_turn? and @phase == :arena_aim) or @walk_left == 0}
                  aria-label="Walk left"
                >
                  <.icon name={:arrow_left} class="size-5" />
                </.button>
                <div class="flex w-14 flex-col items-center gap-1 text-xs font-bold">
                  <span class="flex items-center gap-1">
                    <.icon name={:footprints} class="size-3.5" />
                    <span id="walk-left-count" class="tabular-nums">{@walk_left}</span>
                  </span>
                  <span class="h-1.5 w-full overflow-hidden rounded-full border border-border bg-gray-100">
                    <span
                      class="block h-full bg-emerald-500 transition-all duration-200"
                      style={"width: #{steps_percent(@walk_left, @walk_budget)}%"}
                    />
                  </span>
                </div>
                <.button
                  size="icon"
                  variant="outline"
                  id="walk-right"
                  phx-click="walk"
                  phx-value-dir="1"
                  disabled={!(@my_turn? and @phase == :arena_aim) or @walk_left == 0}
                  aria-label="Walk right"
                >
                  <.icon name={:arrow_right} class="size-5" />
                </.button>
              </div>
              <div :if={@floating?} id="rise-controls" class="flex items-center gap-1">
                <.button
                  size="sm"
                  variant="outline"
                  id="rise-up"
                  phx-click="rise"
                  phx-value-dir="1"
                  disabled={!(@my_turn? and @phase == :arena_aim) or @walk_left == 0}
                  aria-label="Float up"
                >
                  <.icon name={:arrow_up} class="size-4" />
                </.button>
                <.button
                  size="sm"
                  variant="outline"
                  id="rise-down"
                  phx-click="rise"
                  phx-value-dir="-1"
                  disabled={!(@my_turn? and @phase == :arena_aim) or @walk_left == 0}
                  aria-label="Float down"
                >
                  <.icon name={:arrow_down} class="size-4" />
                </.button>
              </div>
              <.button
                variant="ghost"
                size="sm"
                id="arena-pass"
                phx-click="pass"
                disabled={!(@my_turn? and @phase == :arena_aim)}
              >
                <span class="inline-flex items-center gap-1">
                  <.icon name={:skip_forward} class="size-3.5" /> Pass turn
                </span>
              </.button>
            </div>
          </section>
          <p
            :if={@participation != :active and @phase != :game_ended}
            id="arena-spectating"
            class="text-center text-sm font-bold"
          >
            You joined mid-duel, so you're watching this one.
          </p>
          <p
            :if={@participation == :active and @phase != :game_ended}
            class="text-center text-xs text-gray-600 group-[.arena-full]:hidden"
          >
            Hold the mouse (or Space) to charge thrown spells and release to cast; beams fire on click; walls, ledges and summons appear where you click. A / D walk (W / S while levitating), 1–9, 0 and - pick spells, mouse at the edge or the minimap pans, C recentres, F is full screen.
          </p>
        </div>
      </main>
    </Layouts.app>
    """
  end

  @dirs [-1, 1, "-1", "1"]

  def handle_event("choose_book", %{"book" => book}, socket) do
    Rooms.command(socket.assigns.room_id, {:choose_book, book})
    {:noreply, socket}
  end

  def handle_event("select_spell", %{"spell" => spell}, socket) do
    quick? = Enum.any?(Spellslingers.spells(), &(&1.id == spell and &1.quick))

    cond do
      spell not in socket.assigns.my_spells ->
        {:noreply, socket}

      # Quick spells need no aim: picking one casts it.
      quick? ->
        case Rooms.command(socket.assigns.room_id, {:cast, spell, 0, 0}) do
          {:error, reason} -> {:noreply, put_flash(socket, :error, command_error(reason))}
          _ -> {:noreply, socket}
        end

      true ->
        {:noreply,
         socket
         |> assign(:selected_spell, spell)
         |> push_event("arena_select", %{spell: spell})}
    end
  end

  def handle_event("rise", %{"dir" => dir}, socket) when dir in @dirs do
    Rooms.command(socket.assigns.room_id, {:rise, parse_dir(dir)})
    {:noreply, socket}
  end

  def handle_event("walk", %{"dir" => dir}, socket) when dir in @dirs do
    case Rooms.command(socket.assigns.room_id, {:walk, parse_dir(dir)}) do
      {:error, reason} when reason not in [:blocked, :no_steps_left, :not_your_turn] ->
        {:noreply, put_flash(socket, :error, command_error(reason))}

      _ ->
        {:noreply, socket}
    end
  end

  # The client names the spell it aimed, so a selection change still in flight
  # can't turn a charged throw into a placement or the reverse.
  def handle_event("cast", %{"spell" => spell, "angle" => angle, "power" => power}, socket)
      when is_binary(spell) and is_number(angle) and is_number(power),
      do: send_cast(socket, {:cast, spell, angle, power})

  def handle_event("place", %{"spell" => spell, "x" => x, "y" => y}, socket)
      when is_binary(spell) and is_number(x) and is_number(y),
      do: send_cast(socket, {:place, spell, x, y})

  def handle_event("pass", _params, socket) do
    Rooms.command(socket.assigns.room_id, :pass)
    {:noreply, socket}
  end

  def handle_event("return_to_lobby", _params, socket) do
    case Rooms.return_to_lobby(socket.assigns.room_id) do
      {:error, reason} -> {:noreply, put_flash(socket, :error, command_error(reason))}
      _ -> {:noreply, socket}
    end
  end

  # Malformed payloads issue no command.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # Keys push numbers; the on-screen buttons send phx-value strings.
  defp parse_dir(dir) when dir in [-1, "-1"], do: -1
  defp parse_dir(_dir), do: 1

  defp send_cast(socket, command) do
    case Rooms.command(socket.assigns.room_id, command) do
      {:error, reason} ->
        {:noreply,
         socket |> put_flash(:error, command_error(reason)) |> push_event("arena_unlock", %{})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:room_snapshot, snapshot}, socket),
    do: {:noreply, route_snapshot(socket, snapshot)}

  # The sidebar catches up once the cast's projectiles have landed on screen.
  def handle_info({:reveal_board, id}, %{assigns: %{pending_board: %{id: id} = board}} = socket),
    do: {:noreply, assign(socket, units: board.units, events: board.events, pending_board: nil)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp route_snapshot(socket, snapshot), do: RoomRoute.route(socket, snapshot, &apply_snapshot/2)

  defp apply_snapshot(socket, snapshot) do
    initial? = is_nil(socket.assigns.viewer_id)
    old_phase = socket.assigns.phase

    selected =
      if Map.get(snapshot.cooldowns, socket.assigns.selected_spell, 0) > 0 or
           socket.assigns.selected_spell not in snapshot.my_spells,
         do: "ember",
         else: socket.assigns.selected_spell

    socket =
      assign(socket,
        viewer_id: snapshot.viewer_id,
        phase: snapshot.phase,
        participation: snapshot.participation,
        players: snapshot.players,
        player_order: snapshot.player_order,
        host_id: snapshot.host_id,
        online: snapshot.online,
        current_id: snapshot.current_id,
        surging?: match?(%{caster_id: nil}, snapshot.last_cast),
        wind: snapshot.wind,
        walk_left: snapshot.walk_left,
        walk_budget: snapshot.walk_budget,
        cooldowns: snapshot.cooldowns,
        quick_used: Map.get(snapshot, :quick_used, false),
        final_result: snapshot.final_result,
        books: snapshot.books,
        chosen_books: snapshot.chosen_books,
        my_spells: snapshot.my_spells,
        map_name: snapshot.map_name,
        turn_end_time: Map.get(snapshot, :turn_end_time),
        selected_spell: selected
      )

    socket = defer_board(socket, snapshot, initial?)

    socket =
      socket
      |> push_event("arena_state", client_state(snapshot, selected))
      |> push_event("set_timer", %{
        end_time: timer_end(snapshot.phase, Map.get(snapshot, :turn_end_time))
      })

    if initial? or old_phase != snapshot.phase,
      do:
        push_event(socket, "sync_round_audio", %{
          music: snapshot.phase in [:arena_books, :arena_aim, :arena_resolve],
          track: ~p"/sounds/spellslingers-theme.mp3",
          countdown_end: nil
        }),
      else: socket
  end

  defp client_state(snapshot, selected) do
    snapshot
    |> Map.take([
      :phase,
      :viewer_id,
      :current_id,
      :wind,
      :width,
      :height,
      :water_level,
      :terrain,
      :units,
      :last_cast,
      :physics,
      :spells,
      :participation,
      :crates,
      :my_spells,
      :map_id,
      :quick_used
    ])
    |> Map.put(:selected_spell, selected)
    |> Map.put(
      :players,
      Map.new(snapshot.players, fn {id, p} -> {id, %{name: p.name, color: p.color}} end)
    )
  end

  # Holds back HP and chronicle updates from a new cast until its flight has played out,
  # so health bars drop when spells visibly land rather than when they are cast.
  defp defer_board(socket, snapshot, initial?) do
    cast = snapshot.last_cast
    cast_id = cast && cast.id
    board = %{units: snapshot.units, events: snapshot.events}
    pending = socket.assigns.pending_board

    cond do
      not initial? and cast_id != nil and cast_id != socket.assigns.last_cast_id ->
        p = snapshot.physics
        delay = round(cast.flight_steps * p.dt * 1000 / p.playback_speed) + 250
        Process.send_after(self(), {:reveal_board, cast_id}, delay)
        assign(socket, last_cast_id: cast_id, pending_board: Map.put(board, :id, cast_id))

      pending && pending.id == cast_id ->
        assign(socket, pending_board: Map.put(board, :id, cast_id))

      true ->
        assign(socket, units: board.units, events: board.events, last_cast_id: cast_id)
    end
  end

  defp floating?(assigns) do
    Enum.any?(assigns.units, &(&1.id == assigns.viewer_id and Map.get(&1, :float, 0) > 0))
  end

  defp key_label(index) when index <= 9, do: Integer.to_string(index)
  defp key_label(10), do: "0"
  defp key_label(11), do: "-"
  defp key_label(_), do: ""

  # Spells in hotkey order, split into runs by the book they come from.
  defp spell_groups(ids, books) do
    ids
    |> my_spells()
    |> Enum.with_index(1)
    |> Enum.chunk_by(fn {spell, _} -> book_of(books, spell.id) end)
    |> Enum.map(fn [{first, _} | _] = spells ->
      case book_of(books, first.id) do
        nil -> %{id: "core", name: "Core", color: "#64748b", spells: spells}
        book -> %{id: book.id, name: book.name, color: book.color, spells: spells}
      end
    end)
  end

  defp book_of(books, spell_id), do: Enum.find(books, &(spell_id in &1.spells))

  defp steps_percent(_left, budget) when budget in [nil, 0], do: 0
  defp steps_percent(left, budget), do: round(left * 100 / budget)

  defp my_spells(ids) do
    by_id = Map.new(Spellslingers.spells(), &{&1.id, &1})
    Enum.map(ids, &Map.fetch!(by_id, &1))
  end

  defp choosers(chosen, book), do: for({id, books} <- chosen, book in books, do: id)

  defp book_icon("pyro"), do: :flame
  defp book_icon("geo"), do: :mountain
  defp book_icon("storm"), do: :cloud_lightning
  defp book_icon("wild"), do: :leaf
  defp book_icon("sky"), do: :feather
  defp book_icon(_), do: :book_open

  defp my_turn?(assigns),
    do: assigns.viewer_id != nil and assigns.viewer_id == assigns.current_id

  defp wizards(assigns) do
    by_id = Map.new(assigns.units, &{&1.id, &1})
    for id <- assigns.player_order, wizard = by_id[id], do: wizard
  end

  defp player_name(players, id), do: get_in(players, [id, :name]) || "Someone"
  defp player_color(players, id), do: get_in(players, [id, :color]) || "#9ca3af"

  defp wind_bar_style(wind) do
    width = abs(wind) * 5

    if wind < 0,
      do: "right: 50%; width: #{width}%",
      else: "left: 50%; width: #{width}%"
  end

  # Only aiming and the spellbook pick have a countdown players should watch.
  defp counting_down?(phase), do: phase in [:arena_aim, :arena_books]

  defp timer_end(phase, end_time),
    do: if(counting_down?(phase), do: iso_time(end_time))

  defp iso_time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso_time(_), do: nil

  defp command_error(:spell_cooling_down), do: "That spell is still recharging."
  defp command_error(:not_your_turn), do: "It's not your turn."
  defp command_error(:spectator), do: "You're watching this duel."
  defp command_error(:not_host), do: "Only the host can do that."
  defp command_error(:out_of_range), do: "That's too far away to conjure."
  defp command_error(:place_only), do: "Point where that spell should appear."
  defp command_error(reason), do: "That didn't work (#{reason})."
end
