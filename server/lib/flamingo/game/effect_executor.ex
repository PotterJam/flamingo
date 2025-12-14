defmodule Flamingo.Game.EffectExecutor do
  @moduledoc """
  Interprets effects from the functional core phases into stateful actions.
  Effects are sent as messages to socket processes.
  """

  @spec execute_all(list(tuple()), map()) :: :ok
  def execute_all(effects, state) do
    Enum.each(effects, &execute(&1, state))
  end

  @spec execute(tuple(), map()) :: :ok
  def execute({:send_to, player_id, type, payload}, state) do
    case Map.get(state.players, player_id) do
      %{pid: pid} -> send(pid, {:game_message, type, payload})
      nil -> :ok
    end
  end

  def execute({:broadcast_all, type, payload}, state) do
    msg = {:game_message, type, payload}
    Enum.each(state.players, fn {_id, %{pid: pid}} -> send(pid, msg) end)
  end

  def execute({:broadcast_except, excluded_id, type, payload}, state) do
    msg = {:game_message, type, payload}

    state.players
    |> Enum.reject(fn {id, _} -> id == excluded_id end)
    |> Enum.each(fn {_, %{pid: pid}} -> send(pid, msg) end)
  end

  def execute({:broadcast_guessers, type, payload}, state) do
    msg = {:game_message, type, payload}
    drawer_id = get_in(state, [:context, :current_drawer_id])

    state.players
    |> Enum.reject(fn {id, _} -> id == drawer_id end)
    |> Enum.each(fn {_, %{pid: pid}} -> send(pid, msg) end)
  end

  def execute({:set_timeout, _ms}, _state) do
    :ok
  end
end
