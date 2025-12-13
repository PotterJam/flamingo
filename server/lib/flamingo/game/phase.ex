defmodule Flamingo.Game.Phase do
  alias Flamingo.Game.Context

  @type phase_state :: term()
  @type action :: term()
  @type effect :: term()
  @type transition :: {:continue, phase_state, Context.t(), list(effect())}
                    | {:transition, module(), phase_state, Context.t(), list(effect())}

  @callback init(Context.t()) :: {phase_state(), Context.t(), list(effect())}

  @callback handle_action(phase_state(), Context.t(), action(), elapsed :: non_neg_integer()) ::
              transition() | {:error, term()}

  @callback handle_timeout(phase_state(), Context.t()) :: transition()

  @optional_callbacks handle_timeout: 2
end
