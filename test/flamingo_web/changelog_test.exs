defmodule FlamingoWeb.ChangelogTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "release data has unique descending dates and supported, nonempty entries" do
    releases = "priv/changelog.json" |> File.read!() |> Jason.decode!()
    dates = Enum.map(releases, &Date.from_iso8601!(&1["date"]))

    assert dates != []
    assert dates == Enum.sort(Enum.uniq(dates), {:desc, Date})

    for release <- releases do
      assert release["entries"] != []

      for entry <- release["entries"] do
        assert entry["type"] in ["feature", "fix", "new_mode"]
        assert is_binary(entry["text"])
        assert String.trim(entry["text"]) != ""
      end
    end
  end

  test "groups entries under their dates and renders each classification beside escaped text" do
    releases = [
      %{
        "date" => "2026-09-07",
        "entries" => [
          %{"type" => "new_mode", "text" => "Telephone <remix>"},
          %{"type" => "fix", "text" => "Keep players connected."}
        ]
      },
      %{
        "date" => "2026-08-18",
        "entries" => [%{"type" => "feature", "text" => "Draw an avatar."}]
      }
    ]

    document =
      render_component(&FlamingoWeb.Changelog.feed/1, releases: releases)
      |> LazyHTML.from_fragment()

    groups = LazyHTML.query(document, "#changelog-releases > section") |> Enum.to_list()
    assert length(groups) == 2
    [newer, older] = groups

    assert newer |> LazyHTML.query("time") |> LazyHTML.text() |> String.trim() ==
             "7 September 2026"

    assert older |> LazyHTML.query("time") |> LazyHTML.text() |> String.trim() == "18 August 2026"

    assert newer |> LazyHTML.query("li:first-child span") |> LazyHTML.text() |> String.trim() ==
             "Game"

    assert newer |> LazyHTML.query("li:first-child p") |> LazyHTML.text() == "Telephone <remix>"

    assert newer |> LazyHTML.query("li:nth-child(2) span") |> LazyHTML.text() |> String.trim() ==
             "Fix"

    assert older |> LazyHTML.query("li span") |> LazyHTML.text() |> String.trim() == "New"
    assert Enum.empty?(LazyHTML.query(document, "remix"))
  end
end
