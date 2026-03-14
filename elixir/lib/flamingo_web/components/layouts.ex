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
          const checkbox = this.el.querySelector("#sound-toggle-switch");
          const muted = localStorage.getItem("flamingo_sound_muted") === "true";
          window.__soundMuted = muted;
          checkbox.checked = !muted;

          checkbox.addEventListener("change", () => {
            window.__soundMuted = !checkbox.checked;
            localStorage.setItem("flamingo_sound_muted", window.__soundMuted);
            if (window.__soundMuted) {
              window.dispatchEvent(new Event("flamingo:mute"));
            }
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
