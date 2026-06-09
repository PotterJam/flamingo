defmodule Flamingo.DeploymentTest do
  use ExUnit.Case, async: true

  test "Docker builder uses a supported Elixir version" do
    dockerfile = File.read!(Path.expand("../../Dockerfile", __DIR__))
    [_, docker_elixir_version] = Regex.run(~r/^ARG ELIXIR_VERSION=(\S+)$/m, dockerfile)
    required_elixir_version = Mix.Project.config() |> Keyword.fetch!(:elixir)

    assert Version.match?(docker_elixir_version, required_elixir_version),
           "Docker uses Elixir #{docker_elixir_version}, but mix.exs requires #{required_elixir_version}"
  end
end
