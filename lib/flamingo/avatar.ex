defmodule Flamingo.Avatar do
  @moduledoc """
  Defines the interchangeable parts used to build a player's flamingo avatar.
  """

  @traits %{
    "body" => 0..5,
    "neck" => 0..4,
    "beak" => 0..4,
    "eyes" => 0..4,
    "tuft" => 0..4,
    "accessory" => 0..5
  }

  @trait_atoms %{
    "body" => :body,
    "neck" => :neck,
    "beak" => :beak,
    "eyes" => :eyes,
    "tuft" => :tuft,
    "accessory" => :accessory
  }

  @default %{
    "body" => 0,
    "neck" => 0,
    "beak" => 2,
    "eyes" => 2,
    "tuft" => 1,
    "accessory" => 0
  }

  @labels %{
    "neck" => ~w(classic swoop straight zigzag pretzel),
    "beak" => ~w(tiny petite classic grand absurd),
    "eyes" => ~w(close cozy classic wide bewildered),
    "tuft" => ~w(smooth flick fluffy punk chaos),
    "accessory" => ["none", "crown", "bow", "beret", "glasses", "flower"]
  }

  def default, do: @default

  def normalize(avatar) when is_map(avatar) do
    Map.new(@traits, fn {trait, range} ->
      value = Map.get(avatar, trait, Map.get(avatar, Map.fetch!(@trait_atoms, trait)))
      {trait, normalize_value(value, Map.fetch!(@default, trait), range)}
    end)
  end

  def normalize(_avatar), do: @default

  def random do
    Map.new(@traits, fn {trait, range} ->
      {trait, Enum.random(range)}
    end)
  end

  def label(trait, value) do
    @labels
    |> Map.fetch!(trait)
    |> Enum.at(normalize_value(value, Map.fetch!(@default, trait), Map.fetch!(@traits, trait)))
  end

  def max(trait), do: @traits |> Map.fetch!(trait) |> Enum.max()

  defp normalize_value(value, default, range) when is_integer(value) do
    if value in range, do: value, else: default
  end

  defp normalize_value(value, default, range) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> normalize_value(number, default, range)
      _ -> default
    end
  end

  defp normalize_value(_value, default, _range), do: default
end
