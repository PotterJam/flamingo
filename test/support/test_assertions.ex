defmodule Flamingo.TestAssertions do
  import ExUnit.Assertions

  @doc "Compares the expected fields exactly, ignoring other top-level fields in actual."
  def assert_fields(actual, expected) do
    assert Map.take(actual, Map.keys(expected)) == expected
  end
end
