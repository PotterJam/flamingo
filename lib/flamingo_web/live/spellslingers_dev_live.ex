defmodule FlamingoWeb.SpellslingersDevLive do
  # Dev-only launcher: starts a Spellslingers duel against AI wizards for testing.
  use FlamingoWeb, :live_view

  alias Flamingo.GameModes.Spellslingers
  alias Flamingo.Rooms
  alias FlamingoWeb.RoomRoute

  def mount(_params, _session, socket) do
    params = %{"name" => "Tester", "bots" => "3", "arena_map" => "random", "turn_length" => "30"}
    {:ok, assign(socket, form: to_form(params, as: :dev), room_id: nil, resume_token: nil)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} background="grid-background lobby-background-spellslingers">
      <div class="flex min-h-screen items-center justify-center px-4 py-20">
        <.card class="w-full max-w-md bg-white p-6">
          <h1 class="font-retro-display text-2xl">Spellslingers vs bots</h1>
          <p class="mt-1 text-sm text-gray-600">
            Dev only. Starts a duel against AI wizards. Friends can still join the room to watch.
          </p>
          <.form for={@form} id="dev-bots-form" phx-submit="start" class="mt-4 space-y-3">
            <.input field={@form[:name]} label="Your name" id="dev-name-input" />
            <.input
              field={@form[:bots]}
              type="select"
              label="AI wizards"
              options={Enum.map(1..5, &{"#{&1}", "#{&1}"})}
              id="dev-bots-select"
            />
            <.input
              field={@form[:arena_map]}
              type="select"
              label="Arena"
              options={[
                {"Random arena", "random"} | Enum.map(Spellslingers.maps(), fn {id, n} -> {n, id} end)
              ]}
              id="dev-map-select"
            />
            <.input
              field={@form[:turn_length]}
              type="number"
              label="Turn length (s)"
              min="15"
              max="120"
              id="dev-turn-length-input"
            />
            <.button type="submit" class="w-full" id="dev-start-button">Start duel</.button>
          </.form>
        </.card>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("start", %{"dev" => params}, socket) do
    name =
      params["name"]
      |> to_string()
      |> String.trim()
      |> then(&if(&1 == "", do: "Tester", else: &1))

    settings = %{
      bots: parse(params["bots"], 3),
      arena_map: params["arena_map"] || "random",
      turn_length: parse(params["turn_length"], 30)
    }

    mode = FlamingoWeb.GameModes.Spellslingers

    with {:ok, room_id} <- Rooms.create_room(),
         {:ok, token, _} <- Rooms.join(room_id, name, Flamingo.Avatar.random()),
         {:ok, _} <- Rooms.connect(room_id, token),
         :ok <- Rooms.start_game(room_id, mode.id(), mode.engine(), settings),
         {:ok, snapshot} <- Rooms.snapshot(room_id) do
      socket = assign(socket, room_id: room_id, resume_token: token)
      {:noreply, RoomRoute.navigate(socket, snapshot)}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Couldn't start: #{reason}")}
    end
  end

  # The room pushes snapshots once we connect; navigation already handles them.
  def handle_info({:room_snapshot, _snapshot}, socket), do: {:noreply, socket}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp parse(value, default) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      :error -> default
    end
  end
end
