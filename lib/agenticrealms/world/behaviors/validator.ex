defmodule AgenticRealms.World.Behaviors.Validator do
  @moduledoc """
  Validates the shape of a behavior list at authoring time. Called by the
  seed before dispatching CreateRoom / CreateNPCBlueprint with behaviors,
  and (in a future feature) by the wizard tab before persisting any
  user-authored behaviors.

  """

  @valid_triggers ~w(player_entered player_left tick)
  @max_say_text_length 500
  @max_emote_text_length 500
  @default_base_tick_rate_ms 1_000

  @type error_reason ::
          :not_a_list
          | :invalid_behavior_shape
          | {:unknown_trigger, any()}
          | :actions_not_a_list
          | :empty_actions
          | :invalid_action_shape
          | {:unknown_action_type, any()}
          | :missing_say_text
          | :empty_say_text
          | :text_too_long
          | :missing_emote_text
          | :empty_emote_text
          | :emote_text_too_long
          | {:invalid_tick_interval, map()}

  @spec validate(any()) :: :ok | {:error, error_reason()}
  def validate(behaviors) when is_list(behaviors) do
    Enum.reduce_while(behaviors, :ok, fn behavior, _acc ->
      case validate_behavior(behavior) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  def validate(_), do: {:error, :not_a_list}

  defp validate_behavior(%{"trigger" => trigger, "actions" => actions} = behavior)
       when is_binary(trigger) do
    cond do
      trigger not in @valid_triggers ->
        {:error, {:unknown_trigger, trigger}}

      not is_list(actions) ->
        {:error, :actions_not_a_list}

      actions == [] ->
        {:error, :empty_actions}

      true ->
        with :ok <- validate_trigger_specific(trigger, behavior),
             :ok <- validate_actions(actions) do
          :ok
        end
    end
  end

  defp validate_behavior(_), do: {:error, :invalid_behavior_shape}

  defp validate_trigger_specific("tick", behavior) do
    base_rate = base_tick_rate_ms()

    case interval_ms_value(behavior) do
      nil ->
        {:error,
         {:invalid_tick_interval, %{reason: :missing, behavior: behavior, base_rate: base_rate}}}

      value when not is_integer(value) ->
        {:error,
         {:invalid_tick_interval,
          %{reason: :non_integer, value: value, behavior: behavior, base_rate: base_rate}}}

      value when value <= 0 ->
        {:error,
         {:invalid_tick_interval,
          %{reason: :non_positive, value: value, behavior: behavior, base_rate: base_rate}}}

      value when rem(value, base_rate) != 0 ->
        {:error,
         {:invalid_tick_interval,
          %{reason: :non_multiple, value: value, behavior: behavior, base_rate: base_rate}}}

      _ok ->
        :ok
    end
  end

  defp validate_trigger_specific(_other_trigger, _behavior), do: :ok

  defp interval_ms_value(behavior) do
    Map.get(behavior, "interval_ms") || Map.get(behavior, :interval_ms)
  end

  defp base_tick_rate_ms do
    Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])
    |> Keyword.get(:base_tick_rate_ms, @default_base_tick_rate_ms)
  end

  defp validate_actions(actions) do
    Enum.reduce_while(actions, :ok, fn action, _acc ->
      case validate_action(action) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_action(%{"type" => "say"} = action) do
    case Map.get(action, "text") do
      nil ->
        {:error, :missing_say_text}

      text when not is_binary(text) ->
        {:error, :missing_say_text}

      "" ->
        {:error, :empty_say_text}

      text when byte_size(text) > @max_say_text_length ->
        {:error, :text_too_long}

      _ ->
        :ok
    end
  end

  defp validate_action(%{"type" => "emote"} = action) do
    case Map.get(action, "text") do
      nil -> {:error, :missing_emote_text}
      text when not is_binary(text) -> {:error, :missing_emote_text}
      "" -> {:error, :empty_emote_text}
      text when byte_size(text) > @max_emote_text_length -> {:error, :emote_text_too_long}
      _ -> :ok
    end
  end

  defp validate_action(%{"type" => unknown}),
    do: {:error, {:unknown_action_type, unknown}}

  defp validate_action(_), do: {:error, :invalid_action_shape}
end
