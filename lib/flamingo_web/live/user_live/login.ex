defmodule FlamingoWeb.UserLive.Login do
  use FlamingoWeb, :live_view

  alias Flamingo.Accounts
  alias Flamingo.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} show_sound_controls={false}>
      <Layouts.account_panel current_scope={@current_scope}>
        <div
          :if={@sent_email}
          id="login-email-sent"
          role="status"
          tabindex="-1"
          phx-mounted={JS.focus()}
          class="space-y-3 focus:outline-none"
        >
          <h1 class="text-3xl font-bold text-foreground">Check your email</h1>
          <p class="text-sm text-neutral-600">
            We've sent a login link to <strong class="break-all text-foreground">{@sent_email}</strong>.
          </p>
          <p class="text-sm text-neutral-600">If you don't see it, check your spam folder.</p>
        </div>

        <header :if={!@sent_email} class="space-y-2">
          <h1 id="login-heading" class="text-3xl font-bold text-foreground">Log in</h1>
          <p class="text-sm text-neutral-600">
            <%= if @current_scope do %>
              Log in again to make changes to your account.
            <% else %>
              If you don't already have an email registered this will create your account.
            <% end %>
          </p>
        </header>

        <div
          :if={local_mail_adapter?()}
          class="flex gap-3 rounded-base border-2 border-border bg-secondary p-3 text-sm"
        >
          <.icon name={:info} class="size-5 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <.form
          :if={!@sent_email}
          for={@form}
          id="login_form_magic"
          class="space-y-4"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button id="magic-login-submit" phx-disable-with="Sending link..." class="w-full">
            Log in
          </.button>
        </.form>
      </Layouts.account_panel>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: :register}} = socket) do
    destination = if socket.assigns.current_scope, do: ~p"/", else: ~p"/users/log-in"
    {:ok, redirect(socket, to: destination)}
  end

  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form =
      %User{}
      |> Accounts.change_user_email(%{email: email}, validate_unique: false)
      |> to_form(as: "user")

    {:ok, assign(socket, form: form, sent_email: nil)}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    with {:ok, user} <- Accounts.get_or_register_user(email),
         {:ok, _email} <-
           Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}")) do
      {:noreply,
       socket
       |> clear_flash()
       |> assign(sent_email: user.email)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "We couldn't send your login link. Please try again.")}
    end
  end

  defp local_mail_adapter? do
    Application.get_env(:flamingo, Flamingo.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
