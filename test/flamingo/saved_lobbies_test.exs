defmodule Flamingo.SavedLobbiesTest do
  use Flamingo.DataCase, async: true

  import Flamingo.AccountsFixtures

  alias Flamingo.{Rooms, RoomSupervisor, SavedLobbies}
  alias Flamingo.SavedLobbies.SavedLobby

  defp unique_name, do: "crew-#{System.unique_integer([:positive])}"

  defp start_room do
    room_id = "saved-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    room_id
  end

  defp join_connected(room_id, name) do
    {:ok, token, _} = Rooms.join(room_id, name)
    {:ok, snapshot} = Rooms.connect(room_id, token)
    snapshot
  end

  # Holds a connected seat in another process until the test ends.
  defp join_elsewhere(room_id, name) do
    parent = self()

    pid =
      start_supervised!(
        Supervisor.child_spec(
          {Task,
           fn ->
             send(parent, {:joined, join_connected(room_id, name)})

             receive do
               {:leave, caller} -> send(caller, {:left, Rooms.leave(room_id)})
             end
           end},
          id: {:player, name}
        )
      )

    assert_receive {:joined, snapshot}
    Process.put({:player, name}, pid)
    snapshot
  end

  defp leave_elsewhere(name) do
    send(Process.get({:player, name}), {:leave, self()})
    assert_receive {:left, :ok}
  end

  describe "names" do
    test "are normalized into link-safe ids" do
      changeset = SavedLobbies.change_saved_lobby(%{name: "  Thursday   Crew "})
      assert Ecto.Changeset.get_change(changeset, :name) == "thursday-crew"
      assert changeset.valid?
    end

    test "reject characters, lengths and hyphens that do not make clean links" do
      for name <- ["ab", String.duplicate("a", 31), "crew!", "crew--two", "-crew", "crew-"] do
        refute SavedLobbies.change_saved_lobby(%{name: name}).valid?, name
      end
    end

    test "are unique regardless of the case they were typed in" do
      name = unique_name()
      first = start_room()
      join_connected(first, "Alice")
      assert {:ok, _} = SavedLobbies.save_room(user_scope_fixture(), first, %{name: name})

      second = start_room()
      join_connected(second, "Bob")

      assert {:error, changeset} =
               SavedLobbies.save_room(user_scope_fixture(), second, %{name: String.upcase(name)})

      assert "is already taken" in errors_on(changeset).name
      assert {:ok, %{saved_lobby: nil}} = Rooms.snapshot(second)
    end
  end

  describe "saving a room" do
    test "records the creator and labels the running room" do
      room_id = start_room()
      join_connected(room_id, "Alice")
      scope = user_scope_fixture()
      name = unique_name()

      assert {:ok, %SavedLobby{name: ^name} = saved} =
               SavedLobbies.save_room(scope, room_id, %{name: name})

      assert saved.creator_id == scope.user.id
      assert SavedLobbies.get_saved_lobby_by_name(String.upcase(name)).id == saved.id
      assert {:ok, %{saved_lobby: ^name}} = Rooms.snapshot(room_id)
      assert Rooms.open_saved_lobby(name) == {:ok, room_id}
    end

    test "is refused for a non-host and leaves no record" do
      room_id = start_room()
      join_elsewhere(room_id, "Alice")
      join_connected(room_id, "Bob")
      name = unique_name()

      assert {:error, :not_host} =
               SavedLobbies.save_room(user_scope_fixture(), room_id, %{name: name})

      assert SavedLobbies.get_saved_lobby_by_name(name) == nil
      assert {:ok, %{saved_lobby: nil}} = Rooms.snapshot(room_id)
    end

    test "only happens once per room" do
      room_id = start_room()
      join_connected(room_id, "Alice")
      scope = user_scope_fixture()
      second = unique_name()
      assert {:ok, _} = SavedLobbies.save_room(scope, room_id, %{name: unique_name()})
      assert {:error, :already_saved} = SavedLobbies.save_room(scope, room_id, %{name: second})
      assert SavedLobbies.get_saved_lobby_by_name(second) == nil
    end

    test "survives the creator deleting their account" do
      room_id = start_room()
      join_connected(room_id, "Alice")
      scope = user_scope_fixture()
      name = unique_name()
      {:ok, _} = SavedLobbies.save_room(scope, room_id, %{name: name})
      Repo.delete!(scope.user)
      assert %SavedLobby{creator_id: nil} = SavedLobbies.get_saved_lobby_by_name(name)
    end
  end

  describe "opening a saved lobby" do
    test "starts one room and reuses it for everyone who arrives" do
      name = unique_name()

      room_ids =
        1..8
        |> Task.async_stream(fn _ -> Rooms.open_saved_lobby(name) end, timeout: :infinity)
        |> Enum.map(fn {:ok, {:ok, room_id}} -> room_id end)
        |> Enum.uniq()

      assert [room_id] = room_ids
      assert %{saved_lobby: ^name} = join_connected(room_id, "Alice")
    end

    test "makes the first arrival the host" do
      {:ok, room_id} = Rooms.open_saved_lobby(unique_name())
      first = join_elsewhere(room_id, "Alice")
      second = join_connected(room_id, "Bob")
      assert first.host_id == first.viewer_id
      assert second.host_id == first.viewer_id
    end

    test "opens a fresh lobby after everyone leaves a game" do
      room_id = start_room()
      %{viewer_id: alice} = join_connected(room_id, "Alice")
      name = unique_name()
      {:ok, _} = SavedLobbies.save_room(user_scope_fixture(), room_id, %{name: name})
      join_elsewhere(room_id, "Bob")
      assert :ok = Rooms.start_game(room_id, %{game_mode: :scribble})

      :ok = Rooms.leave(room_id)
      leave_elsewhere("Bob")

      assert {:ok, ^room_id} = Rooms.open_saved_lobby(name)
      assert {:ok, _token, snapshot} = Rooms.join(room_id, "Carol")
      assert snapshot.phase == :lobby
      assert snapshot.host_id == snapshot.viewer_id
      refute alice in snapshot.player_order
    end

    test "lets late arrivals join a running game" do
      room_id = start_room()
      join_connected(room_id, "Alice")
      name = unique_name()
      {:ok, _} = SavedLobbies.save_room(user_scope_fixture(), room_id, %{name: name})
      join_elsewhere(room_id, "Bob")
      assert :ok = Rooms.start_game(room_id, %{game_mode: :scribble})

      assert {:ok, ^room_id} = Rooms.open_saved_lobby(name)
      assert {:ok, _token, snapshot} = Rooms.join(room_id, "Carol")
      assert snapshot.phase != :lobby
    end
  end
end
