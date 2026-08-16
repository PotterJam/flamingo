defmodule FlamingoWeb.TelephoneLive do
  use FlamingoWeb, :live_view

  alias Flamingo.Rooms
  alias FlamingoWeb.TelephoneComponents

  def mount(%{"room_id" => room_id}, _session, socket) do
    {:ok,
     assign(socket,
       room_id: room_id,
       resume_token: nil,
       viewer_id: nil,
       participation: :spectator,
       phase: :telephone_draw,
       players: %{},
       player_order: [],
       host_id: nil,
       turn_length: 30,
       current_step: nil,
       step_count: 0,
       submitted_ids: MapSet.new(),
       prompt_choices: [],
       assignment: nil,
       reveal: nil,
       votes: %{},
       vote_counts: %{},
       awards: %{},
       custom_words: [],
       include_default_words: false,
       turn_end_time: nil,
       drawing_key: nil,
       prompt_form: to_form(%{"prompt" => ""}),
       guess_form: to_form(%{"text" => ""}, as: :guess)
     )}
  end

  def handle_params(%{"resume_token" => token}, _uri, socket) do
    if connected?(socket) do
      case Rooms.connect(socket.assigns.room_id, token) do
        {:ok, %{mode: :telephone} = snapshot} ->
          {:noreply, socket |> assign(:resume_token, token) |> apply_snapshot(snapshot)}

        {:ok, _snapshot} ->
          {:noreply,
           push_navigate(socket, to: "/game/#{socket.assigns.room_id}?resume_token=#{token}")}

        {:error, _reason} ->
          {:noreply, push_navigate(socket, to: ~p"/")}
      end
    else
      {:noreply, assign(socket, :resume_token, token)}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/")}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} background="">
      <.flamingo_background game_mode={:telephone} />
      <main id="telephone-game" class="min-h-screen px-3 py-5 sm:px-6 lg:px-8">
        <div class="mx-auto flex w-full max-w-6xl flex-col gap-4">
          <header id="telephone-header" class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p class="font-hero text-sm font-black tracking-widest text-purple-600 uppercase">
                Telephone
              </p>
              <h1 class="text-2xl font-black sm:text-3xl">Draw it. Guess it. Watch it unravel.</h1>
            </div>
            <div
              :if={@phase in [:telephone_prompt, :telephone_draw, :telephone_guess]}
              class="flex items-center gap-3"
            >
              <span
                :if={@phase in [:telephone_draw, :telephone_guess]}
                id="telephone-step-progress"
                class="rounded-full border-2 border-border bg-white px-4 py-2 font-bold shadow-shadow"
              >
                Step {if(is_integer(@current_step), do: @current_step + 1, else: "–")} of {max(
                  @step_count,
                  1
                )}
              </span>
              <span
                id="telephone-timer"
                phx-hook=".TelephoneTimer"
                phx-update="ignore"
                data-end-time={iso_time(@turn_end_time)}
                class="min-w-16 rounded-full border-2 border-border bg-yellow-200 px-4 py-2 text-center font-hero text-xl font-black tabular-nums shadow-shadow"
              >
                --
              </span>
            </div>
          </header>

          <%= case @phase do %>
            <% :telephone_prompt -> %>
              <TelephoneComponents.prompt_phase
                choices={@prompt_choices}
                submitted={submitted?(assigns)}
                form={@prompt_form}
              />
            <% :telephone_draw -> %>
              <TelephoneComponents.draw_phase
                assignment={@assignment}
                submitted={submitted?(assigns)}
              />
            <% :telephone_guess -> %>
              <TelephoneComponents.guess_phase
                assignment={@assignment}
                submitted={submitted?(assigns)}
                form={@guess_form}
              />
            <% :telephone_return -> %>
              <TelephoneComponents.return_phase
                assignment={@assignment}
                players={@players}
                viewer_id={@viewer_id}
                host_id={@host_id}
              />
            <% :telephone_reveal -> %>
              <TelephoneComponents.reveal_phase
                reveal={@reveal}
                players={@players}
                viewer_id={@viewer_id}
                host_id={@host_id}
                participation={@participation}
                votes={@votes}
                vote_counts={@vote_counts}
              />
            <% :game_ended -> %>
              <TelephoneComponents.awards_phase
                awards={@awards}
                players={@players}
                host?={@viewer_id == @host_id}
              />
            <% _ -> %>
              <.box class="bg-white p-10 text-center">
                <p id="telephone-loading" class="text-xl font-bold">Getting the next link ready…</p>
              </.box>
          <% end %>
        </div>
      </main>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".TelephoneTimer">
        export default {
          mounted() {
            this.run = (endTime) => {
              this.token = (this.token || 0) + 1
              const token = this.token
              const end = endTime ? new Date(endTime).getTime() : NaN
              const tick = () => {
                if (token !== this.token) return
                const seconds = Number.isFinite(end) ? Math.max(0, Math.ceil((end - Date.now()) / 1000)) : 0
                this.el.textContent = Number.isFinite(end) ? String(seconds).padStart(2, "0") : "--"
                if (seconds > 0) requestAnimationFrame(tick)
              }
              tick()
            }
            this.run(this.el.dataset.endTime)
            this.handleEvent("set_telephone_timer", ({end_time}) => this.run(end_time))
          },
          destroyed() { this.token = (this.token || 0) + 1 }
        }
      </script>
    </Layouts.app>
    """
  end

  def handle_event("draw_event", event, socket) do
    Rooms.draw_event(socket.assigns.room_id, event)
    {:noreply, socket}
  end

  def handle_event("select_prompt", %{"prompt" => prompt}, socket),
    do: command(socket, {:select_prompt, prompt})

  def handle_event("submit_drawing", _params, socket), do: command(socket, :submit_drawing)

  def handle_event("submit_guess", %{"guess" => %{"text" => text}}, socket) do
    command(socket, {:submit_guess, text}, reset_form?: true)
  end

  def handle_event("start_reveal", _params, socket), do: command(socket, :start_reveal)

  def handle_event("advance_reveal", _params, socket), do: command(socket, :advance_reveal)

  def handle_event("vote", %{"category" => category, "entry-id" => entry_id}, socket) do
    category =
      Enum.find([:derailment, :best_save, :worst_drawing], &(Atom.to_string(&1) == category))

    if category, do: command(socket, {:vote, category, entry_id}), else: {:noreply, socket}
  end

  def handle_event("play_again", _params, socket) do
    settings = %{
      game_mode: :telephone,
      turn_length: socket.assigns.turn_length,
      custom_words: socket.assigns.custom_words,
      include_default_words: socket.assigns.include_default_words
    }

    result(socket, Rooms.start_game(socket.assigns.room_id, settings))
  end

  def handle_info({:room_snapshot, %{mode: :telephone} = snapshot}, socket),
    do: {:noreply, apply_snapshot(socket, snapshot)}

  def handle_info({:draw_event, %{actor_id: actor_id, event: event}}, socket) do
    if actor_id == socket.assigns.viewer_id,
      do: {:noreply, push_event(socket, "draw_event", event)},
      else: {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp command(socket, command, opts \\ []) do
    case Rooms.command(socket.assigns.room_id, command) do
      :ok ->
        socket =
          if opts[:reset_form?],
            do: assign(socket, :guess_form, to_form(%{"text" => ""}, as: :guess)),
            else: socket

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, command_error(reason))}

      other ->
        result(socket, other)
    end
  end

  defp result(socket, :ok), do: {:noreply, socket}

  defp result(socket, {:error, reason}),
    do: {:noreply, put_flash(socket, :error, command_error(reason))}

  defp result(socket, _), do: {:noreply, socket}

  defp apply_snapshot(socket, snapshot) do
    assignment = Map.get(snapshot, :assignment)
    key = assignment && {Map.get(snapshot, :current_step), assignment.chain_id}
    baseline? = key != socket.assigns.drawing_key and Map.get(snapshot, :phase) == :telephone_draw

    socket =
      assign(socket,
        viewer_id: snapshot.viewer_id,
        participation: snapshot.participation,
        phase: snapshot.phase,
        players: snapshot.players,
        player_order: snapshot.player_order,
        host_id: snapshot.host_id,
        turn_length: snapshot.turn_length,
        current_step: snapshot.current_step,
        step_count: snapshot.step_count,
        submitted_ids: snapshot.submitted_ids,
        prompt_choices: Map.get(snapshot, :prompt_choices, []),
        assignment: assignment,
        reveal: snapshot.reveal,
        votes: snapshot.votes,
        vote_counts: snapshot.vote_counts,
        awards: snapshot.awards,
        custom_words: snapshot.custom_words,
        include_default_words: snapshot.include_default_words,
        turn_end_time: Map.get(snapshot, :turn_end_time),
        drawing_key: key
      )

    socket =
      if baseline?,
        do:
          push_event(socket, "drawing_state", %{events: Map.get(assignment, :current_drawing, [])}),
        else: socket

    push_event(socket, "set_telephone_timer", %{
      end_time: iso_time(Map.get(snapshot, :turn_end_time))
    })
  end

  defp submitted?(assigns), do: MapSet.member?(assigns.submitted_ids, assigns.viewer_id)
  defp iso_time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso_time(value) when is_binary(value), do: value
  defp iso_time(_), do: nil
  defp command_error(:invalid_prompt), do: "Choose a prompt or write one of your own."
  defp command_error(:prompt_taken), do: "That prompt is already in this game. Try another one."
  defp command_error(:invalid_guess), do: "Add a guess between 1 and 100 characters."
  defp command_error(:already_submitted), do: "You already sent this link."
  defp command_error(:not_host), do: "Only the host can do that."
  defp command_error(:cannot_submit), do: "That drawing can no longer be submitted."
  defp command_error(reason), do: "That didn't work (#{reason}). Please try again."
end
