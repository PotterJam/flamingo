defmodule FlamingoWeb.UserLive.Settings do
  use FlamingoWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} show_sound_controls={false}>
      <Layouts.account_panel current_scope={@current_scope} settings>
        <h1 class="text-2xl font-bold">Account settings</h1>

        <p id="signed-in-as" class="text-sm">
          Signed in with Google as <strong class="break-all">{@current_scope.user.email}</strong>
        </p>

        <section class="space-y-5 pt-2" aria-label="Account actions">
          <%= if @confirm_delete do %>
            <div id="delete-account-confirmation" class="space-y-4">
              <h2 class="font-bold">Delete your account?</h2>
              <p class="text-sm">
                This permanently deletes your account, saved avatar, and sign-ins.
                You can still play as a guest. This cannot be undone.
              </p>
              <.form
                for={@delete_form}
                id="delete-account-form"
                action={~p"/users/account"}
                method="delete"
                class="space-y-4"
              >
                <.input
                  field={@delete_form[:confirm]}
                  type="checkbox"
                  label="I understand this permanently deletes my account."
                  required
                />
                <div class="flex flex-wrap gap-3">
                  <.button
                    id="confirm-delete-account"
                    variant="neutral"
                    class="font-bold text-red-700"
                  >
                    Delete my account
                  </.button>
                  <.button
                    id="cancel-delete-account"
                    type="button"
                    phx-click="cancel_delete"
                    variant="neutral"
                  >
                    Keep my account
                  </.button>
                </div>
              </.form>
            </div>
          <% end %>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.button
              :if={!@confirm_delete}
              id="delete-account"
              type="button"
              phx-click="confirm_delete"
              variant="danger-ghost"
            >
              Delete account
            </.button>
            <.button
              id="account-log-out"
              href={~p"/users/log-out"}
              method="delete"
              variant="outline"
              class="ml-auto font-bold"
            >
              Log out
            </.button>
          </div>
        </section>
      </Layouts.account_panel>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, confirm_delete: false, delete_form: to_form(%{"confirm" => false}))}
  end

  @impl true
  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete: true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete: false)}
  end
end
