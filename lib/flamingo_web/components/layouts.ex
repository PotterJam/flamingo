defmodule FlamingoWeb.Layouts do
  use FlamingoWeb, :html

  embed_templates "layouts/*"

  attr :current_scope, :map, required: true

  def account_menu(assigns) do
    ~H"""
    <.box
      :if={@current_scope}
      id="account-menu"
      role="navigation"
      aria-label="Account"
      class="absolute right-4 top-4 z-40 flex max-w-[calc(100%-2rem)] items-center gap-1 bg-white p-1 pl-2 text-sm"
    >
      <span class="min-w-0 truncate font-semibold" title={@current_scope.user.email}>
        {@current_scope.user.email}
      </span>
      <.button
        id="account-settings"
        navigate={~p"/users/settings"}
        variant="ghost"
        size="sm"
        class="inline-flex shrink-0 items-center justify-center"
        aria-label="Account settings"
        title="Account settings"
      >
        <.icon name={:settings} class="size-5" />
      </.button>
    </.box>
    """
  end

  attr :current_scope, :map, default: nil

  def account_status(assigns) do
    ~H"""
    <%!-- Guest radius: 20px button radius + 8px vertical padding + 2px border. --%>
    <.box
      :if={!@current_scope}
      id="account-status"
      role="region"
      aria-label="Your account"
      radius="30px"
      class="mt-2 flex w-full max-w-[41rem] flex-col gap-4 bg-white px-3 py-2 sm:flex-row sm:items-center sm:justify-between"
    >
      <p class="text-sm font-bold">
        You are currently playing as a guest. Sign in to save your history
      </p>
      <.button
        id="account-log-in"
        navigate={~p"/users/log-in"}
        variant="default"
        rounded
        class="shrink-0 text-center font-bold"
      >
        Sign in
      </.button>
    </.box>
    """
  end

  attr :current_scope, :map, default: nil
  attr :settings, :boolean, default: false
  slot :inner_block, required: true

  def account_panel(assigns) do
    ~H"""
    <div class={[
      "mx-auto flex min-h-screen flex-col justify-center gap-5 px-4 pt-28 pb-12",
      if(@settings, do: "max-w-3xl", else: "max-w-lg")
    ]}>
      <.button
        id="account-back"
        navigate={~p"/"}
        variant="neutral"
        class="inline-flex items-center gap-2 self-start font-bold"
      >
        <.icon name={:arrow_left} class="size-4" /> Home
      </.button>
      <.card class={[
        "space-y-6 bg-white",
        if(@settings, do: "p-4 sm:p-5", else: "p-6 sm:p-8")
      ]}>
        {render_slot(@inner_block)}
      </.card>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :background, :string, default: "grid-background"
  attr :show_sound_controls, :boolean, default: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main class={[@background, "min-h-screen"]}>
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    <div id="sound-manager" phx-hook="SoundManager" phx-update="ignore"></div>
    <div
      :if={@show_sound_controls}
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
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed left-1/2 top-4 z-50 flex w-[calc(100%-2rem)] max-w-sm -translate-x-1/2 flex-col gap-3"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:success} flash={@flash} />
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
