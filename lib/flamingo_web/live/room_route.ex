defmodule FlamingoWeb.RoomRoute do
  use FlamingoWeb, :verified_routes

  alias Flamingo.Rooms
  alias FlamingoWeb.GameModes

  @doc """
  Applies the snapshot with `apply` when it belongs to the calling LiveView,
  otherwise navigates to the screen that owns it.
  """
  def route(socket, snapshot, apply) do
    if screen(snapshot) == socket.view,
      do: apply.(socket, snapshot),
      else: navigate(socket, snapshot)
  end

  def navigate(socket, snapshot) do
    room_id = socket.assigns.room_id
    token = socket.assigns.resume_token

    Rooms.prepare_handoff(room_id)

    Phoenix.LiveView.push_navigate(socket,
      to: __MODULE__.path(snapshot, room_id, token),
      replace: true
    )
  end

  @doc """
  The LiveView that shows this snapshot. The room snapshot decides the page,
  not the URL or settings draft.
  """
  def screen(%{phase: :lobby}), do: FlamingoWeb.LobbyLive
  def screen(snapshot), do: GameModes.get(snapshot.game_mode).live_view()

  def path(%{phase: :lobby}, room_id, token), do: ~p"/game/#{room_id}?resume_token=#{token}"
  def path(snapshot, room_id, token), do: GameModes.get(snapshot.game_mode).path(room_id, token)
end
