defmodule FlamingoWeb.GameModes.SettingsFields do
  @moduledoc """
  Settings fields shared between game modes, each with the parser for its params.

  A mode's `settings/1` composes the fields it needs, and its `parse_settings/1`
  calls the matching parsers. Parsers fall back to defaults for missing or
  invalid params, because the host's draft may come from another mode's form.
  """
  use FlamingoWeb, :html

  alias Flamingo.{GameSettings, Words}

  @turn_length_range GameSettings.turn_length_range()
  @round_range 1..5
  @default_rounds 3

  attr :form, Phoenix.HTML.Form, required: true

  def rounds(assigns) do
    assigns = assign(assigns, value: parse_rounds(assigns.form.params), range: @round_range)

    ~H"""
    <div class="mb-4 space-y-1">
      <div class="flex w-full justify-between">
        <label for="round-count-slider" class="text-sm">Rounds</label>
        <span class="text-sm">{@value}</span>
      </div>
      <.input
        field={@form[:round_count]}
        type="range"
        min={@range.first}
        max={@range.last}
        value={@value}
        class="w-full"
        id="round-count-slider"
      />
    </div>
    """
  end

  def parse_rounds(params),
    do: params |> integer("round_count", @default_rounds) |> clamp(@round_range)

  attr :form, Phoenix.HTML.Form, required: true
  attr :label, :string, default: "Round length(s)"

  def turn_length(assigns) do
    assigns =
      assign(assigns, value: parse_turn_length(assigns.form.params), range: @turn_length_range)

    ~H"""
    <div class="mb-4">
      <label for="round-length-input" class="block text-sm">{@label}</label>
      <div class="mt-1 flex w-48 items-center">
        <.input
          type="number"
          min={@range.first}
          max={@range.last}
          value={@value}
          name={@form[:turn_length].name}
          class="w-full rounded-base border-2 border-border bg-white px-3 py-2 text-sm focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
          id="round-length-input"
        />
      </div>
    </div>
    """
  end

  def parse_turn_length(params),
    do:
      params
      |> integer("turn_length", GameSettings.defaults().turn_length)
      |> clamp(@turn_length_range)

  attr :form, Phoenix.HTML.Form, required: true

  def spin(assigns) do
    ~H"""
    <div class="mb-4 space-y-1">
      <.input
        field={@form[:spin_enabled]}
        type="checkbox"
        label="Last-place Spin"
        id="spin-enabled-input"
      />
      <p class="text-xs text-gray-600">
        Last place gets one canvas spin for the next round. Requires 3+ players
        and 2+ rounds. Use it before guessing correctly.
      </p>
    </div>
    """
  end

  def parse_spin(params), do: params["spin_enabled"] == "true"

  @doc "The word theme picker, with a custom word list when the theme is Custom."
  attr :form, Phoenix.HTML.Form, required: true

  def words(assigns) do
    custom_words = assigns.form.params["custom_words"] || ""
    {count, live_error} = custom_words_summary(custom_words)

    error =
      case Keyword.get(assigns.form.errors, :custom_words) do
        {message, _opts} -> message
        nil -> live_error
      end

    assigns =
      assign(assigns,
        custom?: parse_word_list(assigns.form.params) == :custom,
        custom_words: custom_words,
        count: count,
        error: error
      )

    ~H"""
    <div class="mb-4 space-y-1">
      <.input
        field={@form[:word_list]}
        type="select"
        label="Word theme"
        options={Words.word_list_options()}
        id="word-list-select"
      />
    </div>
    <div :if={@custom?} id="custom-words-settings" class="mb-4">
      <div class="flex items-end justify-between gap-3">
        <label for="custom-words-input" class="text-sm">Custom words</label>
        <span id="custom-word-count" class="text-xs text-gray-500">
          {@count} / 3000
        </span>
      </div>
      <.input
        name={@form[:custom_words].name}
        value={@custom_words}
        type="textarea"
        rows="4"
        required
        placeholder={"Add your own words, one per line" <> "\nflamingo\nsandcastle"}
        class="mt-1 min-h-24 w-full resize-y rounded-base border-2 border-border bg-white px-3 py-2 text-sm leading-5 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
        phx-hook=".CustomWords"
        id="custom-words-input"
      />
      <p :if={@error} id="custom-words-error" class="mt-1 text-xs text-red-600">
        {@error}
      </p>
      <p :if={!@error} class="mt-1 text-xs text-gray-500">
        Add at least one word or phrase per line. Commas are not supported.
      </p>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CustomWords">
      export default {
        mounted() {
          this.validate = () => {
            const words = this.el.value.split(/\r?\n/).map(word => word.trim()).filter(Boolean)
            const message = this.el.value.includes(",")
              ? "Enter one word per line without commas."
              : words.length > 3000
                ? "Custom word lists can contain at most 3000 words."
                : ""

            this.el.setCustomValidity(message)
          }

          this.validate()
          this.el.addEventListener("input", this.validate)
        },
        updated() {
          this.validate()
        },
        destroyed() {
          this.el.removeEventListener("input", this.validate)
        }
      }
    </script>
    """
  end

  @doc "Parses the word theme and, for Custom, its word list."
  def parse_words(params) do
    word_list = parse_word_list(params)

    with {:ok, words} <- custom_words(word_list, params["custom_words"] || "") do
      {:ok, %{word_list: word_list, custom_words: words, include_default_words: false}}
    end
  end

  defp parse_word_list(params), do: Words.parse_word_list(params["word_list"], :default)

  defp custom_words(:custom, text) do
    case Words.parse_custom_words(text) do
      {:ok, []} -> {:error, custom_words: {"Add at least one custom word.", []}}
      {:ok, words} -> {:ok, words}
      {:error, reason} -> {:error, custom_words: {custom_words_message(reason), []}}
    end
  end

  defp custom_words(_word_list, _text), do: {:ok, []}

  defp custom_words_summary(text) do
    case Words.parse_custom_words(text) do
      {:ok, words} -> {length(words), nil}
      {:error, reason} -> {line_count(text), custom_words_message(reason)}
    end
  end

  defp custom_words_message(:too_many_custom_words), do: "Use at most 3000 custom words."
  defp custom_words_message(:invalid_custom_words), do: "Enter one word per line without commas."

  defp line_count(text), do: text |> String.split(~r/\R/) |> Enum.count(&(String.trim(&1) != ""))

  defp integer(params, key, default) do
    case Integer.parse(to_string(params[key])) do
      {value, _} -> value
      :error -> default
    end
  end

  defp clamp(value, range), do: value |> max(range.first) |> min(range.last)
end
