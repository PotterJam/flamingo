defmodule FlamingoWeb.DrawingLive do
  use FlamingoWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} background="">
      <.flamingo_background />
      <div
        id="shared-drawing"
        phx-hook="SharedDrawing"
        phx-update="ignore"
        class="flex min-h-screen w-full items-center justify-center p-6"
      >
        <div
          id="shared-drawing-content"
          class="hidden w-full max-w-3xl flex-col gap-4"
          data-shared-drawing-content
        >
          <div class="flex items-center justify-between gap-4">
            <div class="min-w-0">
              <h1
                id="shared-drawing-drawer"
                class="font-hero truncate text-5xl leading-none font-black"
              >
              </h1>
              <p class="text-lg font-semibold">
                was trying to draw
                <span id="shared-drawing-word" class="font-black text-pink-700"></span>
              </p>
            </div>
            <.link
              navigate={~p"/"}
              class="shrink-0"
              aria-label="Play Flamingo"
            >
              <.logo />
            </.link>
          </div>

          <div class="border-2 border-border bg-white p-3 shadow-shadow">
            <div id="shared-drawing-canvas">
              <canvas width="700" height="500" class="aspect-[7/5] w-full bg-white"></canvas>
            </div>
          </div>

          <div class="flex items-center justify-between">
            <.button
              type="button"
              variant="outline"
              size="icon"
              class="bg-white text-pink-700 hover:bg-pink-50"
              data-replay-shared-drawing
              aria-label="Replay drawing"
              id="replay-shared-drawing-button"
            >
              <.icon name={:refresh_cw} class="size-6" />
            </.button>

            <.button
              type="button"
              variant="neutral"
              class="px-6 py-3 text-base"
              id="copy-drawing-link-button"
              on_confirm_click={JS.dispatch("phx:copy-current-url")}
            >
              <span class="flex items-center gap-2">
                <.icon name={:copy} class="h-5 w-5" /> Share
              </span>
            </.button>
          </div>
        </div>
      </div>

      <div
        id="shared-drawing-clipboard-handler"
        phx-hook=".SharedDrawingClipboard"
        phx-update="ignore"
      >
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".SharedDrawingClipboard">
        export default {
          mounted() {
            window.addEventListener("phx:copy-current-url", () => {
              navigator.clipboard.writeText(window.location.href)
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end
end
