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
       jump_cost: 0,
       units: [],
       locked: %{},
       events: [],
       log: [],
       log_seq: 0,
       final_result: nil,
       my_spells: [],
       ammo: %{},
       map_name: nil,
       turn_end_time: nil,
       selected_spell: "firebolt",
       quick_used: false,
       retreat?: false,
       sudden_death?: false,
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

  # Boxes floating over the arena share one look: a white card with a hard black edge.
  @hud_box "border-2 border-border bg-paper shadow-[0_3px_0_#111827] rounded-base"

  def render(assigns) do
    assigns =
      assign(assigns,
        can_act?: my_turn?(assigns) and assigns.phase == :arena_aim,
        spell_rows: spell_rows(assigns.my_spells),
        selected_def: Spellslingers.spell(assigns.selected_spell),
        floating?: floating?(assigns),
        wizards: wizards(assigns),
        tuning?: assigns.dev_tools? and assigns.tuning != %{},
        hud_box: @hud_box,
        # The tour's hints run on your own turn, each clearing once you have done it.
        touring?:
          assigns.participation == :active and my_turn?(assigns) and assigns.phase == :arena_aim
      )

    ~H"""
    <Layouts.app flash={@flash} background="" show_sound_controls={false} show_logo={false}>
      <%!-- The arena is the whole window; everything else floats over it --%>
      <main id="spellslingers-game" class="fixed inset-0 overflow-hidden bg-indigo-950">
        <div id="arena-wrap" phx-hook="SpellCards" class="absolute inset-0">
          <div id="arena-stage" class="absolute inset-0 overflow-hidden [container-type:size]">
            <div id="arena-sky" phx-update="ignore" class="absolute inset-0" />
            <canvas
              id="arena-canvas"
              phx-hook="SpellArena"
              phx-update="ignore"
              width="1000"
              height="500"
              tabindex="0"
              class="absolute inset-0 block size-full cursor-crosshair touch-none outline-none"
              aria-label="Spellslingers arena"
            />

            <.chronicle_ticker log={@log} players={@players} />
            <.turn_banner
              can_act?={@can_act?}
              current_id={@current_id}
              retreat?={@retreat?}
              sudden_death?={@sudden_death?}
              participation={@participation}
              phase={@phase}
              players={@players}
              surging?={@surging?}
              turn_end_time={@turn_end_time}
            />
            <.menu hud_box={@hud_box} tuned?={@tuned?} tuning?={@tuning?} />
            <.hud
              can_act?={@can_act?}
              current_id={@current_id}
              floating?={@floating?}
              hud_box={@hud_box}
              jump_cost={@jump_cost}
              online={@online}
              participation={@participation}
              phase={@phase}
              players={@players}
              retreat?={@retreat?}
              selected_def={@selected_def}
              turn_end_time={@turn_end_time}
              walk_left={@walk_left}
              wind={@wind}
              wizards={@wizards}
            />
            <.spell_panel
              ammo={@ammo}
              locked={@locked}
              participation={@participation}
              quick_used={@quick_used}
              selected_spell={@selected_spell}
              spell_rows={@spell_rows}
            />
            <.help_panel />
            <.drawer
              log={@log}
              players={@players}
              tuned?={@tuned?}
              tuning={@tuning}
              tuning?={@tuning?}
            />

            <.results
              final_result={@final_result}
              host_id={@host_id}
              phase={@phase}
              players={@players}
              viewer_id={@viewer_id}
            />
          </div>

          <%!-- The SpellCards hook writes which spell's pane the panel shows in here --%>
          <style id="arena-spell-info-hot" phx-update="ignore" data-info-hot>
          </style>
        </div>

        <div
          id="arena-tour-anchor"
          phx-hook="ArenaTour"
          data-active={to_string(@touring?)}
          data-walk={@walk_budget}
          data-jump={@jump_cost}
          hidden
        />
      </main>
    </Layouts.app>
    """
  end

  attr :can_act?, :any, required: true
  attr :current_id, :any, required: true
  attr :retreat?, :any, required: true
  attr :sudden_death?, :any, required: true
  attr :participation, :any, required: true
  attr :phase, :any, required: true
  attr :players, :any, required: true
  attr :surging?, :any, required: true
  attr :turn_end_time, :any, required: true

  # Whose turn it is slams in at the top when a turn starts, then gets out of the way;
  # its id changes every turn so the animation plays again. Below it, a line for the
  # moments that need saying while spells play out.
  defp turn_banner(assigns) do
    ~H"""
    <div
      id="arena-status"
      class="pointer-events-none absolute inset-x-0 top-4 z-20 flex flex-col items-center gap-2"
    >
      <div
        :if={@phase == :arena_aim && @current_id && !@retreat?}
        id={"arena-turn-banner-#{iso_time(@turn_end_time)}"}
        class="arena-banner rounded-base border-2 border-border px-6 py-2 text-2xl font-black text-white shadow-[0_4px_0_#111827] [text-shadow:0_2px_0_#111827]"
        style={"background: #{player_color(@players, @current_id)}"}
      >
        {if @can_act?, do: "Your turn!", else: "#{player_name(@players, @current_id)}'s turn"}
      </div>
      <p
        :if={@phase == :arena_resolve and @surging?}
        id="arena-status-line"
        class="rounded-base border-2 border-border bg-paper px-3 py-1 text-sm font-black"
      >
        Coconut storm! Coconuts are coming down…
      </p>
      <p
        :if={@phase == :arena_aim and @retreat?}
        id="arena-retreat"
        class="arena-banner rounded-base border-2 border-border bg-rose-500 px-4 py-1 text-lg font-black text-white shadow-[0_3px_0_#111827] [text-shadow:0_2px_0_#111827]"
      >
        {if @can_act?, do: "Run for it!", else: "#{player_name(@players, @current_id)} retreats…"}
      </p>
      <p
        :if={@sudden_death? and @phase in [:arena_aim, :arena_resolve]}
        id="arena-sudden-death"
        class="rounded-full border-2 border-border bg-gray-900 px-3 py-0.5 text-xs font-black tracking-widest text-rose-300 uppercase"
      >
        Sudden death
      </p>
      <p
        :if={@participation != :active and @phase not in [:game_ended, nil]}
        id="arena-spectating"
        class="rounded-base border-2 border-border bg-paper px-3 py-1 text-sm font-bold"
      >
        You joined mid-duel, so you're watching this one.
      </p>
    </div>
    """
  end

  attr :hud_box, :string, required: true
  attr :tuned?, :any, required: true
  attr :tuning?, :any, required: true

  # Esc opens this: help, the full chronicle, sound, full screen and the way out.
  defp menu(assigns) do
    ~H"""
    <div class="absolute top-3 right-3 z-30 flex items-center gap-2">
      <span
        :if={@tuned?}
        id="arena-tuned"
        class="rounded-full border-2 border-border bg-violet-100 px-2 py-0.5 text-xs font-bold"
        title="Someone changed this game's rules from the dev panel"
      >
        Tuned rules
      </span>
      <button
        type="button"
        id="arena-menu-button"
        phx-click={JS.toggle(to: "#arena-menu", display: "grid")}
        class={[
          @hud_box,
          "flex cursor-pointer items-center gap-1.5 px-2.5 py-1 text-sm font-black hover:bg-amber-100"
        ]}
        aria-label="Menu"
      >
        <.icon name={:menu} class="size-4" /> Menu <.key_cap key="Esc" />
      </button>
    </div>
    <nav
      id="arena-menu"
      class={[@hud_box, "absolute top-14 right-3 z-40 hidden w-60 gap-1 p-2 text-sm font-bold"]}
      aria-label="Game menu"
    >
      <button
        type="button"
        id="arena-help-button"
        phx-click={JS.hide(to: "#arena-menu") |> JS.toggle(to: "#arena-help", display: "block")}
        class="flex cursor-pointer items-center gap-2 rounded-sm px-2 py-1.5 text-left hover:bg-amber-100"
      >
        <.icon name={:circle_question_mark} class="size-4" />
        <span class="flex-1">How to play</span>
        <.key_cap key="H" />
      </button>
      <button
        type="button"
        id="arena-chronicle-button"
        phx-click={JS.hide(to: "#arena-menu") |> open_drawer("chronicle")}
        class="flex cursor-pointer items-center gap-2 rounded-sm px-2 py-1.5 text-left hover:bg-amber-100"
      >
        <.icon name={:scroll_text} class="size-4" /> Chronicle
      </button>
      <button
        :if={@tuning?}
        type="button"
        id="arena-tuning-button"
        phx-click={JS.hide(to: "#arena-menu") |> open_drawer("tuning")}
        class="flex cursor-pointer items-center gap-2 rounded-sm px-2 py-1.5 text-left hover:bg-amber-100"
      >
        <.icon name={:sliders_horizontal} class="size-4" /> Dev tuning
      </button>
      <button
        type="button"
        id="arena-fullscreen"
        phx-click={JS.dispatch("arena:fullscreen", to: "#arena-canvas")}
        class="flex cursor-pointer items-center gap-2 rounded-sm px-2 py-1.5 text-left hover:bg-amber-100"
      >
        <.icon name={:maximize} class="size-4" />
        <span class="flex-1">Full screen</span>
        <.key_cap key="F" />
      </button>
      <div class="px-2 py-1.5">
        <Layouts.sound_volume class="shrink-0" slider_class="w-36" />
      </div>
      <.link
        navigate={~p"/"}
        id="arena-leave"
        class="flex items-center gap-2 rounded-sm border-t-2 border-border px-2 py-1.5 text-rose-700 hover:bg-rose-50"
      >
        <.icon name={:log_out} class="size-4" /> Leave game
      </.link>
    </nav>
    """
  end

  attr :can_act?, :any, required: true
  attr :current_id, :any, required: true
  attr :floating?, :any, required: true
  attr :hud_box, :string, required: true
  attr :jump_cost, :any, required: true
  attr :online, :any, required: true
  attr :participation, :any, required: true
  attr :phase, :any, required: true
  attr :players, :any, required: true
  attr :selected_def, :any, required: true
  attr :retreat?, :boolean, required: true
  attr :turn_end_time, :any, required: true
  attr :walk_left, :any, required: true
  attr :wind, :any, required: true
  attr :wizards, :any, required: true

  # The one strip along the bottom, Worms style: the clock and your spell on the left,
  # everyone's health in the middle, steps and wind on the right. While a spell charges,
  # the spell box becomes the power meter.
  defp hud(assigns) do
    ~H"""
    <div
      :if={@phase in [:arena_aim, :arena_resolve]}
      id="arena-hud"
      class="pointer-events-none absolute inset-x-3 bottom-3 z-20 flex items-end justify-between gap-3"
    >
      <div class="flex min-w-0 flex-1 basis-0 items-end gap-2.5">
        <.starburst_timer
          position_class={
            if(@phase == :arena_aim,
              do: "shrink-0 transition-opacity duration-300",
              else: "shrink-0 opacity-50 transition-opacity duration-300"
            )
          }
          size_class="h-14 w-14"
          text_class="text-base"
          timer_id="arena-timer"
          end_time={timer_end(@phase, @turn_end_time)}
          fill={if @phase == :arena_aim, do: "#fcd34d", else: "#e5e7eb"}
          stroke="#111827"
          stroke_width="7"
        />
        <button
          :if={@participation == :active and @selected_def}
          type="button"
          id="arena-spell-chip"
          phx-click={JS.dispatch("arena:spells", to: "#arena-canvas")}
          class={[
            @hud_box,
            "pointer-events-auto flex h-12 min-w-0 cursor-pointer items-center px-3 text-left hover:bg-amber-50"
          ]}
          title="Your kit (Tab or right-click)"
        >
          <span id="arena-turn" class="flex min-w-0 items-center gap-2">
            <.spell_sprite spell={@selected_def} class="size-9 shrink-0" />
            <span class="min-w-0">
              <span
                id="arena-selected-spell"
                class="block truncate text-[15px] leading-tight font-black"
              >
                {@selected_def.name}
              </span>
              <span class="block truncate text-xs leading-tight font-bold text-gray-600">
                {cond do
                  @retreat? && @can_act? -> "thrown, run for cover"
                  @can_act? -> cast_hint(@selected_def)
                  true -> "waiting for your turn"
                end}
              </span>
            </span>
            <span class="ml-1 hidden shrink-0 sm:inline-flex"><.key_cap key="Tab" /></span>
          </span>
          <span
            id="arena-meter"
            phx-update="ignore"
            class="hidden min-w-0 items-center gap-2.5 text-sm font-black"
          >
            <span data-meter-name class="whitespace-nowrap"></span>
            <span class="relative h-6 w-56 max-w-[30vw] shrink overflow-hidden border-2 border-border bg-paper">
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
              <span
                data-meter-text
                class="absolute inset-0 grid place-items-center text-xs font-black"
              >
              </span>
            </span>
          </span>
          <span
            id="arena-thrown"
            phx-update="ignore"
            class="hidden truncate text-sm font-black"
          >
          </span>
        </button>
      </div>

      <ul id="arena-teams" class={[@hud_box, "arena-ov pointer-events-auto grid gap-1 px-3 py-2"]}>
        <li
          :for={wizard <- @wizards}
          id={"wizard-#{wizard.id}"}
          phx-click={JS.dispatch("arena:focus", to: "#arena-canvas", detail: %{id: wizard.id})}
          class={[
            "grid cursor-pointer grid-cols-[0.75rem_7rem_minmax(6rem,12rem)_2rem] items-center gap-2 text-sm font-black",
            (wizard.dead or !Map.get(@online, wizard.id, false)) && "opacity-50"
          ]}
          title={
            if Map.get(@online, wizard.id, false),
              do: "Look at #{player_name(@players, wizard.id)}",
              else: "#{player_name(@players, wizard.id)} is away"
          }
        >
          <span class={[
            "text-xs leading-none",
            wizard.id != @current_id && "invisible"
          ]}>
            ▶
          </span>
          <span
            class={["truncate", wizard.dead && "line-through"]}
            style={"color: #{player_color(@players, wizard.id)}"}
          >
            {player_name(@players, wizard.id)}
          </span>
          <span class="h-3.5 overflow-hidden rounded-full border-2 border-border bg-gray-100">
            <%!-- Scaled rather than resized, so the drop animates without page layout --%>
            <span
              class="block h-full origin-left transition-transform duration-700 ease-out"
              style={"transform: scaleX(#{wizard.hp / wizard.max_hp}); background: #{player_color(@players, wizard.id)}"}
            />
          </span>
          <span class="text-right tabular-nums">{wizard.hp}</span>
        </li>
      </ul>

      <div class="flex min-w-0 flex-1 basis-0 items-end justify-end gap-2.5">
        <div
          :if={@participation == :active}
          id="arena-moves"
          class={[@hud_box, "pointer-events-auto flex h-12 items-center gap-2 px-2.5"]}
        >
          <span
            class="flex items-center gap-1 text-sm font-black"
            title="Steps left this turn (A / D to walk)"
          >
            <.icon name={:footprints} class="size-4" />
            <span id="walk-left-count" class="tabular-nums">{@walk_left}</span>
          </span>
          <%!-- Jumps go the way the wizard faces, which only the arena hook knows --%>
          <div :if={!@floating?} id="jump-controls" class="flex gap-1">
            <button
              :for={
                {kind, key, icon, label} <- [
                  {"high", "W", :chevrons_up, "High jump"},
                  {"long", "S", :redo, "Long jump"}
                ]
              }
              type="button"
              id={"jump-#{kind}"}
              phx-click={JS.dispatch("arena:jump", to: "#arena-canvas", detail: %{kind: kind})}
              disabled={!@can_act? or @walk_left < @jump_cost}
              aria-label={label}
              title={"#{label} (#{key}), the way you face. Costs #{@jump_cost} steps."}
              class="flex h-7 cursor-pointer items-center gap-0.5 border-2 border-border bg-paper px-1.5 text-[11px] font-black hover:bg-amber-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <.icon name={icon} class="size-3.5" />{key}
            </button>
          </div>
          <div :if={@floating?} id="rise-controls" class="flex gap-1">
            <button
              :for={
                {dir, icon, label} <- [
                  {"1", :arrow_up, "Float up"},
                  {"-1", :arrow_down, "Float down"}
                ]
              }
              type="button"
              id={if dir == "1", do: "rise-up", else: "rise-down"}
              phx-click="rise"
              phx-value-dir={dir}
              disabled={!@can_act? or @walk_left == 0}
              aria-label={label}
              class="grid h-7 w-8 cursor-pointer place-items-center border-2 border-border bg-paper hover:bg-amber-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <.icon name={icon} class="size-3.5" />
            </button>
          </div>
          <button
            type="button"
            id="arena-pass"
            phx-click="pass"
            disabled={!@can_act?}
            aria-label="Pass turn"
            title="Pass turn"
            class="grid h-7 cursor-pointer place-items-center border-2 border-border bg-paper px-1.5 hover:bg-amber-50 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <.icon name={:skip_forward} class="size-4" />
          </button>
        </div>
        <div
          id="arena-wind"
          class={[@hud_box, "flex h-12 items-center gap-2 px-3 text-sm font-black"]}
          title="Wind"
        >
          <.icon name={:wind} class="size-5" />
          <div class="relative h-3.5 w-24 overflow-hidden rounded-full border-2 border-border bg-sky-50">
            <div class="absolute inset-y-0 left-1/2 w-0.5 bg-border/40" />
            <div
              class={[
                "absolute inset-y-0 transition-all duration-500",
                if(@wind < 0, do: "bg-sky-500", else: "bg-amber-400")
              ]}
              style={wind_bar_style(@wind)}
            />
          </div>
          <span class="w-10 tabular-nums">
            {cond do
              @wind < 0 -> "← #{abs(@wind)}"
              @wind > 0 -> "#{@wind} →"
              true -> "calm"
            end}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :ammo, :map, required: true
  attr :locked, :any, required: true
  attr :participation, :any, required: true
  attr :quick_used, :any, required: true
  attr :selected_spell, :any, required: true
  attr :spell_rows, :any, required: true

  # Tab or right-click slides in every spell you carry, Worms style: a paper tray of
  # wells, a colour stripe under each way of casting, and under the tray the pointed-at
  # spell's name, numbers and traits (the SpellCards hook); away from the tray it shows
  # the selected spell. Picking one closes it; the number keys still pick directly.
  defp spell_panel(assigns) do
    spells =
      Enum.flat_map(assigns.spell_rows, fn {_label, _color, row} ->
        Enum.map(row, &elem(&1, 0))
      end)

    shown =
      if Enum.any?(spells, &(&1.id == assigns.selected_spell)),
        do: assigns.selected_spell,
        else: List.first(Enum.map(spells, & &1.id))

    assigns = assign(assigns, spells: spells, shown: shown)

    ~H"""
    <div
      :if={@participation == :active}
      id="arena-spells"
      class="kit-panel absolute top-1/2 right-4 z-30 hidden -translate-y-1/2"
    >
      <div class="absolute -top-6 right-4 flex h-6 items-center gap-1.5 rounded-t-[9px] bg-gray-800 pr-1.5 pl-2.5 text-[11px] font-black tracking-[0.16em] text-amber-200">
        KIT
        <span class="inline-grid h-4 min-w-4 place-items-center rounded-[3px] bg-amber-200 px-1 text-[9.5px] tracking-normal text-gray-900">
          Tab
        </span>
      </div>
      <div class="kit-tray bg-paper grid gap-2 p-2.5">
        <div class="flex w-[332px] flex-wrap gap-x-1 gap-y-[9px]">
          <div
            :for={{label, color, spells} <- @spell_rows}
            class="flex flex-col gap-[3px]"
            title={label}
          >
            <div class="flex gap-1">
              <button
                :for={{spell, index} <- spells}
                type="button"
                id={"spell-#{spell.id}"}
                phx-click={
                  JS.push("select_spell", value: %{spell: spell.id}) |> JS.hide(to: "#arena-spells")
                }
                data-card={spell.id}
                data-grand={spell.grand}
                aria-label={spell.name}
                aria-pressed={to_string(@selected_spell == spell.id)}
                disabled={
                  Map.has_key?(@locked, spell.id) or (spell.quick and @quick_used) or
                    Map.get(@ammo, spell.id) == 0
                }
                style={"animation-delay: #{index * 14}ms"}
                class="kit-slot relative grid size-[52px] cursor-pointer touch-none place-items-center rounded-[10px] p-0 select-none disabled:cursor-not-allowed"
              >
                <span class="absolute top-0.5 left-[5px] text-[9px] font-black text-gray-500">
                  {key_label(index)}
                </span>
                <.spell_sprite spell={spell} class="kit-sprite size-[42px]" />
                <span
                  :if={Map.has_key?(@locked, spell.id)}
                  class="absolute inset-x-[3px] bottom-[3px] flex h-4 items-center justify-center gap-0.5 rounded-[6px] bg-gray-900/80 text-[10.5px] font-black text-amber-300"
                  title={"Unlocks in #{Map.get(@locked, spell.id)} of your turns"}
                >
                  <.icon name={:lock} class="size-2.5" />
                  {Map.get(@locked, spell.id)}
                </span>
                <span
                  :if={!Map.has_key?(@locked, spell.id)}
                  class={[
                    "absolute right-[3px] bottom-[3px] grid h-[15px] min-w-4 place-items-center rounded-[6px] px-[3px] text-[10px] leading-none font-black",
                    if(Map.get(@ammo, spell.id) == 0,
                      do: "bg-gray-400 text-gray-900",
                      else: "bg-gray-900/80 text-white"
                    )
                  ]}
                  title={
                    if Map.has_key?(@ammo, spell.id),
                      do: "#{Map.get(@ammo, spell.id)} left",
                      else: "Unlimited"
                  }
                >
                  {Map.get(@ammo, spell.id, "∞")}
                </span>
              </button>
            </div>
            <i class="h-[3px] rounded-full opacity-85" style={"background: #{color}"}></i>
          </div>
        </div>
        <%!-- Every pane sits in the same grid cell, so the tray is always as tall as the
             tallest one and pointing along it never resizes or shifts it --%>
        <div id="arena-spell-info" class="grid w-[332px] grid-cols-1">
          <.spell_info
            :for={spell <- @spells}
            spell={spell}
            shown?={spell.id == @shown}
            ammo={@ammo}
            locked={@locked}
          />
        </div>
      </div>
    </div>
    """
  end

  @sprite_count Enum.max(Enum.map(Spellslingers.spells(), & &1.sprite)) + 1

  attr :spell, :map, required: true
  attr :class, :any, default: nil

  # A spell's painted picture, cut from the spells sprite sheet.
  defp spell_sprite(assigns) do
    assigns = assign(assigns, :count, @sprite_count)

    ~H"""
    <span
      class={["block bg-no-repeat", @class]}
      style={"background-image: url(/images/spellslingers/spells.webp); background-size: #{@count * 100}% 100%; background-position: #{@spell.sprite * 100 / (@count - 1)}% 0"}
      aria-hidden="true"
    />
    """
  end

  # How to play: three painted scenes, one per thing you do on a turn, with the keys
  # for each under it.
  defp help_panel(assigns) do
    ~H"""
    <div
      id="arena-help"
      class="absolute top-1/2 left-1/2 z-50 hidden max-h-[calc(100vh-2rem)] w-[min(860px,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 overflow-y-auto border-2 border-border bg-paper shadow-rounded"
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
      <div class="grid grid-cols-3 divide-x-2 divide-border">
        <.help_step n={1} image="help-move" title="Move">
          <span class="inline-flex items-center gap-1">
            <.key_cap key="A" /><.key_cap key="D" /> walk
          </span>
          <span class="inline-flex items-center gap-1">
            <.key_cap key="W" /> high jump <.key_cap key="S" /> long jump
          </span>
          <span>Cross gaps with Take Flight, or Migrate to anywhere.</span>
        </.help_step>
        <.help_step n={2} image="help-throw" title="Throw">
          <span>Hold the mouse to charge, aim with the pointer, let go to throw.</span>
          <span>Wind bends what you throw.</span>
          <span class="inline-flex items-center gap-1">
            <.key_cap key="Esc" /> or right-click cancels a charge
          </span>
        </.help_step>
        <.help_step n={3} image="help-win" title="Blast them off">
          <span>Blow the ground out from under them. The sea takes anyone who falls in.</span>
          <span>After you throw you have 4 seconds to run for cover.</span>
        </.help_step>
      </div>
      <div class="flex flex-wrap items-center gap-x-4 gap-y-1.5 border-t-2 border-border bg-amber-50 px-3 py-2 text-[13px] font-bold">
        <span class="inline-flex items-center gap-1.5">
          <.key_cap key="Tab" /> or right-click: kit
        </span>
        <span class="inline-flex items-center gap-1.5">
          <.key_cap key="1" />…<.key_cap key="-" /> pick a spell
        </span>
        <span>Scroll to zoom, right-drag to look around</span>
        <span class="inline-flex items-center gap-1.5"><.key_cap key="F" /> full screen</span>
        <span class="inline-flex items-center gap-1.5"><.key_cap key="Esc" /> menu</span>
        <span class="inline-flex items-center gap-1.5"><.key_cap key="H" /> help</span>
      </div>
    </div>
    """
  end

  attr :n, :integer, required: true
  attr :image, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp help_step(assigns) do
    ~H"""
    <div>
      <img
        src={"/images/spellslingers/guide/#{@image}.webp"}
        alt=""
        width="640"
        height="400"
        class="block aspect-[16/10] w-full border-b-2 border-border object-cover"
      />
      <div class="grid gap-1.5 px-3 py-2.5 text-[13px] leading-snug font-semibold text-gray-700">
        <h3 class="flex items-center gap-2 text-base font-black text-gray-900">
          <span class="grid size-6 place-items-center rounded-full bg-gray-900 text-xs text-white">
            {@n}
          </span>
          {@title}
        </h3>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :key, :string, required: true

  defp key_cap(assigns) do
    ~H"""
    <span class="inline-grid h-6 min-w-6 place-items-center border-2 border-b-4 border-border bg-paper px-1 text-xs font-black">
      {@key}
    </span>
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
      class="absolute inset-0 z-30 flex items-center justify-center bg-black/40 p-4 backdrop-blur-[2px]"
    >
      <.card class="w-full max-w-md bg-paper p-6 text-center">
        <.icon name={:trophy} class="mx-auto size-10 text-amber-500" />
        <h2 class="mt-2 text-2xl font-black tracking-wide uppercase">
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
        <div :if={@viewer_id == @host_id} class="mt-5 flex justify-center gap-2">
          <.button id="arena-rematch" class="inline-flex items-center gap-2" phx-click="rematch">
            <.icon name={:rotate_ccw} class="size-4" /> Rematch
          </.button>
          <.button id="arena-return-to-lobby" variant="neutral" phx-click="return_to_lobby">
            Back to lobby
          </.button>
        </div>
        <p :if={@viewer_id != @host_id} class="mt-5 text-sm text-gray-600">
          Waiting for the host to call a rematch or head back to the lobby…
        </p>
      </.card>
    </div>
    """
  end

  attr :log, :list, required: true
  attr :players, :any, required: true

  # The newest few chronicle lines, top left. Each drifts in and
  # fades out on its own; hovering holds them and offers the full log.
  defp chronicle_ticker(assigns) do
    ~H"""
    <div
      id="arena-ticker"
      class="arena-ov group/ticker pointer-events-none absolute top-3 left-3 z-20 grid w-[360px] max-w-[40vw] justify-items-start gap-0.5 [&>*]:pointer-events-auto"
    >
      <p
        :for={entry <- Enum.take(@log, 4)}
        id={"event-#{entry.seq}"}
        class="arena-feed-line rounded-sm bg-paper px-1.5 text-[13px] font-extrabold text-gray-900"
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
      class="absolute top-16 right-3 bottom-24 z-30 hidden w-[300px] flex-col gap-2 border-2 border-border bg-paper p-2.5 shadow-rounded"
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
            class="flex cursor-pointer items-center gap-1 border-2 border-border bg-paper px-2.5 py-0.5 text-xs font-black"
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
              class="w-20 rounded-base border-2 border-border bg-paper px-1.5 py-0.5 text-right tabular-nums"
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

  defp open_drawer(js \\ %JS{}, tab),
    do: js |> drawer_tab(tab) |> JS.show(to: "#arena-drawer", display: "flex")

  defp drawer_tab(js \\ %JS{}, tab) do
    {shown, hidden} =
      if tab == "tuning",
        do: {"#arena-dev-panel", "#arena-events"},
        else: {"#arena-events", "#arena-dev-panel"}

    js
    |> JS.show(to: shown, display: "grid")
    |> JS.hide(to: hidden)
    |> JS.remove_class("bg-amber-300", to: "#arena-drawer [id^=drawer-tab-]")
    |> JS.add_class("bg-paper", to: "#arena-drawer [id^=drawer-tab-]")
    |> JS.remove_class("bg-paper", to: "#drawer-tab-#{tab}")
    |> JS.add_class("bg-amber-300", to: "#drawer-tab-#{tab}")
  end

  # The tray's groups, each with the colour of its stripe and its spells' cast chips.
  @kit_groups [
    thrown: {"Thrown", "#fcd34d"},
    straight: {"Straight", "#93c5fd"},
    placed: {"Placed", "#86efac"},
    instant: {"Instant", "#f9a8d4"},
    grand: {"Big ones", "#fbbf24"}
  ]

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

  @meters [
    {"Power", :flame, :damage},
    {"Area", :target, :radius},
    {"Push", :arrow_up_right, :knock}
  ]

  # What sets each spell apart, as a worded tag that explains itself on hover. Each
  # family has a colour: what it does on a hit, how it aims, the land, moving, big ones.
  @trait_families %{
    hit: "#fb923c",
    aim: "#93c5fd",
    land: "#d6a36b",
    move: "#f9a8d4",
    big: "#fbbf24"
  }

  @traits %{
    wind: {:wind, "Rides the wind", "Wind bends it all the way.", :aim},
    light_wind: {:wind_arrow_down, "Shrugs off wind", "Wind barely moves it.", :aim},
    straight:
      {:mouse_pointer_click, "Dead straight", "No gravity, no wind: goes where you point.", :aim},
    anywhere:
      {:map_pin, "Anywhere", "Reaches any spot on the map, no line of sight needed.", :aim},
    short: {:ruler, "Short reach", "Only reaches so far.", :aim},
    bounces: {:redo_2, "Bounces", "Rolls and bounces before it goes off.", :hit},
    scatters: {:split, "Scatters", "Splits into several smaller blasts.", :hit},
    homing: {:radar, "Homing", "Turns towards the nearest enemy as it falls.", :hit},
    walks: {:footprints, "Walks", "Lands and scuttles on until it meets a flamingo.", :hit},
    pulls: {:magnet, "Pulls", "Drags the first flamingo hit over to you.", :hit},
    trap: {:timer, "Trap", "Waits, then goes off when your turn ends.", :hit},
    digs: {:shovel, "Digs", "Cuts through the land.", :land},
    builds: {:brick_wall, "Builds", "Makes new ground: bridges, roofs, cover.", :land},
    moves: {:bird, "Moves you", "Gets you somewhere else on the map.", :move},
    keeps_turn:
      {:fast_forward, "Keeps your turn", "You can still walk and throw after it.", :move},
    big: {:crown, "Big one", "Grand spell: title card, darkened sky, huge payoff.", :big},
    whole_map: {:globe, "Whole map", "Hits every part of the island at once.", :big},
    spares_you: {:shield, "Spares you", "Hurts everyone except you.", :big}
  }

  @spell_traits %{
    "firebolt" => [:wind],
    "fuserune" => [:bounces, :light_wind],
    "embers" => [:scatters, :wind],
    "thunderegg" => [:scatters, :wind],
    "seeker" => [:homing],
    "hexhare" => [:walks, :light_wind],
    "lance" => [:straight],
    "hook" => [:pulls, :short],
    "tunnel" => [:digs, :short],
    "blastrune" => [:trap],
    "meteors" => [:anywhere, :scatters],
    "slab" => [:builds],
    "broom" => [:moves, :keeps_turn],
    "blink" => [:moves, :anywhere],
    "holyorb" => [:big, :bounces],
    "anvil" => [:big, :anywhere, :digs],
    "quake" => [:big, :whole_map, :spares_you],
    "starfall" => [:big, :whole_map, :scatters]
  }

  attr :spell, :map, required: true
  attr :shown?, :boolean, required: true
  attr :ammo, :map, required: true
  attr :locked, :map, required: true

  # A spell's pane under the tray: its name, how it casts, ammo or lock, three meters
  # and its trait tags. Every pane is rendered; the selected one shows unless the hook
  # says otherwise.
  defp spell_info(assigns) do
    # Aimless spells (Flock Stomp) cast on picking, like quick ones, but end the turn.
    {how_icon, how_text} =
      if assigns.spell.input == "instant" and not assigns.spell.quick,
        do: {:zap, "Goes off on picking"},
        else: Map.fetch!(@how, assigns.spell.input)

    {_label, color} = Keyword.fetch!(@kit_groups, kit_group(assigns.spell))

    meters =
      for {label, icon, key} <- @meters,
          do: {label, icon, pips(Map.fetch!(assigns.spell, key), @maxima[key])}

    traits =
      for key <- Map.get(@spell_traits, assigns.spell.id, []) do
        {icon, label, text, family} = Map.fetch!(@traits, key)
        {icon, label, text, Map.fetch!(@trait_families, family)}
      end

    assigns =
      assign(assigns,
        how_icon: how_icon,
        how_text: how_text,
        color: color,
        meters: meters,
        traits: traits,
        locked_for: Map.get(assigns.locked, assigns.spell.id)
      )

    ~H"""
    <div
      data-info={@spell.id}
      class={[
        "spell-card-pop grid grid-cols-1 gap-2 [grid-area:1/1]",
        if(@shown?, do: "visible", else: "invisible")
      ]}
    >
      <div class="flex h-9 items-center gap-1.5 rounded-[9px] bg-gray-900/90 pr-1.5 pl-2.5 text-white">
        <b class="min-w-0 truncate text-[15px] font-black">{@spell.name}</b>
        <span
          class="ml-auto inline-flex h-[21px] shrink-0 items-center gap-1 rounded-full px-2 text-[10.5px] font-black whitespace-nowrap text-gray-900"
          style={"background: #{@color}"}
        >
          <.icon name={@how_icon} class="size-3" /> {@how_text}
        </span>
        <span
          :if={@locked_for}
          title={"Unlocks in #{@locked_for} of your turns"}
          class="inline-flex h-[21px] shrink-0 items-center gap-1 rounded-full bg-gray-950 px-2 text-[10.5px] font-black whitespace-nowrap text-amber-300"
        >
          <.icon name={:lock} class="size-3" />
          {@locked_for}
        </span>
        <span
          :if={!@locked_for}
          class="inline-flex h-[21px] shrink-0 items-center gap-1 rounded-full bg-[#fffaf0] px-2 text-[10.5px] font-black whitespace-nowrap text-gray-900"
        >
          <.icon name={:package} class="size-3" /> {Map.get(@ammo, @spell.id, "∞")}
        </span>
      </div>
      <div class="grid grid-cols-3 gap-x-2 px-0.5">
        <span
          :for={{label, icon, pips} <- @meters}
          class={[
            "flex items-center gap-1 text-[9.5px] font-black uppercase",
            !pips && "opacity-30"
          ]}
        >
          <.icon name={icon} class="size-3 shrink-0" /> {label}
          <span class="ml-auto flex gap-0.5">
            <i
              :for={i <- 1..5}
              class={[
                "h-2 w-[7px] rounded-[2px]",
                if(pips && i <= pips, do: "bg-gray-900", else: "bg-gray-900/15")
              ]}
            >
            </i>
          </span>
        </span>
      </div>
      <div class="flex flex-wrap gap-1">
        <span
          :for={{icon, label, text, color} <- @traits}
          class="kit-trait relative inline-flex h-[23px] cursor-help items-center gap-1 rounded-full bg-[#fffaf0]/85 pr-2.5 pl-2 text-[11px] font-black whitespace-nowrap shadow-[0_1px_0_rgb(80_45_15/0.25)] hover:bg-white"
        >
          <span class="contents" style={"color: #{color}"}>
            <.icon name={icon} class="size-3.5" />
          </span>
          {label}
          <span class="kit-tip pointer-events-none absolute top-full left-0 z-10 mt-2 w-52 rounded-[9px] bg-gray-900 px-2.5 py-1.5 text-[11.5px] leading-snug font-medium whitespace-normal text-gray-200 shadow-[0_8px_18px_rgb(0_0_0/0.3)]">
            <b
              class="mb-0.5 flex items-center gap-1 text-[12.5px] font-black"
              style={"color: #{color}"}
            >
              <.icon name={icon} class="size-3.5" /> {label}
            </b>
            {text}
          </span>
        </span>
      </div>
    </div>
    """
  end

  defp pips(value, _max) when value in [0, nil], do: nil
  defp pips(value, max), do: max(1, round(value / max * 5))

  # The turn banner's reminder of how the selected spell is cast.
  defp cast_hint(%{input: "charge"}), do: "hold, then let go to throw"
  defp cast_hint(%{input: "beam"}), do: "click to fire"
  defp cast_hint(%{input: "place"}), do: "click a spot"
  defp cast_hint(_spell), do: "click to use"

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

  # The arena reports each hit as it shows it, so the health bars drop with the bomb
  # that strikes rather than once the whole cast has played. Only the cast still held
  # back is touched, health only goes down, and its reveal sets every bar for certain.
  def handle_event(
        "arena_hits_shown",
        %{"cast" => id, "hits" => hits},
        %{assigns: %{pending_board: %{id: id}}} = socket
      )
      when is_list(hits) do
    shown = for %{"id" => unit, "hp" => hp} when is_integer(hp) <- hits, into: %{}, do: {unit, hp}
    units = Enum.map(socket.assigns.units, &%{&1 | hp: min(&1.hp, Map.get(shown, &1.id, &1.hp))})
    {:noreply, assign(socket, units: units)}
  end

  def handle_event("arena_hits_shown", _params, socket), do: {:noreply, socket}

  def handle_event("select_spell", %{"spell" => spell}, socket) do
    # Quick spells and aimless ones (Earthquake) need no aim: picking one casts it.
    quick? = Enum.any?(Spellslingers.spells(), &(&1.id == spell and &1.input == "instant"))

    cond do
      # A spell that is locked or spent can't be picked, even from the keyboard.
      spell not in socket.assigns.my_spells or Map.has_key?(socket.assigns.locked, spell) or
          Map.get(socket.assigns.ammo, spell) == 0 ->
        {:noreply, socket}

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
      # Too steep to walk: the arena suggests a jump over the wizard's head.
      {:error, :blocked} ->
        {:noreply, push_event(socket, "arena_blocked", %{})}

      {:error, reason} when reason not in [:no_steps_left, :not_your_turn] ->
        {:noreply, put_flash(socket, :error, command_error(reason))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("jump", %{"kind" => kind, "dir" => dir}, socket)
      when kind in ["high", "long"] and dir in @dirs do
    case Rooms.command(
           socket.assigns.room_id,
           {:jump, String.to_existing_atom(kind), parse_dir(dir)}
         ) do
      {:error, :blocked} ->
        {:noreply, push_event(socket, "arena_blocked", %{jump: true})}

      {:error, reason} when reason not in [:no_steps_left, :floating, :not_your_turn] ->
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

  def handle_event("rematch", _params, socket) do
    case Rooms.command(socket.assigns.room_id, :rematch) do
      {:error, reason} -> {:noreply, put_flash(socket, :error, command_error(reason))}
      _ -> {:noreply, socket}
    end
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
      if Map.has_key?(snapshot.locked, socket.assigns.selected_spell) or
           socket.assigns.selected_spell not in snapshot.my_spells or
           Map.get(snapshot.ammo, socket.assigns.selected_spell) == 0,
         do: "firebolt",
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
        retreat?: snapshot.retreat,
        sudden_death?: snapshot.sudden_death,
        wind: snapshot.wind,
        walk_left: snapshot.walk_left,
        walk_budget: snapshot.walk_budget,
        jump_cost: snapshot.jump_cost,
        locked: snapshot.locked,
        quick_used: Map.get(snapshot, :quick_used, false),
        final_result: snapshot.final_result,
        my_spells: snapshot.my_spells,
        ammo: snapshot.ammo,
        map_name: snapshot.map_name,
        turn_end_time: Map.get(snapshot, :turn_end_time),
        tuning: snapshot.tuning,
        tuned?: snapshot.tuned?,
        selected_spell: selected
      )

    # A rematch starts a fresh chronicle.
    socket =
      if old_phase == :game_ended and snapshot.phase != :game_ended,
        do: assign(socket, events: [], log: []),
        else: socket

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
          music: snapshot.phase in [:arena_aim, :arena_resolve],
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
          :quick_used,
          :last_jump,
          :runes,
          :retreat,
          :bot_aim,
          :walk_left
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
  # knockout waits for its slow-motion knockback (0.35x on the canvas) to land too. The
  # last blast's explosion (680 ms on the canvas) plays out first as well: the page update
  # costs a frame, a hitch in the middle of it.
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

        # A grand spell's title card plays before anything flies.
        intro = if Map.get(cast, :grand), do: p.grand_intro_ms, else: 0
        delay = round((cast.flight_steps + knock) * p.dt * 1000 / p.playback_speed) + intro + 720
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

  defp kit_group(%{grand: true}), do: :grand
  defp kit_group(%{input: "charge"}), do: :thrown
  defp kit_group(%{input: "beam"}), do: :straight
  defp kit_group(%{input: "place"}), do: :placed
  defp kit_group(_spell), do: :instant

  # Spells in hotkey order, one group per way of casting and one for the big ones.
  defp spell_rows(ids) do
    spells = ids |> my_spells() |> Enum.with_index(1)

    for {group, {label, color}} <- @kit_groups,
        row = Enum.filter(spells, fn {spell, _} -> kit_group(spell) == group end),
        row != [],
        do: {label, color, row}
  end

  defp my_spells(ids), do: Enum.map(ids, &Spellslingers.spell/1)

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

  # Only aiming has a countdown players should watch.
  defp counting_down?(phase), do: phase == :arena_aim

  defp timer_end(phase, end_time),
    do: if(counting_down?(phase), do: iso_time(end_time))

  defp iso_time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso_time(_), do: nil

  defp command_error(:retreating), do: "You've thrown this turn. Run!"
  defp command_error(:no_ammo), do: "You're out of those. Supply crates bring more."
  defp command_error(:spell_locked), do: "That isn't unlocked yet."
  defp command_error(:not_your_turn), do: "It's not your turn."
  defp command_error(:spectator), do: "You're watching this duel."
  defp command_error(:not_host), do: "Only the host can do that."
  defp command_error(:out_of_range), do: "That's too far away."
  defp command_error(:place_only), do: "Point where it should go."
  defp command_error(reason), do: "That didn't work (#{reason})."
end
