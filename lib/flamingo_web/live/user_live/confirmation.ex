defmodule FlamingoWeb.UserLive.Confirmation do
  use FlamingoWeb, :live_view

  alias Flamingo.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} show_sound_controls={false}>
      <.form
        for={@form}
        id="magic-link-login"
        action={~p"/users/log-in"}
        phx-trigger-action={@trigger_submit}
        hidden
      >
        <.input type="hidden" field={@form[:token]} />
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      # Only a connected browser submits the token; a plain link preview won't consume it.
      {:ok, assign(socket, form: form, trigger_submit: connected?(socket))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end
end
