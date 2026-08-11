defmodule FlamingoWeb.Layouts do
  use FlamingoWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :background, :string, default: "grid-background"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main class={[@background, "min-h-screen"]}>
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    <div id="sound-manager" phx-hook="SoundManager" phx-update="ignore"></div>
    <div
      id="sound-volume-control"
      phx-hook=".SoundVolume"
      phx-update="ignore"
      class="fixed bottom-4 left-4 z-50 rounded-base border-2 border-border bg-white px-3 py-2 shadow-shadow"
    >
      <div class="flex items-center gap-2">
        <button
          type="button"
          id="sound-volume-button"
          aria-label="Toggle sound mute"
          class="flex size-5 shrink-0 cursor-pointer items-center justify-center text-foreground"
        >
          <span class="sr-only">Toggle sound mute</span>
          <span
            id="sound-volume-icon"
            class="flex size-5 shrink-0 items-center justify-center text-foreground"
            aria-hidden="true"
          >
            <span data-sound-volume-icon="muted" class="hidden">
              <.icon name={:volume_x} class="size-5" />
            </span>
            <span data-sound-volume-icon="low" class="hidden">
              <.icon name={:volume} class="size-5" />
            </span>
            <span data-sound-volume-icon="medium" class="hidden">
              <.icon name={:volume_1} class="size-5" />
            </span>
            <span data-sound-volume-icon="high"><.icon name={:volume_2} class="size-5" /></span>
          </span>
        </button>
        <label for="sound-volume-slider" class="sr-only">Sound volume</label>
        <.input
          type="range"
          id="sound-volume-slider"
          name="sound-volume"
          min="0"
          max="100"
          step="1"
          value="100"
          aria-label="Sound volume"
          class="w-28"
        />
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SoundVolume">
      export default {
        mounted() {
          const slider = this.el.querySelector("#sound-volume-slider");
          const muteButton = this.el.querySelector("#sound-volume-button");
          const icons = Array.from(this.el.querySelectorAll("[data-sound-volume-icon]"));

          const clampVolume = (value) => {
            const volume = Number.parseInt(value, 10);
            if (!Number.isFinite(volume)) return 100;
            return Math.min(100, Math.max(0, volume));
          };

          const storedPreviousVolume = () => {
            const previous = clampVolume(localStorage.getItem("flamingo_sound_previous_volume"));
            return previous === 0 ? 100 : previous;
          };

          const storedVolume = () => {
            const stored = localStorage.getItem("flamingo_sound_volume");
            if (stored !== null) return clampVolume(stored);
            return localStorage.getItem("flamingo_sound_muted") === "true" ? 0 : 100;
          };

          const iconForVolume = (volume) => {
            if (volume === 0) return "muted";
            if (volume <= 33) return "low";
            if (volume <= 66) return "medium";
            return "high";
          };

          const applyVolume = (volume) => {
            const clampedVolume = clampVolume(volume);
            const visibleIcon = iconForVolume(clampedVolume);

            slider.value = clampedVolume;
            slider.style.setProperty("--slider-progress", `${clampedVolume}%`);
            window.__soundVolume = clampedVolume;
            window.__soundMuted = clampedVolume === 0;
            localStorage.setItem("flamingo_sound_volume", clampedVolume);
            localStorage.setItem("flamingo_sound_muted", window.__soundMuted);
            muteButton.setAttribute("aria-pressed", window.__soundMuted);

            if (clampedVolume > 0) {
              localStorage.setItem("flamingo_sound_previous_volume", clampedVolume);
            }

            for (const icon of icons) {
              icon.classList.toggle("hidden", icon.dataset.soundVolumeIcon !== visibleIcon);
            }

            window.dispatchEvent(new CustomEvent("flamingo:volumechange", {
              detail: { volume: clampedVolume }
            }));
          };

          applyVolume(storedVolume());
          slider.addEventListener("input", () => applyVolume(slider.value));
          muteButton.addEventListener("click", () => {
            applyVolume(window.__soundVolume === 0 ? storedPreviousVolume() : 0);
          });
        }
      }
    </script>
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name={:refresh_cw} class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name={:refresh_cw} class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
