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

  def prompt_phase(assigns) do
    ~H"""
    <section id="telephone-prompt-phase" class="mx-auto w-full max-w-4xl py-8 sm:py-16">
      <.box class="bg-white p-6 text-center sm:p-10">
        <p class="text-sm font-bold tracking-widest text-purple-600 uppercase">Start your chain</p>
        <h2 class="mt-2 text-3xl font-black sm:text-5xl">Choose what you’ll draw</h2>
        <p class="mx-auto mt-3 max-w-xl text-gray-600">
          Everyone picks privately. Your prompt starts a chain that will travel around the room.
        </p>
        <%= if @submitted do %>
          <div
            id="prompt-submitted-waiting"
            class="mt-8 rounded-base border-2 border-green-700 bg-green-100 p-6 font-bold"
          >
            <.icon name={:check_circle} class="mr-2 inline h-6 w-6" />Prompt locked in—waiting for everyone else.
          </div>
        <% else %>
          <div id="telephone-prompt-choices" class="mt-8 grid gap-3 sm:grid-cols-3">
            <.button
              :for={prompt <- @choices}
              id={"telephone-prompt-#{prompt_id(prompt)}"}
              phx-click="select_prompt"
              phx-value-prompt={prompt}
              class="min-h-20 justify-center px-5 py-4 text-lg font-black"
            >
              {prompt}
            </.button>
          </div>
        <% end %>
      </.box>
    </section>
    """
  end

  attr :assignment, :map, default: nil
  attr :submitted, :boolean, required: true

  def draw_phase(assigns) do
    assigns = assign(assigns, :palette, @palette)

    ~H"""
    <section id="telephone-draw-phase" class="grid items-start gap-4 lg:grid-cols-[1fr_18rem]">
      <div class="relative min-w-0">
        <.box class="mb-3 bg-white p-3 text-center">
          <p class="text-xs font-bold tracking-wider text-gray-500 uppercase">Your link says</p>
          <p id="draw-source-text" class="text-xl font-black sm:text-2xl">
            {source_text(@assignment)}
          </p>
        </.box>
        <div
          id="telephone-drawing-canvas"
          phx-hook="DrawingCanvas"
          phx-update="ignore"
          data-is-drawer="true"
          class="flex flex-col gap-3"
        >
          <.box class="overflow-hidden bg-white p-0">
            <canvas width="700" height="500" class="aspect-[7/5] w-full cursor-crosshair bg-white">
            </canvas>
          </.box>
          <.box class="overflow-x-auto bg-white p-0"><.drawing_toolbar palette={@palette} /></.box>
        </div>
        <div
          :if={@submitted}
          id="drawing-submitted-overlay"
          class="absolute inset-0 z-20 flex items-center justify-center rounded-base bg-white/85 p-6 text-center backdrop-blur-sm"
        >
          <div>
            <.icon name={:check_circle} class="mx-auto h-12 w-12 text-green-600" />
            <p class="mt-2 text-2xl font-black">Drawing delivered!</p>
            <p>Waiting for the other artists…</p>
          </div>
        </div>
      </div>
      <.box class="bg-pink-100 p-5 text-center lg:sticky lg:top-5">
        <.icon name={:pencil_line} class="mx-auto h-10 w-10" />
        <h2 class="mt-2 text-xl font-black">Pass the picture on</h2>
        <p class="my-4 text-sm text-gray-700">Make it recognizable—or wonderfully confusing.</p>
        <.button
          id="submit-telephone-drawing"
          phx-click="submit_drawing"
          disabled={@submitted}
          class="w-full justify-center px-6 py-3 text-lg font-black"
        >
          Done drawing
        </.button>
      </.box>
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
    assigns = assign(assigns, chain: chain, entries: entries, categories: @categories)

    ~H"""
    <section id="telephone-reveal-phase" class="space-y-5">
      <.box class="bg-purple-100 p-5 text-center">
        <p id="reveal-progress" class="text-sm font-bold tracking-wider uppercase">
          Chain {number(@reveal, :chain_index)} · Link {number(@reveal, :entry_index)}
        </p>
        <h2 class="font-hero text-3xl font-black text-purple-700 sm:text-5xl">The grand reveal</h2>
        <p class="mt-2">
          Started by <strong>{player_name(@players, @chain && @chain.origin_player_id)}</strong>
        </p>
      </.box>
      <div
        id="revealed-entries"
        class={[
          "grid gap-5",
          length(@entries) == 1 && "mx-auto w-full max-w-2xl",
          length(@entries) > 1 && "md:grid-cols-2"
        ]}
      >
        <article
          :for={entry <- @entries}
          id={"telephone-entry-#{entry.id}"}
          class="animate-in fade-in zoom-in-95 duration-500 rounded-base border-2 border-border bg-white p-4 shadow-shadow transition hover:-translate-y-1"
        >
          <div class="mb-3 flex items-center gap-2">
            <.flamingo_avatar
              avatar={player_avatar(@players, entry.player_id || @chain.origin_player_id)}
              class="h-10 w-10"
              label={
                "#{player_name(@players, entry.player_id || @chain.origin_player_id)}'s avatar"
              }
            />
            <div>
              <p class="font-bold">
                {player_name(@players, entry.player_id || @chain.origin_player_id)}
              </p>
              <p class="text-xs font-bold text-gray-500 uppercase">{entry_label(entry)}</p>
            </div>
          </div>
          <%= if entry.type == :drawing do %>
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
            <p
              id={"reveal-text-#{entry.id}"}
              class="flex min-h-36 items-center justify-center p-5 text-center font-hero text-3xl font-black text-pink-500"
            >
              {present_text(entry.value)}
            </p>
          <% end %>
          <div :if={@participation == :active} class="mt-4 flex flex-wrap gap-2">
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
      <div id="reveal-controls" class="text-center">
        <.button
          :if={@viewer_id == @host_id}
          id="advance-telephone-reveal"
          phx-click="advance_reveal"
          class="px-8 py-3 text-lg font-black"
        >
          Next reveal <.icon name={:arrow_right} class="ml-2 h-5 w-5" />
        </.button>
        <p :if={@viewer_id != @host_id} id="waiting-for-reveal-host" class="font-bold text-gray-600">
          The host is choosing the dramatic moment…
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
    <section id="telephone-awards" class="space-y-6 text-center">
      <div>
        <p class="font-hero text-lg font-black text-purple-600">FIN</p>
        <h2 class="text-4xl font-black sm:text-6xl">Telephone legends</h2>
      </div>
      <div class="grid gap-4 md:grid-cols-3">
        <.box
          :for={{category, label, icon} <- @categories}
          class="bg-white p-6 transition hover:-translate-y-1"
        >
          <.icon name={icon} class="mx-auto h-9 w-9 text-pink-500" />
          <h3 class="mt-2 text-xl font-black">{label}</h3>
          <%= if award = Map.get(@awards, category) do %>
            <.flamingo_avatar
              avatar={player_avatar(@players, award.player_id)}
              class="mx-auto mt-4 h-24 w-24"
              label={"#{player_name(@players, award.player_id)}'s avatar"}
            />
            <p class="text-2xl font-black">{player_name(@players, award.player_id)}</p>
            <p class="text-sm text-gray-600">
              {award.votes} {if(award.votes == 1, do: "vote", else: "votes")}
            </p>
          <% else %>
            <p class="mt-8 text-gray-500">No votes this time—every link is a winner.</p>
          <% end %>
        </.box>
      </div>
      <div class="flex flex-wrap justify-center gap-3">
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
  defp number(nil, _key), do: "–"

  defp number(map, key),
    do: if(is_integer(Map.get(map, key)), do: Map.get(map, key) + 1, else: "–")

  defp entry_label(%{type: :prompt}), do: "Original prompt"
  defp entry_label(%{type: :drawing}), do: "Drawing"
  defp entry_label(%{type: :guess}), do: "Guess"
  defp entry_label(_), do: "Missing link"
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
  defp prompt_id(prompt), do: Base.url_encode64(prompt, padding: false)
end
