defmodule FlamingoWeb.RoomRoute do
  use FlamingoWeb, :verified_routes

  # The room snapshot, not the URL or the host's settings draft, owns the screen.
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
