defmodule FlamingoWeb.Layouts do
  use FlamingoWeb, :html

  embed_templates "layouts/*"

  attr :current_scope, :map, required: true
  attr :avatar, :map, required: true

  def account_menu(assigns) do
    ~H"""
    <details
      :if={@current_scope}
      id="account-menu"
      class="absolute right-4 top-4 z-40 text-sm"
      phx-click-away={JS.remove_attribute("open", to: "#account-menu")}
      phx-window-keydown={JS.remove_attribute("open", to: "#account-menu")}
      phx-key="escape"
    >
      <summary class="flex cursor-pointer list-none items-center gap-2 rounded-xl border-2 border-border bg-white px-3 py-2 font-bold shadow-shadow transition-transform hover:-translate-y-0.5 [&::-webkit-details-marker]:hidden">
        <.flamingo_avatar avatar={@avatar} class="h-8 w-7" /> Account
        <.icon name={:chevron_down} class="size-4" />
      </summary>
      <nav
        aria-label="Account"
        class="absolute right-0 mt-3 w-72 max-w-[calc(100vw-2rem)] space-y-3 rounded-xl border-2 border-border bg-white p-4 shadow-shadow"
      >
        <p class="text-xs text-muted-foreground">Signed in as</p>
        <p class="break-all font-semibold">{@current_scope.user.email}</p>
        <.button
          id="account-settings"
          navigate={~p"/users/settings"}
          variant="neutral"
          class="block text-center"
        >
          Account settings
        </.button>
        <.link
          id="account-log-out"
          href={~p"/users/log-out"}
          method="delete"
          class="block underline underline-offset-4"
        >
          Log out
        </.link>
      </nav>
    </details>
    """
  end

  attr :current_scope, :map, default: nil

  def account_status(assigns) do
    ~H"""
    <%!-- Guest radius: 20px button radius + 8px vertical padding + 2px border. --%>
    <.box
      id="account-status"
      role="region"
      aria-label="Your account"
      radius={if(@current_scope, do: "1rem", else: "30px")}
      class={[
        "mt-2 flex w-full max-w-[41rem] flex-col gap-4 bg-white px-3 sm:flex-row sm:items-center sm:justify-between",
        if(@current_scope, do: "py-5", else: "py-2")
      ]}
    >
      <%= if @current_scope do %>
        <div class="min-w-0">
          <p class="font-bold">Signed in as</p>
          <p class="break-all text-sm">{@current_scope.user.email}</p>
          <p
            id="avatar-save-status"
            role="status"
            phx-update="ignore"
            class="mt-1 text-xs text-muted-foreground"
          >
          </p>
        </div>
        <.button
          id="account-settings-link"
          navigate={~p"/users/settings"}
          variant="neutral"
          class="shrink-0 text-center font-bold"
        >
          Account settings
        </.button>
      <% else %>
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
      <% end %>
    </.box>
    """
  end

  attr :current_scope, :map, default: nil

  def account_nav(assigns) do
    ~H"""
    <nav
      id="account-nav"
      aria-label="Account"
      class="flex flex-wrap items-center justify-center gap-3 text-sm"
    >
      <%= if @current_scope do %>
        <span class="max-w-64 truncate">{@current_scope.user.email}</span>
        <.button id="account-settings" href={~p"/users/settings"} variant="neutral" size="sm">
          Settings
        </.button>
        <.button
          id="account-log-out"
          href={~p"/users/log-out"}
          method="delete"
          variant="neutral"
          size="sm"
        >
          Log out
        </.button>
      <% else %>
        <span class="text-muted-foreground">No account needed to play.</span>
        <.link
          id="account-log-in"
          navigate={~p"/users/log-in"}
          class="font-semibold underline underline-offset-4"
        >
          Log in
        </.link>
        <.link
          id="account-register"
          navigate={~p"/users/register"}
          class="font-semibold underline underline-offset-4"
        >
          Register
        </.link>
      <% end %>
    </nav>
    """
  end

  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def account_panel(assigns) do
    ~H"""
    <div class="mx-auto flex min-h-screen max-w-lg flex-col justify-center gap-6 px-4 pt-28 pb-12">
      <.link navigate={~p"/"} class="self-center font-semibold underline underline-offset-4">
        Back to Flamingo
      </.link>
      <.card class="space-y-6 bg-white p-6 sm:p-8">
        {render_slot(@inner_block)}
      </.card>
      <.account_nav current_scope={@current_scope} />
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
