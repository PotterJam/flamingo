defmodule Flamingo.Game.Message do
  @spec encode(atom(), map()) :: binary()
  def encode(type, payload) do
    %{type: atom_to_camel(type), payload: payload}
    |> ProperCase.to_camel_case()
    |> Jason.encode!()
  end

  defp atom_to_camel(atom) do
    atom
    |> Atom.to_string()
    |> ProperCase.camel_case()
  end
end
