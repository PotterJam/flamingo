defmodule FlamingoWeb.RoomRoute do
  use FlamingoWeb, :verified_routes

  alias Flamingo.Rooms

  def navigate(socket, snapshot) do
    room_id = socket.assigns.room_id
    token = socket.assigns.resume_token

    Rooms.prepare_handoff(room_id)

    Phoenix.LiveView.push_navigate(socket,
      to: __MODULE__.path(snapshot, room_id, token),
      replace: true
    )
  end

  # The room snapshot determines which page to show, not the URL or settings draft.
  def screen(%{phase: :lobby}), do: :lobby
  def screen(%{mode: :telephone}), do: :telephone
  def screen(%{mode: :scribble}), do: :scribble

  def path(snapshot, room_id, token) do
    case screen(snapshot) do
      :lobby -> ~p"/game/#{room_id}?resume_token=#{token}"
      :scribble -> ~p"/game/#{room_id}/scribble?resume_token=#{token}"
      :telephone -> ~p"/game/#{room_id}/telephone?resume_token=#{token}"
    end
  end
end
