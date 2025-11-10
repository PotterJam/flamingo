defmodule FlamingoWeb do
  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
    end
  end

  def html_controller do
    quote do
      use Phoenix.Controller, formats: [:html]
      import Plug.Conn
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
