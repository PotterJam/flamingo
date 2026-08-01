defmodule Flamingo.Room.MembersTest do
  use ExUnit.Case, async: true

  alias Flamingo.Room.Members

  test "members preserve room order and assign the first seat as host" do
    members = members_fixture()

    assert Members.ordered_ids(members) == ["alice", "bob"]
    assert Members.host_id(members) == "alice"
    assert {:ok, "alice"} = Members.resolve(members, "alice-token")
    assert {:ok, "bob"} = Members.resolve(members, "bob-token")
  end

  test "removing a non-host preserves the host" do
    members = members_fixture()

    assert {:ok, members, %{id: "bob", name: "Bob"}} = Members.remove(members, "bob")
    assert Members.ordered_ids(members) == ["alice"]
    assert Members.host_id(members) == "alice"
    assert :error = Members.resolve(members, "bob-token")
  end

  test "removing the host promotes the first remaining seat" do
    members = members_fixture()

    assert {:ok, members, %{id: "alice", name: "Alice"}} =
             Members.remove(members, "alice")

    assert Members.ordered_ids(members) == ["bob"]
    assert Members.host_id(members) == "bob"

    assert {:ok, members, %{id: "bob"}} = Members.remove(members, "bob")
    assert Members.ordered_ids(members) == []
    assert Members.host_id(members) == nil
  end

  test "duplicate seat IDs and resume tokens are rejected" do
    {:ok, members} = Members.add(Members.new(), "alice", "alice-token", "Alice")

    assert {:error, :duplicate_seat} =
             Members.add(members, "alice", "other-token", "Other Alice")

    assert {:error, :duplicate_resume_token} =
             Members.add(members, "bob", "alice-token", "Bob")
  end

  test "connection counts report only semantic status transitions" do
    {:ok, members} = Members.add(Members.new(), "alice", "alice-token", "Alice")

    refute Members.online?(members, "alice")
    assert Members.online_count(members) == 0

    assert {:ok, members, :became_online} = Members.connection_added(members, "alice")
    assert Members.online?(members, "alice")
    assert Members.online_count(members) == 1

    assert {:ok, members, :unchanged} = Members.connection_added(members, "alice")
    assert {:ok, members, :unchanged} = Members.connection_removed(members, "alice")
    assert Members.online?(members, "alice")

    assert {:ok, members, :became_offline} = Members.connection_removed(members, "alice")
    refute Members.online?(members, "alice")
    assert Members.online_count(members) == 0
    assert {:error, :already_offline} = Members.connection_removed(members, "alice")
    assert :error = Members.connection_added(members, "missing")
  end

  test "snapshots omit resume tokens and connection counts" do
    members = members_fixture()
    {:ok, members, :became_online} = Members.connection_added(members, "alice")

    assert %{
             players: %{
               "alice" => %{id: "alice", name: "Alice", connected: true},
               "bob" => %{id: "bob", name: "Bob", connected: false}
             },
             player_order: ["alice", "bob"],
             host_id: "alice"
           } = Members.snapshot(members)
  end

  defp members_fixture do
    {:ok, members} = Members.add(Members.new(), "alice", "alice-token", "Alice")
    {:ok, members} = Members.add(members, "bob", "bob-token", "Bob")
    members
  end
end
