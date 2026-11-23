defmodule FlamingoWeb.SpellslingersLive do
  use FlamingoWeb, :live_view

  alias Flamingo.GameModes.Spellslingers
  alias Flamingo.GameModes.Spellslingers.Catalog
  alias Flamingo.Rooms
  alias FlamingoWeb.RoomRoute

  def mount(%{"room_id" => room_id}, _session, socket) do
    {:ok,
     assign(socket,
       room_id: room_id,
       resume_token: nil,
       viewer_id: nil,
       phase: nil,
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
       log: [],
       log_seq: 0,
       final_result: nil,
       books: [],
       chosen_books: %{},
       books_ready: [],
       my_spells: [],
       map_name: nil,
       turn_end_time: nil,
       selected_spell: "ember",
       quick_used: false,
       last_cast_id: nil,
       pending_board: nil,
       sent: %{},
       tuning: %{},
       tuned?: false,
       surging?: false,
       dev_tools?: Flamingo.DevTools.allowed?(socket.assigns[:current_scope])
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
        can_act?: my_turn?(assigns) and assigns.phase == :arena_aim,
        spell_groups: spell_groups(assigns.my_spells, assigns.books),
        selected_def: Spellslingers.spell(assigns.selected_spell),
        floating?: floating?(assigns),
        wizards: wizards(assigns),
        tuning?: assigns.dev_tools? and assigns.tuning != %{},
        # The tour teaches while someone else is casting, so it never eats your own turn.
        watching?:
          assigns.participation == :active and assigns.phase in [:arena_aim, :arena_resolve] and
            not my_turn?(assigns)
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
        <div class="relative mx-auto flex w-full max-w-6xl flex-col gap-3 group-[.arena-full]:h-full group-[.arena-full]:max-w-none">
          <.turn_header
            can_act?={@can_act?}
            current_id={@current_id}
            map_name={@map_name}
            phase={@phase}
            players={@players}
            selected_def={@selected_def}
            surging?={@surging?}
            tuned?={@tuned?}
            turn_end_time={@turn_end_time}
            wind={@wind}
          />

          <div
            id="arena-wrap"
            phx-hook="SpellCards"
            class="relative group-[.arena-full]:min-h-0 group-[.arena-full]:flex-1"
          >
            <div
              id="arena-stage"
              class={[
                "relative overflow-hidden rounded-base border-2 border-border bg-sky-300 shadow-rounded",
                "group-[.arena-full]:h-full group-[.arena-full]:shadow-none group-[.arena-full]:[container-type:size]"
              ]}
            >
              <div id="arena-sky" phx-update="ignore" class="absolute inset-0" />
              <canvas
                id="arena-canvas"
                phx-hook="SpellArena"
                phx-update="ignore"
                width="1000"
                height="500"
                tabindex="0"
                class={[
                  "relative block aspect-[2/1] w-full cursor-crosshair touch-none outline-none",
                  "group-[.arena-full]:absolute group-[.arena-full]:bottom-0 group-[.arena-full]:left-1/2 group-[.arena-full]:aspect-auto group-[.arena-full]:h-full group-[.arena-full]:w-[min(100cqw,200cqh)] group-[.arena-full]:-translate-x-1/2"
                ]}
                aria-label="Spellslingers arena"
              />

              <div
                id="arena-overlays"
                class="pointer-events-none absolute inset-0 group-[.arena-full]:top-[70px]"
              >
                <.wizard_rail
                  current_id={@current_id}
                  online={@online}
                  phase={@phase}
                  players={@players}
                  wizards={@wizards}
                />
                <div class="absolute top-2.5 right-2.5 flex w-[16%] min-w-32 flex-col items-end gap-3">
                  <canvas
                    id="arena-minimap"
                    phx-update="ignore"
                    class="pointer-events-auto block w-full cursor-pointer"
                    aria-label="Minimap"
                  />
                  <.chronicle_ticker log={@log} players={@players} />
                </div>
                <button
                  :if={@tuning?}
                  type="button"
                  id="arena-tuning-button"
                  phx-click={open_drawer("tuning")}
                  class="arena-ov pointer-events-auto absolute right-2.5 bottom-2.5 grid size-8 cursor-pointer place-items-center rounded-base hover:bg-amber-100"
                  aria-label="Tuning"
                  title="Dev tuning"
                >
                  <.icon name={:sliders_horizontal} class="size-5" />
                </button>
              </div>

              <.books_picker
                books={@books}
                chosen_books={@chosen_books}
                books_ready={@books_ready}
                online={@online}
                player_order={@player_order}
                participation={@participation}
                phase={@phase}
                players={@players}
                viewer_id={@viewer_id}
              />
              <.results
                final_result={@final_result}
                host_id={@host_id}
                phase={@phase}
                players={@players}
                viewer_id={@viewer_id}
              />
            </div>

            <.controls
              can_act?={@can_act?}
              cooldowns={@cooldowns}
              floating?={@floating?}
              participation={@participation}
              phase={@phase}
              quick_used={@quick_used}
              selected_spell={@selected_spell}
              spell_groups={@spell_groups}
              walk_left={@walk_left}
            />

            <.drawer
              log={@log}
              players={@players}
              tuned?={@tuned?}
              tuning={@tuning}
              tuning?={@tuning?}
            />

            <%!-- The hook copies spell cards in here and draws the hover wait bar --%>
            <div
              id="spell-card-layer"
              phx-update="ignore"
              class="pointer-events-none absolute inset-0 z-40"
            >
              <div data-card-slot></div>
              <div data-card-wait hidden class="absolute h-1 bg-gray-900"></div>
              <style data-card-hot>
              </style>
            </div>
          </div>

          <div
            id="arena-tour-anchor"
            phx-hook="ArenaTour"
            data-active={to_string(@watching?)}
            data-walk={@walk_budget}
            hidden
          />

          <p
            :if={@participation != :active and @phase != :game_ended}
            id="arena-spectating"
            class="text-center text-sm font-bold group-[.arena-full]:hidden"
          >
            You joined mid-duel, so you're watching this one.
          </p>
        </div>

        <.spell_card :for={spell <- Spellslingers.spells()} spell={spell} />
      </main>
    </Layouts.app>
    """
  end

  attr :can_act?, :any, required: true
  attr :current_id, :any, required: true
  attr :map_name, :any, required: true
  attr :phase, :any, required: true
  attr :players, :any, required: true
  attr :selected_def, :any, required: true
  attr :surging?, :any, required: true
  attr :tuned?, :any, required: true
  attr :turn_end_time, :any, required: true
  attr :wind, :any, required: true

  # In the page this is the turn banner; in full view it is a translucent strip over the
  # top of the arena. While a spell charges, the hook swaps the text for the power meter.
  defp turn_header(assigns) do
    ~H"""
    <header
      id="arena-header"
      class={[
        "relative flex h-14 items-center justify-between gap-3 rounded-base border-2 border-border bg-white pr-2 pl-4 shadow-rounded",
        "group-[.arena-full]:absolute group-[.arena-full]:inset-x-3 group-[.arena-full]:top-3 group-[.arena-full]:z-30 group-[.arena-full]:h-12 group-[.arena-full]:bg-white/90 group-[.arena-full]:shadow-[0_3px_0_#000]"
      ]}
    >
      <div class="flex min-w-0 items-center">
        <p id="arena-turn" class="flex min-w-0 items-center gap-3 text-lg font-black">
          <span
            class="size-4 shrink-0 rounded-full border-2 border-border"
            style={"background: #{player_color(@players, @current_id)}"}
          />
          <span class="truncate">
            <%= cond do %>
              <% @phase == :game_ended -> %>
                The duel is over
              <% @phase == :arena_books -> %>
                {@map_name}: choose two spellbooks
              <% @can_act? and @selected_def.input == "charge" -> %>
                Your turn! Hold to charge, aim, and let go to throw.
              <% @can_act? -> %>
                Your turn! Aim and click to cast.
              <% @phase == :arena_resolve and @surging? -> %>
                Wild magic! Meteors are falling…
              <% @phase == :arena_resolve -> %>
                {player_name(@players, @current_id)}'s spell is flying…
              <% true -> %>
                {player_name(@players, @current_id)} is casting
            <% end %>
          </span>
        </p>
        <div
          id="arena-meter"
          phx-update="ignore"
          class="hidden min-w-0 items-center gap-2.5 text-base font-black"
        >
          <.icon name={:gauge} class="size-5 shrink-0" />
          <span data-meter-name class="whitespace-nowrap"></span>
          <span class="relative h-6 w-[380px] max-w-[38vw] shrink overflow-hidden border-2 border-border bg-white">
            <i
              data-meter-fill
              class="absolute inset-y-0 left-0 w-0 bg-[linear-gradient(90deg,#22c55e,#facc15_60%,#ef4444)]"
            >
            </i>
            <u class="absolute inset-y-0 left-1/4 w-px bg-black/20"></u>
            <u class="absolute inset-y-0 left-1/2 w-px bg-black/20"></u>
            <u class="absolute inset-y-0 left-3/4 w-px bg-black/20"></u>
            <b
              data-meter-last
              hidden
              class="absolute inset-y-0 w-[3px] bg-gray-900"
              title="Last throw"
            >
            </b>
            <span data-meter-text class="absolute inset-0 grid place-items-center text-xs font-black">
            </span>
          </span>
        </div>
        <p id="arena-thrown" phx-update="ignore" class="hidden truncate text-lg font-black"></p>
      </div>
      <div class="flex shrink-0 items-center gap-4">
        <span
          :if={@tuned?}
          id="arena-tuned"
          class="rounded-full border-2 border-border bg-violet-100 px-2 py-0.5 text-xs font-bold"
          title="Someone changed this game's rules from the dev panel"
        >
          Tuned rules
        </span>
        <.button
          size="icon"
          variant="ghost"
          id="arena-help-button"
          phx-click={JS.toggle(to: "#arena-help", display: "block")}
          aria-label="How to play"
          title="How to play (H)"
        >
          <.icon name={:circle_question_mark} class="size-5" />
        </.button>
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
          variant="ghost"
          id="arena-fullscreen"
          phx-click={JS.dispatch("arena:fullscreen", to: "#arena-canvas")}
          aria-label="Toggle full view"
          title="Full view (F)"
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
      <.help_panel />
    </header>
    """
  end

  @help_types [
    {:gauge, "hold, release", "Lobbed"},
    {:mouse_pointer_click, "click", "Beams"},
    {:crosshair, "click a spot", "Summons"},
    {:zap, "cast at once", "Quick"}
  ]

  defp help_panel(assigns) do
    assigns = assign(assigns, :types, @help_types)

    ~H"""
    <div
      id="arena-help"
      class="absolute top-[calc(100%+4px)] right-16 z-50 hidden w-[644px] max-w-[calc(100vw-2rem)] border-2 border-border bg-white shadow-rounded"
    >
      <div class="flex items-center justify-between border-b-2 border-border py-1.5 pr-2 pl-3">
        <h2 class="text-[13px] font-black tracking-wide uppercase">How to play</h2>
        <button
          type="button"
          phx-click={JS.hide(to: "#arena-help")}
          class="grid size-7 cursor-pointer place-items-center hover:bg-amber-100"
          aria-label="Close"
        >
          <.icon name={:x} class="size-4" />
        </button>
      </div>
      <.help_diagram />
      <div
        id="arena-help-cancel"
        class="flex items-center gap-2 border-t-2 border-border bg-rose-50 px-3 py-2 text-[13px] font-bold"
      >
        <span class="font-black">Cancel</span>
        <.key_cap key="Esc" />
        or right-click while charging. Nothing is spent and it's still your turn.
      </div>
      <div class="grid grid-cols-4 border-t-2 border-border">
        <div
          :for={{{icon, how, what}, index} <- Enum.with_index(@types)}
          class={["flex items-center gap-2 px-2.5 py-2", index > 0 && "border-l-2 border-border"]}
        >
          <span class="grid size-[30px] shrink-0 place-items-center rounded-full border-2 border-border bg-amber-100">
            <.icon name={icon} class="size-4" />
          </span>
          <div class="text-xs leading-tight font-bold text-gray-600">
            <span class="block text-sm font-black text-gray-900">{what}</span> {how}
          </div>
        </div>
      </div>
      <div class="flex flex-wrap items-center gap-x-4 gap-y-1.5 border-t-2 border-border bg-amber-50 px-3 py-2 text-[13px] font-bold">
        <span>Each spell's key is on its button</span>
        <span class="inline-flex items-center gap-1.5">
          <.key_cap key="A" /><.key_cap key="D" /> or <.key_cap key="←" /><.key_cap key="→" />
          walk
        </span>
        <span>Scroll or right-drag to look around</span>
        <span class="inline-flex items-center gap-1.5"><.key_cap key="F" /> full view</span>
        <span class="inline-flex items-center gap-1.5"><.key_cap key="H" /> help</span>
      </div>
    </div>
    """
  end

  attr :key, :string, required: true

  defp key_cap(assigns) do
    ~H"""
    <span class="inline-grid h-6 min-w-6 place-items-center border-2 border-b-4 border-border bg-white px-1 text-xs font-black">
      {@key}
    </span>
    """
  end

  attr :n, :integer, required: true
  attr :x, :integer, required: true
  attr :label, :string, required: true

  defp help_step(assigns) do
    ~H"""
    <g font-size="15" font-weight="800" font-family="system-ui">
      <circle cx={@x} cy="30" r="12" fill="#111827" />
      <text x={@x} y="35" fill="#fff" text-anchor="middle">{@n}</text>
      <text x={@x + 19} y="35" fill="#111827" paint-order="stroke" stroke="#fff" stroke-width="4">
        {@label}
      </text>
    </g>
    """
  end

  defp help_diagram(assigns) do
    ~H"""
    <svg
      viewBox="0 0 640 210"
      class="block h-auto w-full"
      role="img"
      aria-label="Hold to charge, aim with the mouse, let go to throw"
    >
      <defs>
        <linearGradient id="help-sky" x2="0" y2="1">
          <stop stop-color="#7dd3fc" /><stop offset="1" stop-color="#e0f2fe" />
        </linearGradient>
      </defs>
      <rect width="640" height="210" fill="url(#help-sky)" />
      <path d="M0 160 Q90 120 180 150 T360 140 T520 128 T640 145 V210 H0Z" fill="#c7d2fe" />
      <rect x="0" y="194" width="640" height="16" fill="#3b82f6" opacity=".85" />
      <path
        d="M30 166 h200 v8 h-10 v8 h-170 v-8 h-20 Z"
        fill="#a16234"
        stroke="#111827"
        stroke-width="2"
      /><rect x="30" y="160" width="200" height="8" fill="#4ade80" stroke="#111827" stroke-width="2" /><path
        d="M430 156 h180 v8 h-10 v8 h-150 v-8 h-20 Z"
        fill="#a16234"
        stroke="#111827"
        stroke-width="2"
      /><rect x="430" y="150" width="180" height="8" fill="#4ade80" stroke="#111827" stroke-width="2" />
      <path
        d="M112 126 Q 310 10 512 138"
        fill="none"
        stroke="#111827"
        stroke-width="3"
        stroke-dasharray="7 7"
      />
      <circle
        cx="512"
        cy="142"
        r="18"
        fill="#f97316"
        fill-opacity=".35"
        stroke="#111827"
        stroke-width="2.5"
      />
      <g transform="translate(98 160)" stroke="#111827" stroke-width="2" stroke-linejoin="round">
        <path d="M-9 0 L-5 -14 H5 L9 0Z" fill="#22c55e" /><circle cy="-17" r="5" fill="#fde2c8" /><path
          d="M-10 -19 L0 -38 L10 -19Z"
          fill="#22c55e"
        /><path d="M11 0 L13 -24" stroke="#78350f" stroke-width="3" /><circle
          cx="13"
          cy="-26"
          r="3"
          fill="#fde047"
        />
      </g>
      <g
        transform="translate(520 150) scale(-1 1)"
        stroke="#111827"
        stroke-width="2"
        stroke-linejoin="round"
      >
        <path d="M-9 0 L-5 -14 H5 L9 0Z" fill="#ef4444" /><circle cy="-17" r="5" fill="#fde2c8" /><path
          d="M-10 -19 L0 -38 L10 -19Z"
          fill="#ef4444"
        /><path d="M11 0 L13 -24" stroke="#78350f" stroke-width="3" /><circle
          cx="13"
          cy="-26"
          r="3"
          fill="#fde047"
        />
      </g>
      <.help_step n={1} x={30} label="Hold to charge" />
      <.help_step n={2} x={240} label="Keep aiming" />
      <.help_step n={3} x={440} label="Let go to throw" />
    </svg>
    """
  end

  attr :books, :any, required: true
  attr :chosen_books, :any, required: true
  attr :books_ready, :list, required: true
  attr :online, :map, required: true
  attr :player_order, :list, required: true
  attr :participation, :any, required: true
  attr :phase, :any, required: true
  attr :players, :any, required: true
  attr :viewer_id, :any, required: true

  defp books_picker(assigns) do
    assigns =
      assign(assigns,
        mine: Map.get(assigns.chosen_books, assigns.viewer_id, []),
        ready?: assigns.viewer_id in assigns.books_ready
      )

    ~H"""
    <div
      :if={@phase == :arena_books}
      id="arena-books"
      class="absolute inset-0 flex items-center justify-center bg-black/30 p-3 backdrop-blur-[2px] group-[.arena-full]:pt-[70px]"
    >
      <.card class="max-h-full w-full max-w-5xl overflow-y-auto bg-white p-3">
        <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
          <h2 class="font-retro-display text-xl">Pick two spellbooks</h2>
          <div :if={@participation == :active} class="flex items-center gap-2">
            <span
              id="books-chosen-count"
              class="rounded-full border-2 border-border bg-amber-100 px-3 py-1 text-sm font-black tabular-nums"
            >
              {length(@mine)} / 2 chosen
            </span>
            <.button
              id="books-ready"
              phx-click="toggle_ready"
              disabled={length(@mine) < 2}
              variant={if @ready?, do: "neutral", else: "default"}
              title={if length(@mine) < 2, do: "Choose two books first"}
            >
              <%= if @ready? do %>
                <.icon name={:check} class="size-4" /> Ready! Change books
              <% else %>
                Ready
              <% end %>
            </.button>
          </div>
        </div>
        <ul
          id="books-roster"
          class="mb-3 flex flex-wrap gap-1.5"
          aria-label="What everyone has picked"
        >
          <li
            :for={id <- @player_order}
            :if={Map.get(@online, id, false)}
            id={"books-roster-#{id}"}
            class={[
              "flex items-center gap-1.5 rounded-full border-2 border-border py-0.5 pr-1 pl-0.5 text-xs font-bold",
              if(id in @books_ready, do: "bg-green-100", else: "bg-white")
            ]}
          >
            <.flamingo_avatar
              avatar={get_in(@players, [id, :avatar]) || %{}}
              class="size-6 rounded-full border-2 border-border bg-white"
              label={player_name(@players, id)}
            />
            <span style={"color: #{player_color(@players, id)}"}>{player_name(@players, id)}</span>
            <span
              :for={book <- book_defs(@books, Map.get(@chosen_books, id, []))}
              class="grid size-5 place-items-center rounded-full border-[1.5px] border-border text-white"
              style={"background: #{book.color}"}
              title={book.name}
            >
              <.icon name={book.icon} class="size-3" />
            </span>
            <span
              :for={_ <- 1..(2 - length(Map.get(@chosen_books, id, [])))//1}
              class="size-5 rounded-full border-[1.5px] border-dashed border-gray-400"
            />
            <%= if id in @books_ready do %>
              <span class="flex items-center gap-0.5 px-1 text-green-700">
                <.icon name={:check} class="size-3.5" /> Ready
              </span>
            <% else %>
              <span class="px-1 text-gray-500">choosing…</span>
            <% end %>
          </li>
        </ul>
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <div
            id="book-core"
            data-card-anchor
            class="relative flex min-w-0 -translate-y-1 flex-col border-2 border-border bg-slate-100 shadow-rounded outline-3 outline-offset-2 outline-slate-500"
          >
            <div class="flex items-center gap-2 border-b-2 border-border bg-slate-500 px-2.5 py-1.5 font-black text-white">
              <.icon name={:lock} class="size-4 shrink-0" />
              <span class="flex-1">Core</span>
              <span class="flex items-center gap-1 text-[11px] font-extrabold">
                <.icon name={:users} class="size-3.5" /> Everyone
              </span>
            </div>
            <.book_scene id="core" />
            <.book_spells color="#64748b" tint="#e2e8f0" spells={Catalog.core()} />
          </div>
          <button
            :for={book <- @books}
            type="button"
            id={"book-#{book.id}"}
            data-card-anchor
            phx-click="choose_book"
            phx-value-book={book.id}
            aria-pressed={to_string(book.id in @mine)}
            disabled={@participation != :active}
            class={[
              "relative flex min-w-0 cursor-pointer flex-col border-2 border-border bg-white text-left transition-all duration-150",
              "hover:-translate-y-1 hover:shadow-rounded disabled:cursor-default disabled:hover:translate-y-0 disabled:hover:shadow-none",
              "[&.phx-click-loading]:-translate-y-1 [&.phx-click-loading]:scale-[0.98] [&.phx-click-loading]:shadow-rounded",
              book.id in @mine && "-translate-y-1 shadow-rounded"
            ]}
            style={
              if book.id in @mine,
                do:
                  "background: #{book.color}1f; outline: 3px solid #{book.color}; outline-offset: 2px"
            }
          >
            <div
              class="flex items-center gap-2 border-b-2 border-border px-2.5 py-1.5 font-black text-white"
              style={"background: #{book.color}"}
            >
              <%= if book.id in @mine do %>
                <span class="flex size-5 shrink-0 items-center justify-center rounded-full border-2 border-border bg-white text-gray-900">
                  <.icon name={:check} class="size-3" />
                </span>
              <% else %>
                <.icon name={book.icon} class="size-4 shrink-0" />
              <% end %>
              <span class="min-w-0 flex-1 truncate">{book.name}</span>
              <span class="flex h-6 items-center -space-x-1.5">
                <.flamingo_avatar
                  :for={id <- choosers(@chosen_books, book.id)}
                  avatar={get_in(@players, [id, :avatar]) || %{}}
                  class="size-6 rounded-full border-2 border-border bg-white"
                  label={player_name(@players, id)}
                />
              </span>
            </div>
            <.book_scene id={book.id} />
            <.book_spells color={book.color} tint={"#{book.color}55"} spells={book.spells} />
          </button>
        </div>
      </.card>
    </div>
    """
  end

  attr :id, :string, required: true

  defp book_scene(assigns) do
    ~H"""
    <div
      id={"book-scene-#{@id}"}
      phx-hook="SpellScene"
      phx-update="ignore"
      data-scene={@id}
      class="aspect-[5/2] overflow-hidden border-b-2 border-border bg-sky-200 [&>svg]:block [&>svg]:size-full"
    />
    """
  end

  attr :color, :string, required: true
  attr :tint, :string, required: true
  attr :spells, :list, required: true

  # Hovering a spell opens its card beside it, the same card the spell dock shows.
  defp book_spells(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-x-1.5 gap-y-0.5 p-1.5">
      <span
        :for={spell <- my_spells(@spells)}
        data-card={spell.id}
        data-card-place="side"
        data-card-delay="450"
        data-card-color={@tint}
        class="flex min-w-0 items-center gap-1.5 px-1 py-0.5 text-xs font-bold select-none hover:bg-amber-100"
      >
        <span
          class="grid size-[22px] shrink-0 place-items-center rounded-full border-[1.5px] border-border"
          style={"background: #{@color}2e; color: #{@color}"}
        >
          <.icon name={spell.icon} class="size-3" />
        </span>
        <span class="truncate">{spell.name}</span>
      </span>
    </div>
    """
  end

  attr :final_result, :any, required: true
  attr :host_id, :any, required: true
  attr :phase, :any, required: true
  attr :players, :any, required: true
  attr :viewer_id, :any, required: true

  defp results(assigns) do
    ~H"""
    <div
      :if={@phase == :game_ended && @final_result}
      id="arena-results"
      class="absolute inset-0 flex items-center justify-center bg-black/30 p-4 backdrop-blur-[2px] group-[.arena-full]:pt-[70px]"
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
    """
  end

  attr :current_id, :any, required: true
  attr :online, :any, required: true
  attr :phase, :any, required: true
  attr :players, :any, required: true
  attr :wizards, :any, required: true

  # Faces, names in each wizard's colour and HP, drawn straight onto the map like the
  # name labels over the wizards; hovering adds the numbers. Fallen wizards fold into one row.
  defp wizard_rail(assigns) do
    assigns =
      assign(assigns,
        alive: Enum.reject(assigns.wizards, & &1.dead),
        fallen: Enum.count(assigns.wizards, & &1.dead)
      )

    ~H"""
    <ul
      id="arena-rail"
      class="arena-ov group/rail pointer-events-auto absolute top-2.5 left-2.5 grid gap-[3px] p-0.5"
    >
      <li
        :for={wizard <- @alive}
        id={"wizard-#{wizard.id}"}
        phx-click={JS.dispatch("arena:focus", to: "#arena-canvas", detail: %{id: wizard.id})}
        class={[
          "flex h-[26px] cursor-pointer items-center gap-1.5",
          !Map.get(@online, wizard.id, false) && "opacity-60"
        ]}
        title={
          if Map.get(@online, wizard.id, false),
            do: "Look at #{player_name(@players, wizard.id)}",
            else: "#{player_name(@players, wizard.id)} is away"
        }
      >
        <span
          class="size-6 shrink-0 overflow-hidden rounded-full border-2 border-border bg-white"
          style={
            if wizard.id == @current_id and @phase != :game_ended,
              do: "box-shadow: 0 0 0 3px #fcd34d, 0 0 0 5px #000"
          }
        >
          <.flamingo_avatar
            avatar={get_in(@players, [wizard.id, :avatar]) || %{}}
            class="size-full"
            label=""
          />
        </span>
        <span
          class="arena-outline w-[108px] truncate text-xs font-extrabold"
          style={"color: #{player_color(@players, wizard.id)}"}
        >
          {player_name(@players, wizard.id)}
        </span>
        <span class="h-1.5 w-11 overflow-hidden rounded-full border-[1.5px] border-black bg-gray-100 transition-[width] duration-150 group-hover/rail:w-[70px]">
          <span
            class="block h-full bg-green-500 transition-all duration-500"
            style={"width: #{round(wizard.hp * 100 / wizard.max_hp)}%"}
          />
        </span>
        <span class="arena-outline hidden w-6 text-right text-xs font-extrabold tabular-nums group-hover/rail:inline">
          {wizard.hp}
        </span>
      </li>
      <li
        :if={@fallen > 0}
        id="wizard-fallen"
        class="arena-outline flex h-5 items-center gap-1 text-[11px] font-extrabold text-gray-500"
      >
        <.icon name={:skull} class="size-3.5" /> {@fallen}
        <span class="hidden group-hover/rail:inline">fallen</span>
      </li>
    </ul>
    """
  end

  attr :log, :list, required: true
  attr :players, :any, required: true

  # The newest few chronicle lines, as outlined text under the minimap. Each drifts in and
  # fades out on its own; hovering holds them and offers the full log.
  defp chronicle_ticker(assigns) do
    ~H"""
    <div
      id="arena-ticker"
      class="arena-ov group/ticker pointer-events-auto grid w-[340px] max-w-[45vw] justify-items-end gap-0.5 text-right"
    >
      <p
        :for={entry <- Enum.take(@log, 4)}
        id={"event-#{entry.seq}"}
        class="arena-feed-line arena-outline text-[13px] font-extrabold text-gray-900"
        phx-no-format
      ><span :for={{text, color} <- paint(entry.text, @players)} style={color && "color: #{color}"}>{text}</span></p>
      <button
        type="button"
        id="arena-full-chronicle"
        phx-click={open_drawer("chronicle")}
        class="arena-outline cursor-pointer text-[11px] font-extrabold text-gray-700 underline opacity-0 transition-opacity group-hover/ticker:opacity-100 focus-visible:opacity-100"
      >
        Full chronicle
      </button>
    </div>
    """
  end

  attr :log, :list, required: true
  attr :players, :any, required: true
  attr :tuned?, :any, required: true
  attr :tuning, :any, required: true
  attr :tuning?, :any, required: true

  defp drawer(assigns) do
    ~H"""
    <div
      id="arena-drawer"
      class="absolute top-2.5 right-2.5 bottom-2.5 z-30 hidden w-[280px] group-[.arena-full]:top-[80px] flex-col gap-2 border-2 border-border bg-white p-2.5 shadow-rounded"
    >
      <div class="flex items-center justify-between">
        <div class="flex gap-1">
          <button
            type="button"
            id="drawer-tab-chronicle"
            phx-click={drawer_tab("chronicle")}
            class="flex cursor-pointer items-center gap-1 border-2 border-border bg-amber-300 px-2.5 py-0.5 text-xs font-black"
          >
            <.icon name={:scroll_text} class="size-3.5" /> Chronicle
          </button>
          <button
            :if={@tuning?}
            type="button"
            id="drawer-tab-tuning"
            phx-click={drawer_tab("tuning")}
            class="flex cursor-pointer items-center gap-1 border-2 border-border bg-white px-2.5 py-0.5 text-xs font-black"
          >
            <.icon name={:sliders_horizontal} class="size-3.5" /> Tuning
          </button>
        </div>
        <button
          type="button"
          phx-click={JS.hide(to: "#arena-drawer")}
          class="grid size-7 cursor-pointer place-items-center hover:bg-amber-100"
          aria-label="Close"
        >
          <.icon name={:x} class="size-4" />
        </button>
      </div>
      <ol id="arena-events" class="grid min-h-0 content-start gap-1.5 overflow-y-auto text-[13px]">
        <li
          :for={{entry, index} <- Enum.with_index(@log)}
          id={"log-#{entry.seq}"}
          class={if(index == 0, do: "font-extrabold", else: "text-gray-600")}
        >
          {entry.text}
        </li>
      </ol>
      <div :if={@tuning?} id="arena-dev-panel" class="hidden min-h-0 overflow-y-auto">
        <form id="arena-tuning-form" phx-change="tune" class="space-y-1.5">
          <label
            :for={rule <- Spellslingers.tuning()}
            class="flex items-center justify-between gap-2 text-xs"
          >
            <span>{rule.label}</span>
            <input
              type="number"
              name={"tuning[#{rule.key}]"}
              value={@tuning[rule.key]}
              min={rule.min}
              max={rule.max}
              step={rule.step}
              phx-debounce="400"
              class="w-20 rounded-base border-2 border-border bg-white px-1.5 py-0.5 text-right tabular-nums"
            />
          </label>
        </form>
        <.button
          size="sm"
          variant="ghost"
          class="mt-2"
          id="arena-reset-tuning"
          phx-click="reset_tuning"
          disabled={!@tuned?}
        >
          Restore normal rules
        </.button>
      </div>
    </div>
    """
  end

  defp open_drawer(tab), do: tab |> drawer_tab() |> JS.show(to: "#arena-drawer", display: "flex")

  defp drawer_tab(tab) do
    {shown, hidden} =
      if tab == "tuning",
        do: {"#arena-dev-panel", "#arena-events"},
        else: {"#arena-events", "#arena-dev-panel"}

    JS.show(to: shown, display: "grid")
    |> JS.hide(to: hidden)
    |> JS.remove_class("bg-amber-300", to: "#arena-drawer [id^=drawer-tab-]")
    |> JS.add_class("bg-white", to: "#arena-drawer [id^=drawer-tab-]")
    |> JS.remove_class("bg-white", to: "#drawer-tab-#{tab}")
    |> JS.add_class("bg-amber-300", to: "#drawer-tab-#{tab}")
  end

  attr :can_act?, :any, required: true
  attr :cooldowns, :any, required: true
  attr :floating?, :any, required: true
  attr :participation, :any, required: true
  attr :phase, :any, required: true
  attr :quick_used, :any, required: true
  attr :selected_spell, :any, required: true
  attr :spell_groups, :any, required: true
  attr :walk_left, :any, required: true

  # The spell dock floats over the bottom of the arena: an icon hotbar grouped by book,
  # with walking and Pass turn on the same line. Spell names live in the cards.
  defp controls(assigns) do
    ~H"""
    <section
      :if={@participation == :active and @phase in [:arena_aim, :arena_resolve]}
      id="arena-controls"
      class={[
        "arena-ov z-20 mt-3 flex flex-wrap items-end justify-center gap-2.5 border-2 border-border bg-white/90 px-2.5 py-2 shadow-rounded",
        "md:absolute md:bottom-2.5 md:left-1/2 md:mt-0 md:w-max md:max-w-[calc(100%-1.25rem)] md:-translate-x-1/2"
      ]}
    >
      <div id="spellbook" class="flex flex-wrap items-end gap-2.5">
        <div
          :for={group <- @spell_groups}
          id={"spell-group-#{group.id}"}
          class="flex gap-1 border-t-4 pt-[5px]"
          style={"border-color: #{group.color}"}
          title={group.name}
        >
          <button
            :for={{spell, index} <- group.spells}
            type="button"
            id={"spell-#{spell.id}"}
            phx-click="select_spell"
            phx-value-spell={spell.id}
            data-card={spell.id}
            aria-label={spell.name}
            aria-pressed={to_string(@selected_spell == spell.id)}
            disabled={Map.get(@cooldowns, spell.id, 0) > 0 or (spell.quick and @quick_used)}
            class={[
              "relative grid size-[46px] cursor-pointer touch-none place-items-center border-2 border-border p-0 transition-all duration-150 select-none",
              "disabled:cursor-not-allowed disabled:hover:translate-y-0",
              if(@selected_spell == spell.id,
                do: "-translate-y-1 bg-amber-300 shadow-rounded",
                else: "bg-white hover:-translate-y-0.5 hover:bg-amber-50"
              ),
              (spell.quick and @quick_used) && "opacity-40"
            ]}
          >
            <span class="absolute top-0 left-[3px] text-[9px] font-black text-gray-400">
              {key_label(index)}
            </span>
            <.icon
              :if={spell.input == "charge"}
              name={:gauge}
              class="absolute top-px right-0.5 size-2.5 text-amber-700"
            />
            <.icon
              :if={spell.input == "instant"}
              name={:zap}
              class="absolute top-px right-0.5 size-2.5 text-sky-600"
            />
            <span
              class="grid size-[30px] place-items-center rounded-full border-2 border-border"
              style={"background: #{group.color}2e; color: #{group.color}"}
            >
              <.icon name={spell.icon} class="size-4" />
            </span>
            <span
              :if={Map.get(@cooldowns, spell.id, 0) > 0}
              class="absolute inset-0 flex flex-col items-center justify-center bg-gray-800 text-white"
            >
              <.icon name={:hourglass} class="size-3" />
              <span class="text-base leading-none font-black">
                {Map.get(@cooldowns, spell.id)}
              </span>
            </span>
          </button>
        </div>
      </div>

      <div id="arena-moves" class="ml-1.5 flex items-center gap-1.5">
        <.button
          size="icon"
          variant="outline"
          id="walk-left"
          phx-click="walk"
          phx-value-dir="-1"
          disabled={!@can_act? or @walk_left == 0}
          aria-label="Walk left"
        >
          <.icon name={:arrow_left} class="size-5" />
        </.button>
        <span class="flex w-11 items-center justify-center gap-1 text-xs font-bold" title="Steps left">
          <.icon name={:footprints} class="size-3.5" />
          <span id="walk-left-count" class="tabular-nums">{@walk_left}</span>
        </span>
        <.button
          size="icon"
          variant="outline"
          id="walk-right"
          phx-click="walk"
          phx-value-dir="1"
          disabled={!@can_act? or @walk_left == 0}
          aria-label="Walk right"
        >
          <.icon name={:arrow_right} class="size-5" />
        </.button>
        <div :if={@floating?} id="rise-controls" class="flex flex-col gap-0.5">
          <button
            type="button"
            id="rise-up"
            phx-click="rise"
            phx-value-dir="1"
            disabled={!@can_act? or @walk_left == 0}
            aria-label="Float up"
            class="grid h-[19px] w-8 cursor-pointer place-items-center border-2 border-border bg-white hover:bg-amber-50 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <.icon name={:arrow_up} class="size-3.5" />
          </button>
          <button
            type="button"
            id="rise-down"
            phx-click="rise"
            phx-value-dir="-1"
            disabled={!@can_act? or @walk_left == 0}
            aria-label="Float down"
            class="grid h-[19px] w-8 cursor-pointer place-items-center border-2 border-border bg-white hover:bg-amber-50 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <.icon name={:arrow_down} class="size-3.5" />
          </button>
        </div>
        <.button
          size="icon"
          variant="outline"
          id="arena-pass"
          phx-click="pass"
          disabled={!@can_act?}
          aria-label="Pass turn"
          title="Pass turn"
        >
          <.icon name={:skip_forward} class="size-5" />
        </.button>
      </div>
    </section>
    """
  end

  @how %{
    "charge" => {:gauge, "Hold to charge"},
    "beam" => {:mouse_pointer_click, "Click to fire"},
    "place" => {:crosshair, "Click a spot"},
    "instant" => {:zap, "Instant, turn goes on"}
  }

  # The biggest damage, area and knockback of any spell, so pips read out of five.
  @maxima Map.new([:damage, :radius, :knock], fn key ->
            {key, Spellslingers.spells() |> Enum.map(&Map.fetch!(&1, key)) |> Enum.max()}
          end)

  attr :spell, :map, required: true

  # One spell card per spell, copied out by the SpellCards hook: how it casts, a looping
  # clip of it being cast (drawn by the hook into data-clip), its numbers and its blurb.
  defp spell_card(assigns) do
    {how_icon, how_text} = Map.fetch!(@how, assigns.spell.input)

    assigns =
      assign(assigns, how_icon: how_icon, how_text: how_text, stats: card_stats(assigns.spell))

    ~H"""
    <template id={"spell-card-#{@spell.id}"} data-name={@spell.name} data-input={@spell.input}>
      <div class="absolute w-[300px] border-2 border-border bg-white text-left text-gray-900 shadow-rounded">
        <div
          data-card-head
          class="flex items-center gap-2 border-b-2 border-border bg-amber-300 px-2.5 py-2 text-[17px] font-black whitespace-nowrap"
        >
          <.icon name={@spell.icon} class="size-5 shrink-0" />
          {@spell.name}
          <span class="ml-auto inline-flex items-center gap-1 border-2 border-border bg-white px-1.5 py-px text-[11px] font-black">
            <.icon name={@how_icon} class="size-3" /> {@how_text}
          </span>
        </div>
        <div class="grid gap-2 px-2.5 py-2">
          <div data-clip class="border-2 border-border [&>svg]:block [&>svg]:h-auto [&>svg]:w-full">
          </div>
          <div class="grid grid-cols-[auto_1fr_auto] items-center gap-x-2 gap-y-1 text-[13px]">
            <%= for {label, icon, value, pips} <- @stats do %>
              <span class="inline-flex items-center gap-1 font-bold">
                <.icon name={icon} class="size-3.5" /> {label}
              </span>
              <span class="flex gap-[3px]">
                <i
                  :for={i <- if(pips, do: 1..5, else: [])}
                  class={[
                    "h-2 w-3 border-[1.5px] border-black",
                    if(i <= pips, do: "bg-gray-900", else: "bg-white")
                  ]}
                >
                </i>
              </span>
              <b class="text-right font-black">{value}</b>
            <% end %>
          </div>
          <p class="text-[13px] text-gray-600">
            {String.replace_prefix(@spell.blurb, "Quick: ", "")}
          </p>
        </div>
      </div>
    </template>
    """
  end

  defp card_stats(spell) do
    heal? = spell.effect == :heal

    [
      {"Damage", :flame,
       cond do
         heal? -> "+#{spell.damage}"
         spell.damage > 0 -> spell.damage
         true -> "—"
       end, pips(spell.damage, @maxima.damage)},
      {"Area", :target, if(spell.radius > 0, do: "", else: "—"),
       pips(spell.radius, @maxima.radius)},
      {"Knockback", :arrow_up_right, if(spell.knock > 0, do: "", else: "—"),
       pips(spell.knock, @maxima.knock)},
      {"Wind", :wind, wind_text(spell), nil},
      {"Cooldown", :hourglass,
       case spell.cooldown do
         0 -> "None"
         1 -> "1 turn"
         n -> "#{n} turns"
       end, nil}
    ]
  end

  defp pips(value, _max) when value in [0, nil], do: nil
  defp pips(value, max), do: max(1, round(value / max * 5))

  defp wind_text(%{input: input}) when input in ["instant", "place"], do: "—"
  defp wind_text(%{wind: wind}) when wind == 0, do: "None"
  defp wind_text(%{wind: wind}) when wind < 1, do: "Light"
  defp wind_text(_spell), do: "Full"

  # Splits a chronicle line so each wizard's name can take their colour.
  defp paint(text, players) do
    names =
      players
      |> Map.values()
      |> Enum.map(& &1.name)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.sort_by(&(-String.length(&1)))

    colors = Map.new(players, fn {_id, p} -> {p.name, p.color} end)

    case names do
      [] ->
        [{text, nil}]

      _ ->
        pattern = names |> Enum.map(&Regex.escape/1) |> Enum.join("|") |> Regex.compile!()

        pattern
        |> Regex.split(text, include_captures: true, trim: true)
        |> Enum.map(&{&1, Map.get(colors, &1)})
    end
  end

  @dirs [-1, 1, "-1", "1"]

  # Dev tuning is only for allowlisted players; everyone else's events are ignored.
  def handle_event("tune", %{"_target" => ["tuning", key], "tuning" => values}, socket)
      when socket.assigns.dev_tools? do
    with {value, ""} <- Float.parse(to_string(values[key])) do
      Rooms.command(socket.assigns.room_id, {:tune, key, value})
    end

    {:noreply, socket}
  end

  def handle_event("reset_tuning", _params, socket) when socket.assigns.dev_tools? do
    Rooms.command(socket.assigns.room_id, :reset_tuning)
    {:noreply, socket}
  end

  def handle_event("choose_book", %{"book" => book}, socket) do
    Rooms.command(socket.assigns.room_id, {:choose_book, book})
    {:noreply, socket}
  end

  def handle_event("toggle_ready", _params, socket) do
    Rooms.command(socket.assigns.room_id, :toggle_ready)
    {:noreply, socket}
  end

  def handle_event("select_spell", %{"spell" => spell}, socket) do
    quick? = Enum.any?(Spellslingers.spells(), &(&1.id == spell and &1.quick))

    cond do
      # A spell that is still recharging can't be picked, even from the keyboard.
      spell not in socket.assigns.my_spells or Map.get(socket.assigns.cooldowns, spell, 0) > 0 ->
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
    do:
      {:noreply,
       socket |> assign(units: board.units, pending_board: nil) |> assign_events(board.events)}

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
        books_ready: Map.get(snapshot, :books_ready, []),
        my_spells: snapshot.my_spells,
        map_name: snapshot.map_name,
        turn_end_time: Map.get(snapshot, :turn_end_time),
        tuning: snapshot.tuning,
        tuned?: snapshot.tuned?,
        selected_spell: selected
      )

    socket = defer_board(socket, snapshot, initial?)

    socket =
      socket
      |> push_event("arena_state", client_state(snapshot, selected, socket.assigns.sent))
      |> assign(:sent, Map.take(snapshot, [:terrain, :physics]))
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

  # The hook keeps what it already has, so the spell catalog goes out once per
  # mount, and terrain and physics (which dev tuning changes) only on change.
  defp client_state(snapshot, selected, sent) do
    full? = sent == %{}
    static = if full?, do: [:spells], else: []
    changed = for key <- [:terrain, :physics], snapshot[key] != sent[key], do: key

    snapshot
    |> Map.take(
      static ++
        changed ++
        [
          :phase,
          :viewer_id,
          :current_id,
          :wind,
          :width,
          :height,
          :water_level,
          :units,
          :last_cast,
          :participation,
          :crates,
          :my_spells,
          :map_id,
          :quick_used
        ]
    )
    |> Map.put(:selected_spell, selected)
    |> Map.put(:full, full?)
    |> Map.put(
      :players,
      Map.new(snapshot.players, fn {id, p} -> {id, %{name: p.name, color: p.color}} end)
    )
  end

  # Holds back HP and chronicle updates from a new cast until its flight has played out,
  # so health bars drop when spells visibly land rather than when they are cast. A
  # knockout waits for its slow-motion knockback (0.35x on the canvas) to land too.
  defp defer_board(socket, snapshot, initial?) do
    cast = snapshot.last_cast
    cast_id = cast && cast.id
    board = %{units: snapshot.units, events: snapshot.events}
    pending = socket.assigns.pending_board

    cond do
      not initial? and cast_id != nil and cast_id != socket.assigns.last_cast_id ->
        p = snapshot.physics

        knock =
          if cast.ko == [],
            do: 0,
            else: Enum.max(Enum.map(cast.knocks, &length(&1.path)), fn -> 0 end) / 0.35

        delay = round((cast.flight_steps + knock) * p.dt * 1000 / p.playback_speed) + 250
        Process.send_after(self(), {:reveal_board, cast_id}, delay)
        assign(socket, last_cast_id: cast_id, pending_board: Map.put(board, :id, cast_id))

      pending && pending.id == cast_id ->
        assign(socket, pending_board: Map.put(board, :id, cast_id))

      true ->
        socket
        |> assign(units: board.units, last_cast_id: cast_id)
        |> assign_events(board.events)
    end
  end

  # The game keeps its last ten lines; the chronicle keeps a longer log here, numbering
  # each line so the ticker can animate only the ones that are new.
  defp assign_events(socket, events) do
    %{events: old, log: log, log_seq: seq} = socket.assigns

    count =
      Enum.find(
        0..length(events),
        &(Enum.drop(events, &1) == Enum.take(old, length(events) - &1))
      )

    fresh =
      events
      |> Enum.take(count)
      |> Enum.reverse()
      |> Enum.with_index(seq + 1)
      |> Enum.map(fn {text, n} -> %{seq: n, text: text} end)
      |> Enum.reverse()

    assign(socket, events: events, log: Enum.take(fresh ++ log, 100), log_seq: seq + count)
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

  defp my_spells(ids), do: Enum.map(ids, &Spellslingers.spell/1)

  defp choosers(chosen, book), do: for({id, books} <- chosen, book in books, do: id)

  defp book_defs(books, ids),
    do: for(id <- ids, book = Enum.find(books, &(&1.id == id)), do: book)

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
