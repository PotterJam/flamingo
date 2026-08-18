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
       word_list: :default,
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
        <div class={[
          "mx-auto flex w-full max-w-6xl flex-col",
          if(@phase in [:telephone_prompt, :telephone_draw], do: "gap-0", else: "gap-4")
        ]}>
          <header id="telephone-header" class="relative h-0">
            <div
              :if={@phase == :telephone_guess}
              class="absolute top-0 right-0 z-10 flex items-center gap-3"
            >
              <.game_progress
                id="telephone-step-progress"
                label="Step"
                current={if(is_integer(@current_step), do: @current_step + 1, else: 1)}
                total={max(@step_count, 1)}
                position_class=""
              />
              <.starburst_timer
                position_class=""
                timer_id="telephone-timer"
                end_time={iso_time(@turn_end_time)}
                fill="#fde047"
                stroke="#111827"
                stroke_width="4"
              />
            </div>
          </header>

          <%= case @phase do %>
            <% :telephone_prompt -> %>
              <TelephoneComponents.prompt_phase
                choices={@prompt_choices}
                submitted={submitted?(assigns)}
                form={@prompt_form}
                end_time={iso_time(@turn_end_time)}
              />
            <% :telephone_draw -> %>
              <TelephoneComponents.draw_phase
                assignment={@assignment}
                current_step={if(is_integer(@current_step), do: @current_step + 1, else: 1)}
                step_count={max(@step_count, 1)}
                end_time={iso_time(@turn_end_time)}
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
    </Layouts.app>
    """
  end

  def handle_event("draw_event", event, socket) do
    Rooms.draw_event(socket.assigns.room_id, event)
    {:noreply, socket}
  end

  def handle_event("select_prompt", %{"choice" => prompt}, socket),
    do: command(socket, {:select_prompt, prompt})

  def handle_event("select_prompt", %{"prompt" => prompt}, socket),
    do: command(socket, {:select_prompt, prompt})

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
      word_list: socket.assigns.word_list,
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
    initial? = is_nil(socket.assigns.viewer_id)
    old_phase = socket.assigns.phase
    old_reveal_position = reveal_position(socket.assigns.reveal)
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
        word_list: snapshot.word_list,
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

    socket =
      push_event(socket, "set_timer", %{
        end_time: iso_time(Map.get(snapshot, :turn_end_time))
      })

    socket =
      if initial? or old_phase != snapshot.phase, do: sync_round_audio(socket), else: socket

    if old_phase == :telephone_reveal and snapshot.phase == :telephone_reveal and
         old_reveal_position != reveal_position(snapshot.reveal),
       do: push_event(socket, "scroll_telephone_reveal", %{}),
       else: socket
  end

  defp submitted?(assigns), do: MapSet.member?(assigns.submitted_ids, assigns.viewer_id)

  defp sync_round_audio(socket) do
    push_event(socket, "sync_round_audio", %{
      phase: Atom.to_string(socket.assigns.phase),
      end_time: iso_time(socket.assigns.turn_end_time)
    })
  end

  defp reveal_position(%{chain_index: chain_index, entry_index: entry_index}),
    do: {chain_index, entry_index}

  defp reveal_position(_reveal), do: nil
  defp iso_time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso_time(value) when is_binary(value), do: value
  defp iso_time(_), do: nil
  defp command_error(:invalid_prompt), do: "Choose a prompt or write one of your own."
  defp command_error(:prompt_taken), do: "That prompt is already in this game. Try another one."
  defp command_error(:invalid_guess), do: "Add a guess between 1 and 100 characters."
  defp command_error(:already_submitted), do: "You already sent this link."
  defp command_error(:not_host), do: "Only the host can do that."
  defp command_error(reason), do: "That didn't work (#{reason}). Please try again."
end
