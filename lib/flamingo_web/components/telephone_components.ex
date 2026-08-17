defmodule FlamingoWeb.TelephoneComponents do
  use FlamingoWeb, :html

  @palette ~w(#000000 #FFFFFF #C1C1C1 #505050 #EF120B #740A08 #FF7700 #C23900 #FFE404 #E8A202 #08C202 #00461A #00FF91 #04785E #00B2FF #02569E #2220D3 #0E0865 #A302BA #550069 #DF69A7 #883454 #FFAC8A #CC7C4D #A0522D #63300D)
  @categories [
    {:derailment, "Biggest derailment", :shuffle},
    {:best_save, "Best save", :life_buoy},
    {:worst_drawing, "Wildest drawing", :paintbrush}
  ]

  attr :choices, :list, required: true
  attr :submitted, :boolean, required: true
  attr :form, :map, required: true
  attr :end_time, :string, default: nil

  def prompt_phase(assigns) do
    ~H"""
    <section
      id="telephone-prompt-phase"
      class="mx-auto flex min-h-[calc(100vh-2.5rem)] w-full max-w-4xl items-center"
    >
      <.box class="relative w-full bg-white p-6 text-center sm:p-10">
        <.starburst_timer
          position_class="absolute -top-12 -left-12 z-10"
          timer_id="telephone-timer"
          timer_hook="FlamingoWeb.TelephoneLive.TelephoneTimer"
          end_time={@end_time}
          fill="#fde047"
          stroke="#111827"
          stroke_width="4"
        />
        <h2 class="font-hero text-5xl leading-none font-black text-pink-400">
          Choose what you’ll draw
        </h2>
        <p class="mx-auto mt-3 max-w-xl text-gray-600">
          Choose the word you’ll draw first. After this someone will guess the drawing and you’ll guess someone else’s
        </p>
        <%= if @submitted do %>
          <div
            id="prompt-submitted-waiting"
            class="mt-8 rounded-base border-2 border-green-700 bg-green-100 p-6 font-bold"
          >
            <.icon name={:check_circle} class="mr-2 inline h-6 w-6" />Prompt locked in—waiting for everyone else.
          </div>
        <% else %>
          <.word_choice_buttons
            choices={@choices}
            id="telephone-prompt-choices"
            id_prefix="telephone-prompt-choice"
            event="select_prompt"
            class="mt-12"
          />
          <div class="my-6 flex items-center gap-3 text-sm text-gray-500">
            <span class="h-px flex-1 bg-gray-200"></span>
            or enter your own <span class="h-px flex-1 bg-gray-200"></span>
          </div>
          <.word_submission_form
            form={@form}
            field={@form[:prompt]}
            id="telephone-custom-prompt-form"
            input_id="telephone-custom-prompt-input"
            button_id="telephone-custom-prompt-submit"
            submit="select_prompt"
            placeholder="Enter your own…"
            button_label="Submit"
            maxlength={100}
          />
        <% end %>
      </.box>
    </section>
    """
  end

  attr :assignment, :map, default: nil
  attr :current_step, :integer, required: true
  attr :step_count, :integer, required: true
  attr :end_time, :string, default: nil

  def draw_phase(assigns) do
    assigns = assign(assigns, :palette, @palette)

    ~H"""
    <section
      id="telephone-draw-phase"
      class="mx-auto flex min-h-[calc(100vh-2.5rem)] w-full max-w-[704px] items-center"
    >
      <div class="w-full min-w-0">
        <.box class="relative mb-3 bg-white p-3 text-center">
          <.game_progress
            id="telephone-step-progress"
            label="Step"
            current={@current_step}
            total={@step_count}
            position_class="absolute -top-7 right-1 whitespace-nowrap"
          />
          <.starburst_timer
            position_class="absolute -top-10 -left-14 z-10"
            size_class="h-20 w-20"
            text_class="text-xl"
            timer_id="telephone-timer"
            timer_hook="FlamingoWeb.TelephoneLive.TelephoneTimer"
            end_time={@end_time}
            fill="#fde047"
            stroke="#111827"
            stroke_width="4"
          />
          <p id="draw-source-text" class="text-xl font-black sm:text-2xl">
            {source_text(@assignment)}
          </p>
        </.box>
        <.drawing_canvas
          id="telephone-drawing-canvas"
          is_drawer={true}
          show_toolbar={true}
          palette={@palette}
        />
      </div>
    </section>
    """
  end

  attr :assignment, :map, default: nil
  attr :submitted, :boolean, required: true
  attr :form, :map, required: true

  def guess_phase(assigns) do
    ~H"""
    <section id="telephone-guess-phase" class="mx-auto w-full max-w-4xl">
      <.box class="bg-white p-4 sm:p-6">
        <div class="mb-4 text-center">
          <p class="text-xs font-bold tracking-wider text-gray-500 uppercase">
            What is this supposed to be?
          </p>
          <h2 class="text-2xl font-black">Write the next link</h2>
        </div>
        <div
          id="telephone-guess-drawing"
          phx-hook="DrawingCanvas"
          phx-update="ignore"
          data-is-drawer="false"
          data-final-drawing-replay="false"
          data-final-drawing-events={drawing_json(@assignment)}
        >
          <div class="relative mx-auto aspect-[7/5] w-full max-w-[700px] bg-white">
            <canvas width="700" height="500" class="absolute inset-0 h-full w-full"></canvas>
            <.drawing_fallback ops={drawing_ops(@assignment)} />
          </div>
        </div>
        <%= if @submitted do %>
          <div
            id="guess-submitted-waiting"
            class="mt-5 rounded-base border-2 border-green-700 bg-green-100 p-5 text-center font-bold"
          >
            <.icon name={:check_circle} class="mr-2 inline h-6 w-6" />Guess delivered—waiting for everyone else.
          </div>
        <% else %>
          <.form
            for={@form}
            id="telephone-guess-form"
            phx-submit="submit_guess"
            class="mx-auto mt-5 flex max-w-2xl flex-col gap-2 sm:flex-row"
          >
            <div class="min-w-0 flex-1">
              <.input
                field={@form[:text]}
                id="telephone-guess-input"
                type="text"
                maxlength="100"
                autocomplete="off"
                placeholder="It looks like…"
                class="w-full rounded-base border-2 border-border bg-white px-4 py-3 text-base focus:ring-2 focus:ring-ring focus:outline-none"
              />
            </div>
            <.button
              id="telephone-guess-submit"
              type="submit"
              class="justify-center px-6 py-3 font-black"
            >
              Send guess
            </.button>
          </.form>
        <% end %>
      </.box>
    </section>
    """
  end

  attr :assignment, :map, default: nil
  attr :players, :map, required: true
  attr :viewer_id, :any, required: true
  attr :host_id, :any, required: true

  def return_phase(assigns) do
    assigns =
      assign(assigns,
        original_entry: assigns.assignment && Map.get(assigns.assignment, :origin),
        final_entry: assigns.assignment && Map.get(assigns.assignment, :source)
      )

    ~H"""
    <section id="telephone-return-phase" class="mx-auto w-full max-w-5xl space-y-6 pb-8">
      <.box class="relative overflow-hidden bg-purple-600 p-6 text-center text-white sm:p-10">
        <div aria-hidden="true" class="pointer-events-none absolute inset-0 overflow-hidden">
          <.icon
            name={:sparkles}
            class="telephone-float absolute top-3 left-[6%] h-16 w-16 text-yellow-300 opacity-70"
          />
          <.icon
            name={:rotate_cw}
            class="telephone-float absolute top-4 right-[7%] h-14 w-14 text-pink-200 opacity-60 [animation-delay:400ms]"
          />
        </div>
        <div class="relative">
          <p class="text-sm font-black tracking-[0.25em] text-yellow-200 uppercase">
            Full circle
          </p>
          <h2 class="mt-2 font-hero text-4xl font-black sm:text-6xl">Your chain made it home</h2>
          <p class="mx-auto mt-3 max-w-2xl text-lg font-bold text-purple-50">
            Here’s your private first-and-final look. The twists in the middle stay secret until the
            host starts the reveal.
          </p>
        </div>
      </.box>

      <div
        :if={@assignment}
        id="telephone-return-comparison"
        class="grid items-stretch gap-5 md:grid-cols-[1fr_auto_1fr]"
      >
        <.box class="bg-white p-5 sm:p-7">
          <p class="text-xs font-black tracking-widest text-purple-700 uppercase">Where it started</p>
          <p
            id="telephone-return-original"
            class="flex min-h-44 items-center justify-center p-4 text-center font-hero text-3xl font-black text-purple-700 sm:text-4xl"
          >
            “{present_text(@original_entry && @original_entry.value)}”
          </p>
        </.box>

        <div class="flex items-center justify-center" aria-hidden="true">
          <div class="flex h-14 w-14 rotate-3 items-center justify-center rounded-full border-2 border-border bg-yellow-300 shadow-shadow">
            <.icon name={:arrow_right} class="hidden h-7 w-7 md:block" />
            <.icon name={:arrow_down} class="h-7 w-7 md:hidden" />
          </div>
        </div>

        <.box class="telephone-reveal-current bg-yellow-50 p-5 sm:p-7">
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="text-xs font-black tracking-widest text-pink-700 uppercase">
                Where it landed
              </p>
              <p class="mt-1 font-bold">
                Final link by {player_name(@players, @final_entry && @final_entry.player_id)}
              </p>
            </div>
            <span class="rotate-2 border-2 border-border bg-pink-300 px-3 py-1 text-xs font-black uppercase shadow-shadow">
              Just for you
            </span>
          </div>

          <%= if @final_entry && @final_entry.type == :drawing do %>
            <div
              id="telephone-return-drawing"
              phx-hook="DrawingCanvas"
              phx-update="ignore"
              data-is-drawer="false"
              data-final-drawing-replay="true"
              data-final-drawing-events={Jason.encode!(@final_entry.value || [])}
              class="mt-4"
            >
              <div class="relative aspect-[7/5] w-full border-2 border-border bg-white">
                <canvas width="700" height="500" class="absolute inset-0 h-full w-full"></canvas>
                <.drawing_fallback ops={@final_entry.value || []} />
              </div>
            </div>
          <% else %>
            <p
              id="telephone-return-text"
              class="flex min-h-44 items-center justify-center p-4 text-center font-hero text-3xl font-black text-pink-600 sm:text-4xl"
            >
              “{present_text(@final_entry && @final_entry.value)}”
            </p>
          <% end %>
        </.box>
      </div>

      <.box :if={!@assignment} class="bg-white p-8 text-center">
        <p id="telephone-return-spectator" class="text-xl font-black">
          Every chain is back with its owner. The grand reveal is almost here.
        </p>
      </.box>

      <div
        id="telephone-return-controls"
        class="border-2 border-border bg-white p-5 text-center shadow-shadow"
      >
        <p class="mb-3 font-bold text-gray-600">Take it in—there’s no timer on this moment.</p>
        <.button
          :if={@viewer_id == @host_id}
          id="start-telephone-reveal"
          phx-click="start_reveal"
          class="min-w-64 justify-center px-8 py-3 text-lg font-black"
        >
          Start the grand reveal <.icon name={:sparkles} class="ml-2 h-5 w-5" />
        </.button>
        <p
          :if={@viewer_id != @host_id}
          id="waiting-for-return-host"
          class="font-bold text-gray-600"
        >
          Waiting for the host to gather everyone for the reveal…
        </p>
      </div>
    </section>
    """
  end

  attr :reveal, :map, default: nil
  attr :players, :map, required: true
  attr :viewer_id, :any, required: true
  attr :host_id, :any, required: true
  attr :participation, :atom, required: true
  attr :votes, :map, required: true
  attr :vote_counts, :map, required: true

  def reveal_phase(assigns) do
    chain = assigns.reveal && Map.get(assigns.reveal, :chain)
    entries = if chain, do: Map.get(chain, :entries, []), else: []

    assigns =
      assign(assigns,
        chain: chain,
        entries: entries,
        current_entry: List.last(entries),
        entry_count: Map.get(assigns.reveal || %{}, :entry_count, 0),
        categories: @categories
      )

    ~H"""
    <section id="telephone-reveal-phase" class="space-y-6 pb-6">
      <.box class="relative mx-auto max-w-4xl overflow-hidden bg-sky-100 p-5 text-center sm:p-8">
        <div aria-hidden="true" class="pointer-events-none absolute inset-0 overflow-hidden">
          <.icon
            name={:sparkles}
            class="telephone-float absolute top-6 left-[7%] h-16 w-16 rotate-[-12deg] text-yellow-500 opacity-60"
          />
          <.icon
            name={:shuffle}
            class="telephone-float absolute top-5 right-[7%] h-14 w-14 rotate-12 text-pink-500 opacity-50 [animation-delay:350ms]"
          />
        </div>
        <div class="relative">
          <h2 class="font-hero text-4xl leading-none font-black text-black sm:text-5xl">
            Watch the story unravel
          </h2>

          <div
            id="reveal-journey-progress"
            class="mx-auto mt-5 flex max-w-xl items-end gap-1"
            aria-label="Chain journey progress"
          >
            <div :for={index <- progress_indices(@entry_count)} class="min-w-0 flex-1">
              <p class="mb-1 truncate text-xs font-bold text-gray-700">
                {journey_label(index)}
              </p>
              <span
                data-state={progress_state(index, Map.get(@reveal || %{}, :entry_index))}
                class={[
                  "block h-2 w-full rounded-full border-2 border-border transition-all duration-300",
                  progress_class(index, Map.get(@reveal || %{}, :entry_index))
                ]}
              >
              </span>
            </div>
          </div>
        </div>
      </.box>
      <div
        id="revealed-entries"
        class="flex flex-col gap-5"
      >
        <article
          :for={entry <- @entries}
          id={"telephone-entry-#{entry.id}"}
          data-current={to_string(current_entry?(entry, @current_entry))}
          data-entry-type={entry.type}
          class={[
            "mx-auto flex w-full max-w-3xl flex-col rounded-base border-2 border-border p-3 shadow-shadow",
            current_entry?(entry, @current_entry) && "telephone-reveal-current",
            entry.type == :drawing && "bg-white",
            entry.type != :drawing && "bg-yellow-50"
          ]}
        >
          <%= if entry.type == :drawing do %>
            <div class="mb-1 flex items-center gap-2">
              <.flamingo_avatar
                avatar={player_avatar(@players, entry.player_id || @chain.origin_player_id)}
                class="h-8 w-8"
                label={
                  "#{player_name(@players, entry.player_id || @chain.origin_player_id)}'s avatar"
                }
              />
              <div>
                <p class="font-bold">
                  {player_name(@players, entry.player_id || @chain.origin_player_id)}
                </p>
              </div>
            </div>
            <div
              id={"reveal-drawing-#{entry.id}"}
              phx-hook="DrawingCanvas"
              phx-update="ignore"
              data-is-drawer="false"
              data-final-drawing-replay="true"
              data-final-drawing-events={Jason.encode!(entry.value || [])}
            >
              <div class="relative aspect-[7/5] w-full bg-white">
                <canvas width="700" height="500" class="absolute inset-0 h-full w-full"></canvas>
                <.drawing_fallback ops={entry.value || []} />
              </div>
            </div>
          <% else %>
            <div class="grid grid-cols-[1fr_auto_1fr] items-center gap-2">
              <div class="flex min-w-0 items-center gap-2 justify-self-start">
                <.flamingo_avatar
                  avatar={player_avatar(@players, entry.player_id || @chain.origin_player_id)}
                  class="h-8 w-8 shrink-0"
                  label={
                    "#{player_name(@players, entry.player_id || @chain.origin_player_id)}'s avatar"
                  }
                />
                <span class="truncate font-bold">
                  {player_name(@players, entry.player_id || @chain.origin_player_id)}
                </span>
              </div>
              <p
                id={"reveal-text-#{entry.id}"}
                class="text-center font-hero text-2xl leading-tight font-black text-black"
              >
                {present_text(entry.value)}
              </p>
              <span aria-hidden="true"></span>
            </div>
          <% end %>
          <div :if={@participation == :active} class="mt-2 flex flex-wrap justify-center gap-2">
            <button
              :for={{category, label, icon} <- applicable_categories(@categories, entry)}
              id={"vote-#{category}-#{entry.id}"}
              phx-click="vote"
              phx-value-category={category}
              phx-value-entry-id={entry.id}
              class={[
                "flex items-center gap-1 rounded-full border-2 border-border px-3 py-1.5 text-xs font-bold transition hover:bg-yellow-100",
                Map.get(@votes, category) == entry.id && "bg-yellow-200 shadow-shadow"
              ]}
            >
              <.icon name={icon} class="h-4 w-4" />{label}<span class="rounded-full bg-white px-1.5">{vote_count(@vote_counts, category, entry.id)}</span>
            </button>
          </div>
        </article>
      </div>
      <div id="reveal-controls" class="flex justify-center">
        <.button
          :if={@viewer_id == @host_id}
          id="advance-telephone-reveal"
          phx-click="advance_reveal"
          class="inline-flex items-center gap-1"
        >
          <%= if final_reveal?(@reveal) do %>
            Finish
          <% else %>
            Next <.icon name={:arrow_down} class="h-4 w-4" />
          <% end %>
        </.button>
        <p :if={@viewer_id != @host_id} id="waiting-for-reveal-host" class="font-bold text-gray-600">
          The host is choosing the dramatic moment… hold your breath.
        </p>
      </div>
    </section>
    """
  end

  attr :awards, :map, required: true
  attr :players, :map, required: true
  attr :host?, :boolean, required: true

  def awards_phase(assigns) do
    assigns = assign(assigns, categories: @categories)

    ~H"""
    <section id="telephone-awards" class="relative space-y-7 overflow-hidden pb-8 text-center">
      <div aria-hidden="true" class="pointer-events-none absolute inset-0">
        <.icon
          name={:sparkles}
          class="telephone-float absolute top-6 left-[4%] h-16 w-16 -rotate-12 text-yellow-500"
        />
        <.icon
          name={:sparkles}
          class="telephone-float absolute top-24 right-[3%] h-20 w-20 rotate-12 text-pink-500 [animation-delay:500ms]"
        />
      </div>
      <div id="telephone-finale-banner" class="relative">
        <.box class="bg-purple-600 p-7 text-white sm:p-10">
          <div class="relative">
            <p class="font-hero text-sm font-black tracking-[0.35em] text-yellow-200 uppercase">
              Every chain survived
            </p>
            <h2 class="mt-2 font-hero text-5xl font-black sm:text-7xl">Telephone legends!</h2>
            <p class="mx-auto mt-3 max-w-2xl text-lg font-bold text-purple-50 sm:text-xl">
              {@players |> map_size()} players turned simple prompts into absolute nonsense. Time to
              celebrate the links nobody saw coming.
            </p>
          </div>
        </.box>
      </div>
      <div id="telephone-award-cards" class="relative grid gap-5 md:grid-cols-3">
        <.box
          :for={{category, label, icon} <- @categories}
          class={[
            "telephone-award-card p-6 transition hover:-translate-y-2",
            award_card_class(category)
          ]}
        >
          <div class="mx-auto flex h-16 w-16 rotate-3 items-center justify-center rounded-full border-2 border-border bg-white shadow-shadow">
            <.icon name={icon} class="h-9 w-9 text-purple-700" />
          </div>
          <p class="mt-5 text-xs font-black tracking-[0.2em] text-purple-700 uppercase">
            The award for
          </p>
          <h3 class="mt-1 font-hero text-2xl font-black">{label}</h3>
          <%= if award = Map.get(@awards, category) do %>
            <.flamingo_avatar
              avatar={player_avatar(@players, award.player_id)}
              class="mx-auto mt-5 h-24 w-24"
              label={"#{player_name(@players, award.player_id)}'s avatar"}
            />
            <p class="mt-2 text-2xl font-black">{player_name(@players, award.player_id)}</p>
            <p class="mt-2 border-y-2 border-border/20 py-3 font-hero text-lg font-black text-pink-700">
              {award_summary(award)}
            </p>
            <p class="mt-3 text-sm font-bold text-gray-600">
              {award.votes} {if(award.votes == 1, do: "vote", else: "votes")}
            </p>
          <% else %>
            <p class="mt-8 text-gray-600">No votes this time—chaos made winners of everyone.</p>
          <% end %>
        </.box>
      </div>
      <div class="relative flex flex-wrap justify-center gap-3 border-2 border-border bg-white p-5 shadow-shadow">
        <.button
          :if={@host?}
          id="telephone-play-again"
          phx-click="play_again"
          class="px-7 py-3 font-black"
        >
          <.icon name={:rotate_cw} class="mr-2 h-5 w-5" />Play again
        </.button>
        <.button
          id="telephone-new-room"
          navigate={~p"/"}
          variant="neutral"
          class="px-7 py-3 font-black"
        >
          New room
        </.button>
      </div>
    </section>
    """
  end

  attr :ops, :list, required: true

  def drawing_fallback(assigns) do
    assigns = assign(assigns, :marks, svg_marks(assigns.ops))

    ~H"""
    <svg
      :if={@marks != []}
      class="pointer-events-none absolute inset-0 z-10 h-full w-full"
      viewBox="0 0 700 500"
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <%= for mark <- @marks do %>
        <polyline
          :if={mark.type == :stroke}
          points={mark.points}
          fill="none"
          stroke={mark.color}
          stroke-width={mark.width}
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <circle
          :if={mark.type == :dot}
          cx={mark.x}
          cy={mark.y}
          r={mark.width / 2}
          fill={mark.color}
        />
      <% end %>
    </svg>
    """
  end

  defp source_text(nil), do: "No prompt was provided"
  defp source_text(%{source: source}), do: present_text(source && source.value)
  defp source_text(_), do: "No prompt was provided"
  defp drawing_json(%{source: %{value: value}}), do: Jason.encode!(value || [])
  defp drawing_json(_), do: "[]"
  defp drawing_ops(%{source: %{value: value}}) when is_list(value), do: value
  defp drawing_ops(_), do: []

  defp svg_marks(ops) do
    Enum.reduce(ops, [], fn
      ["c"], _marks ->
        []

      ["p", color, width, coordinates], marks
      when is_binary(color) and is_number(width) and is_list(coordinates) ->
        case svg_points(coordinates) do
          [{x, y}] ->
            marks ++ [%{type: :dot, x: x, y: y, color: color, width: width}]

          points when points != [] ->
            encoded = Enum.map_join(points, " ", fn {x, y} -> "#{x},#{y}" end)
            marks ++ [%{type: :stroke, points: encoded, color: color, width: width}]

          [] ->
            marks
        end

      _op, marks ->
        marks
    end)
  end

  defp svg_points([x, y | deltas]) when is_number(x) and is_number(y) do
    {points, _last} =
      deltas
      |> Enum.chunk_every(2)
      |> Enum.map_reduce({x, y}, fn
        [dx, dy], {previous_x, previous_y} when is_number(dx) and is_number(dy) ->
          point = {previous_x + dx, previous_y + dy}
          {point, point}

        _invalid, previous ->
          {previous, previous}
      end)

    [{x, y} | points]
  end

  defp svg_points(_coordinates), do: []

  defp present_text(value) when is_binary(value),
    do: if(String.trim(value) == "", do: "A mysterious blank link", else: value)

  defp present_text(_), do: "A mysterious blank link"
  defp progress_indices(count) when count > 0, do: 0..(count - 1)
  defp progress_indices(_count), do: []

  defp progress_state(index, current) when index < current, do: "complete"
  defp progress_state(index, index), do: "current"
  defp progress_state(_index, _current), do: "upcoming"

  defp journey_label(0), do: "Prompt"
  defp journey_label(index) when rem(index, 2) == 1, do: "Drawing"
  defp journey_label(_index), do: "Guess"

  defp progress_class(index, current) when index < current, do: "border-solid bg-white"
  defp progress_class(index, index), do: "border-solid bg-pink-400"
  defp progress_class(_index, _current), do: "border-dotted bg-transparent"

  defp current_entry?(%{id: id}, %{id: id}), do: true
  defp current_entry?(_entry, _current), do: false

  defp final_reveal?(reveal) do
    reveal.entry_index + 1 == reveal.entry_count and
      reveal.chain_index + 1 == reveal.chain_count
  end

  defp award_card_class(:derailment), do: "bg-purple-100"
  defp award_card_class(:best_save), do: "bg-green-100"
  defp award_card_class(:worst_drawing), do: "bg-yellow-100"

  defp award_summary(%{entry: %{type: :guess, value: value}}), do: "“#{present_text(value)}”"
  defp award_summary(%{entry: %{type: :drawing}}), do: "A masterpiece beyond words"
  defp award_summary(_award), do: "An unforgettable link"

  defp applicable_categories(categories, %{type: :drawing}), do: categories
  defp applicable_categories(_categories, %{type: :prompt}), do: []

  defp applicable_categories(categories, _entry),
    do: Enum.reject(categories, &(elem(&1, 0) == :worst_drawing))

  defp vote_count(counts, category, entry_id),
    do: counts |> Map.get(category, %{}) |> Map.get(entry_id, 0)

  defp player(players, id), do: Map.get(players, id, %{})
  defp player_name(_players, nil), do: "an unknown player"
  defp player_name(players, id), do: Map.get(player(players, id), :name, "Unknown player")
  defp player_avatar(players, id), do: Map.get(player(players, id), :avatar, %{})
end
