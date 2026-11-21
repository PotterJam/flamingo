defmodule FlamingoWeb.GameMode do
  @moduledoc """
  A game mode the host can pick in the lobby.

  Each mode owns everything the shared lobby and room routing need to know about
  it: its picker metadata and colours, its settings fields and how to turn them
  into engine settings, the engine module that runs it, and the LiveView that
  shows it. Modes are listed in `FlamingoWeb.GameModes`; nothing else in the
  lobby or room code should branch on a mode.

  Several modes may share an engine and a LiveView, as Classic, Roulette and
  Teams share the Scribble screen. Shared settings fields, such as the drawing
  modes' rounds and word theme, live in `FlamingoWeb.GameModes.SettingsFields`
  for each mode to compose.
  """

  @typedoc """
  Colours for the mode. Each value is a literal Tailwind class so the build sees it.

    * `:selected` and `:hover` - the mode's picker button
    * `:lobby` - the lobby background
    * `:game` and `:game_text` - the in-game flamingo background and its text
    * `:banner` - the word repeated across the in-game background
  """
  @type theme :: %{
          selected: String.t(),
          hover: String.t(),
          lobby: String.t(),
          game: String.t(),
          game_text: String.t(),
          banner: String.t()
        }

  @doc "Unique id, stored by the room and used in DOM ids such as `game-mode-<id>`."
  @callback id() :: atom()
  @callback title() :: String.t()
  @callback description() :: String.t()
  @callback theme() :: theme()

  @doc "The `Flamingo.GameModes.*` engine that runs the game."
  @callback engine() :: module()

  @doc "The LiveView that shows a running or finished game of this mode."
  @callback live_view() :: module()
  @callback path(room_id :: String.t(), resume_token :: String.t()) :: String.t()

  @doc "Connected players needed before the host can start."
  @callback min_players() :: pos_integer()

  @doc """
  Renders the mode's settings fields inside the lobby's settings form.

  Receives `form`, built from the host's draft params, which are shared across
  modes so a value such as the word theme carries over when switching.
  """
  @callback settings(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Turns the host's draft params into settings for `engine().start/3`, or returns
  form errors keyed by field. Params may lack fields this mode never rendered.
  """
  @callback parse_settings(params :: map()) :: {:ok, map()} | {:error, keyword()}

  defmacro __using__(_opts) do
    quote do
      @behaviour FlamingoWeb.GameMode
      use FlamingoWeb, :html

      @impl FlamingoWeb.GameMode
      def min_players, do: 2

      defoverridable min_players: 0
    end
  end
end
