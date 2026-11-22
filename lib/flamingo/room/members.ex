defmodule Flamingo.Room.Members do
  alias Flamingo.Avatar

  defstruct seats: %{}, resume_tokens: %{}, order: [], host_id: nil

  def new, do: %__MODULE__{}

  def add(
        %__MODULE__{} = members,
        seat_id,
        resume_token,
        name,
        avatar \\ Avatar.default(),
        user_id \\ nil
      ) do
    cond do
      Map.has_key?(members.seats, seat_id) ->
        {:error, :duplicate_seat}

      Map.has_key?(members.resume_tokens, resume_token) ->
        {:error, :duplicate_resume_token}

      true ->
        seat = %{
          id: seat_id,
          name: name,
          avatar: Avatar.normalize(avatar),
          user_id: user_id,
          connection_count: 0
        }

        {:ok,
         %{
           members
           | seats: Map.put(members.seats, seat_id, seat),
             resume_tokens: Map.put(members.resume_tokens, resume_token, seat_id),
             order: members.order ++ [seat_id],
             host_id: members.host_id || seat_id
         }}
    end
  end

  def resolve(%__MODULE__{} = members, resume_token) do
    Map.fetch(members.resume_tokens, resume_token)
  end

  @doc "Finds the seat and resume token an account already holds, so it never takes two seats."
  def find_by_user(%__MODULE__{}, nil), do: :error

  def find_by_user(%__MODULE__{} = members, user_id) do
    Enum.find_value(members.resume_tokens, :error, fn {token, seat_id} ->
      if members.seats[seat_id].user_id == user_id, do: {:ok, seat_id, token}
    end)
  end

  @doc "Account ids by seat, for seats held by signed-in players. Kept off snapshots."
  def user_ids(%__MODULE__{} = members) do
    for {seat_id, %{user_id: user_id}} <- members.seats,
        user_id,
        into: %{},
        do: {seat_id, user_id}
  end

  def fetch(%__MODULE__{} = members, seat_id), do: Map.fetch(members.seats, seat_id)
  def fetch!(%__MODULE__{} = members, seat_id), do: Map.fetch!(members.seats, seat_id)

  def remove(%__MODULE__{} = members, seat_id) do
    case Map.fetch(members.seats, seat_id) do
      {:ok, seat} ->
        order = List.delete(members.order, seat_id)

        host_id =
          if members.host_id == seat_id do
            Enum.find(order, fn id -> members.seats[id].connection_count > 0 end) ||
              List.first(order)
          else
            members.host_id
          end

        resume_tokens =
          Map.reject(members.resume_tokens, fn {_resume_token, id} -> id == seat_id end)

        {:ok,
         %{
           members
           | seats: Map.delete(members.seats, seat_id),
             resume_tokens: resume_tokens,
             order: order,
             host_id: host_id
         }, seat}

      :error ->
        :error
    end
  end

  def connection_added(%__MODULE__{} = members, seat_id) do
    with {:ok, seat} <- fetch(members, seat_id) do
      transition = if seat.connection_count == 0, do: :became_online, else: :unchanged
      seat = %{seat | connection_count: seat.connection_count + 1}
      {:ok, put_seat(members, seat), transition}
    end
  end

  def connection_removed(%__MODULE__{} = members, seat_id) do
    with {:ok, seat} <- fetch(members, seat_id) do
      if seat.connection_count == 0 do
        {:error, :already_offline}
      else
        connection_count = seat.connection_count - 1
        transition = if connection_count == 0, do: :became_offline, else: :unchanged
        seat = %{seat | connection_count: connection_count}
        {:ok, put_seat(members, seat), transition}
      end
    end
  end

  def host_id(%__MODULE__{} = members), do: members.host_id
  def ordered_ids(%__MODULE__{} = members), do: members.order

  def online?(%__MODULE__{} = members, seat_id) do
    case fetch(members, seat_id) do
      {:ok, seat} -> seat.connection_count > 0
      :error -> false
    end
  end

  def online_count(%__MODULE__{} = members) do
    Enum.count(members.seats, fn {_seat_id, seat} -> seat.connection_count > 0 end)
  end

  def snapshot(%__MODULE__{} = members) do
    %{
      players:
        Map.new(members.seats, fn {seat_id, seat} ->
          {seat_id,
           %{
             id: seat.id,
             name: seat.name,
             avatar: seat.avatar,
             connected: seat.connection_count > 0
           }}
        end),
      player_order: members.order,
      host_id: members.host_id
    }
  end

  defp put_seat(members, seat) do
    %{members | seats: Map.put(members.seats, seat.id, seat)}
  end
end
