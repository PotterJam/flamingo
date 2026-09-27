defmodule FlamingoWeb.Changelog do
  use FlamingoWeb, :html

  @external_resource Path.expand("../../../priv/changelog.json", __DIR__)
  @releases @external_resource |> File.read!() |> Jason.decode!()

  attr :releases, :list, default: @releases

  def feed(assigns) do
    ~H"""
    <details
      id="changelog"
      class="changelog fixed bottom-18 left-4 z-40"
      phx-click-away={JS.remove_attribute("open", to: "#changelog")}
      phx-window-keydown={close()}
      phx-key="Escape"
    >
      <summary
        id="changelog-toggle"
        class="relative z-10 flex w-fit cursor-pointer list-none items-center gap-2 rounded-full border-2 border-border bg-white px-5 py-2 text-sm font-bold select-none hover:bg-pink-50 focus-visible:outline-2 focus-visible:outline-offset-4"
      >
        <.icon name={:sparkles} class="size-4 text-black" /> What's new
      </summary>
      <section
        id="changelog-panel"
        aria-labelledby="changelog-title"
        class="absolute bottom-[calc(100%-2px)] left-0 flex max-h-[min(34rem,calc(100dvh-8rem))] w-[min(25rem,calc(100vw-2rem))] flex-col rounded-2xl rounded-bl-none border-2 border-border bg-white"
      >
        <div class="flex shrink-0 items-center justify-between gap-4 px-5 pt-4 pb-3">
          <h2 id="changelog-title" class="flex items-center gap-2 text-xl font-bold">
            <.icon name={:sparkles} class="size-5 text-black" /> What's new
          </h2>
          <button
            id="changelog-close"
            type="button"
            aria-label="Close changelog"
            phx-click={close()}
            class="flex size-8 cursor-pointer items-center justify-center rounded-full transition-colors hover:bg-pink-100 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            <.icon name={:x} class="size-5" />
          </button>
        </div>
        <div
          id="changelog-releases"
          tabindex="0"
          role="region"
          aria-label="Release history"
          class="min-h-0 space-y-6 overflow-y-auto overscroll-contain px-5 pt-1 pb-6 focus-visible:outline-2 focus-visible:-outline-offset-2"
        >
          <section :for={release <- @releases} aria-label={release["date"]}>
            <h3 class="mb-3 text-sm font-semibold text-pink-400">
              <time datetime={release["date"]}>
                {release["date"] |> Date.from_iso8601!() |> Calendar.strftime("%-d %B %Y")}
              </time>
            </h3>
            <ul class="space-y-3">
              <li :for={entry <- release["entries"]} class="flex items-start gap-3">
                <span class={[
                  "mt-1 inline-flex w-18 shrink-0 justify-center rounded-full px-2 py-0.5 text-[11px] leading-4 font-bold whitespace-nowrap text-white",
                  tag_color(entry["type"])
                ]}>
                  {tag_label(entry["type"])}
                </span>
                <p class="text-sm leading-6 text-slate-900">{entry["text"]}</p>
              </li>
            </ul>
          </section>
        </div>
      </section>
    </details>
    """
  end

  defp close do
    JS.focus(to: "#changelog[open] > summary")
    |> JS.remove_attribute("open", to: "#changelog")
  end

  defp tag_label("feature"), do: "New"
  defp tag_label("fix"), do: "Fix"
  defp tag_label("new_mode"), do: "Game"

  defp tag_color("feature"), do: "bg-blue-400"
  defp tag_color("fix"), do: "bg-green-400"
  defp tag_color("new_mode"), do: "bg-violet-400"
end
