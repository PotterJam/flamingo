defmodule FlamingoWeb.UserLive.Settings do
  use FlamingoWeb, :live_view

  on_mount {FlamingoWeb.UserAuth, :require_sudo_mode}

  alias Flamingo.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} show_sound_controls={false}>
      <Layouts.account_panel current_scope={@current_scope} settings>
        <h1 class="border-b border-border/30 pb-4 text-2xl font-bold">Account settings</h1>

        <.form
          for={@email_form}
          id="email_form"
          class="grid gap-4 sm:grid-cols-[1fr_auto] sm:items-end"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <.input
            field={@email_form[:email]}
            type="email"
            label="Email address"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button phx-disable-with="Sending..." variant="neutral" class="mb-2 font-bold">
            Change email
          </.button>
          <p class="text-sm text-muted-foreground sm:col-span-2">
            We'll send a confirmation link to your new address.
          </p>
        </.form>

        <section class="border-t border-border/30 pt-5" aria-label="Delete account">
          <%= if @confirm_delete do %>
            <div id="delete-account-confirmation" class="space-y-4">
              <h2 class="font-bold">Delete your account?</h2>
              <p class="text-sm">
                This permanently deletes your account, saved avatar, and sign-in links.
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
          <% else %>
            <button
              id="delete-account"
              type="button"
              phx-click="confirm_delete"
              class="cursor-pointer text-sm text-red-700 underline underline-offset-4 hover:text-red-900"
            >
              Delete account…
            </button>
          <% end %>
        </section>
      </Layouts.account_panel>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :success, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)

    {:ok,
     assign(socket,
       email_form: to_form(email_changeset),
       confirm_delete: false,
       delete_form: to_form(%{"confirm" => false})
     )}
  end

  @impl true
  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete: true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, confirm_delete: false)}
  end

  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end
end
