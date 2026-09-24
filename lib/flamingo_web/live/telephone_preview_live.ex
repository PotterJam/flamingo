defmodule FlamingoWeb.TelephonePreviewLive do
  # Local review fixture; remove before shipping.
  use FlamingoWeb, :live_view

  alias FlamingoWeb.TelephoneLive

  def mount(_params, session, socket) do
    {:ok, socket} = TelephoneLive.mount(%{"room_id" => "telephone-preview"}, session, socket)

    players =
      [{"alice", "Alice"}, {"bob", "Bob"}, {"charlie", "Charlie"}, {"you", "You"}]
      |> Enum.with_index()
      |> Map.new(fn {{id, name}, index} ->
        avatar =
          Flamingo.Avatar.normalize(%{
            "head" => index,
            "body" => rem(index + 1, 5),
            "legs" => index,
            "feet" => rem(index + 2, 5),
            "head_color" => index,
            "body_color" => index + 2
          })

        {id, %{id: id, name: name, avatar: avatar, connected: true}}
      end)

    duck = %{
      type: :drawing,
      player_id: "charlie",
      value: [
        ["p", "#e8a202", 12, [190, 290, 40, 65, 160, 0, 45, -65, -90, 15, -80, -25, -75, 10]],
        [
          "p",
          "#e8a202",
          12,
          [355, 300, 0, -110, 30, -40, 50, 5, 20, 40, -30, 40, -35, -5, 0, 65]
        ],
        ["p", "#ff7700", 10, [455, 195, 55, 20, -65, 10]],
        ["p", "#000000", 12, [425, 185]],
        ["p", "#02569e", 6, [150, 390, 90, 8, 90, -8, 90, 8, 90, -8]],
        ["f", "#FFE404", 300, 330]
      ]
    }

    bicycle = %{
      type: :drawing,
      player_id: "you",
      value: [
        [
          "p",
          "#000000",
          7,
          [180, 360, 20, -40, 45, -10, 35, 35, -5, 45, -45, 20, -40, -20, -10, -30]
        ],
        [
          "p",
          "#000000",
          7,
          [430, 360, 20, -40, 45, -10, 35, 35, -5, 45, -45, 20, -40, -20, -10, -30]
        ],
        ["p", "#02569e", 8, [230, 360, 75, -90, 60, 90, -135, 0, 205, -80, 45, 80]],
        [
          "p",
          "#df69a7",
          12,
          [315, 240, -45, -25, 70, -30, 55, 20, -40, 35, -40, 0, 25, 45, -30, 40]
        ],
        ["p", "#df69a7", 12, [370, 200, 0, -90, 25, -25, 30, 15, -5, 25, -30, 0]],
        ["p", "#000000", 8, [418, 126, 25, 20, -25, 0]]
      ]
    }

    {:ok,
     assign(socket,
       phase: :game_ended,
       players: players,
       viewer_id: "you",
       host_id: "you",
       awards: %{
         derailment: %{
           player_id: "alice",
           entry: %{type: :guess, value: "A duck committing tax fraud"},
           drawing: duck,
           text: "A duck committing tax fraud",
           votes: 3
         },
         best_save: %{
           player_id: "bob",
           entry: %{type: :guess, value: "A flamingo riding a bicycle"},
           drawing: bicycle,
           text: "A flamingo riding a bicycle",
           votes: 2
         },
         worst_drawing: %{
           player_id: "charlie",
           entry: duck,
           drawing: duck,
           text: "A duck sailing on a pond",
           votes: 1
         }
       }
     )}
  end

  def render(assigns), do: TelephoneLive.render(assigns)

  def handle_event("return_to_lobby", _params, socket) do
    {:noreply,
     put_flash(socket, :info, "This is a fixed end-screen preview, with no active lobby.")}
  end
end
