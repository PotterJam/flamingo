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
    <div
      id="sound-toggle"
      phx-hook=".SoundToggle"
      phx-update="ignore"
      class="fixed bottom-4 left-4 z-50"
    >
      <.switch id="sound-toggle-switch" label="Play sounds" />
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SoundToggle">
      export default {
        mounted() {
          this.track = this.el.querySelector(".switch-track");
          this.thumb = this.el.querySelector(".switch-thumb");
          const muted = localStorage.getItem("flamingo_sound_muted") === "true";
          window.__soundMuted = muted;
          this.updateToggle(!muted);

          this.track.addEventListener("click", () => {
            window.__soundMuted = !window.__soundMuted;
            localStorage.setItem("flamingo_sound_muted", window.__soundMuted);
            this.updateToggle(!window.__soundMuted);
            if (window.__soundMuted) {
              window.dispatchEvent(new Event("flamingo:mute"));
            }
          });
        },
        updateToggle(on) {
          this.track.setAttribute("aria-checked", on);
          if (on) {
            this.track.classList.remove("bg-secondary-background");
            this.track.classList.add("bg-primary");
            this.thumb.classList.remove("translate-x-1");
            this.thumb.classList.add("translate-x-6");
          } else {
            this.track.classList.remove("bg-primary");
            this.track.classList.add("bg-secondary-background");
            this.thumb.classList.remove("translate-x-6");
            this.thumb.classList.add("translate-x-1");
          }
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
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
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
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
