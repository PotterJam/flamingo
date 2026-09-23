defmodule Flamingo.TestAssertionsTest do
  use ExUnit.Case, async: true

  import Flamingo.TestAssertions

  test "ignores unrelated top-level fields, including on structs" do
    assert_fields(~D[2026-09-22], %{year: 2026, month: 9})
  end

  test "a missing field does not match an expected nil" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_fields(%{}, %{word: nil})
    end
  end

  test "nested maps must match exactly" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_fields(%{votes: %{alice: :drawing}}, %{votes: %{}})
    end
  end
end
