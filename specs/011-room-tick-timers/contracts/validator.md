# Contract: `AgenticRealms.World.Behaviors.Validator` — additions for `tick`

This feature extends the existing feature-009 validator. The function signature and overall shape are unchanged; only the recognized-trigger set and per-trigger validation logic change.

## Changes

### Updated constants

```elixir
# Before (feature 009):
@valid_triggers ~w(player_entered player_left)

# After (feature 011):
@valid_triggers ~w(player_entered player_left tick)
```

### New per-behavior validation clause

When `Map.get(behavior, "trigger") == "tick"` (or `Map.get(behavior, :trigger) == "tick"` after atom-keyed deserialization), the validator MUST additionally verify `interval_ms`:

```elixir
defp validate_tick_interval(behavior) do
  base_rate = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])
              |> Keyword.get(:base_tick_rate_ms, 1_000)

  case interval_ms_value(behavior) do
    nil ->
      {:error, {:invalid_tick_interval, %{reason: :missing, behavior: behavior, base_rate: base_rate}}}

    value when not is_integer(value) ->
      {:error, {:invalid_tick_interval, %{reason: :non_integer, value: value, behavior: behavior, base_rate: base_rate}}}

    value when value <= 0 ->
      {:error, {:invalid_tick_interval, %{reason: :non_positive, value: value, behavior: behavior, base_rate: base_rate}}}

    value when rem(value, base_rate) != 0 ->
      {:error, {:invalid_tick_interval, %{reason: :non_multiple, value: value, behavior: behavior, base_rate: base_rate}}}

    _ok ->
      :ok
  end
end

defp interval_ms_value(behavior) do
  Map.get(behavior, "interval_ms") || Map.get(behavior, :interval_ms)
end
```

### Integration into existing `validate/1`

The existing per-behavior validation loop:

1. Validates the top-level shape (map with `"trigger"` and `"actions"` keys).
2. Validates that `trigger` is in `@valid_triggers`.
3. Validates the `actions` list shape.
4. **NEW**: If trigger is `"tick"`, additionally validate `interval_ms` via the new clause above.
5. Returns `:ok` if all checks pass; the first failure short-circuits with `{:error, reason}`.

## Behavior contracts

- The validator is pure (reads application config at call time; no DB).
- `validate/1` MUST be re-entrant and idempotent: calling it multiple times on the same input yields the same result.
- The base tick rate is read at each `validate/1` invocation, NOT cached at module load. This lets test configs that override the rate take effect without recompilation.

## Test surface

Extends `test/agenticrealms/world/behaviors/validator_test.exs`:

- A list with `[%{"trigger" => "tick", "interval_ms" => 1000, "actions" => [%{"type" => "say", "text" => "..."}]}]` is valid (base rate 1000).
- A behavior with `"trigger" => "tick"` but no `interval_ms` key → `{:error, {:invalid_tick_interval, %{reason: :missing, ...}}}`.
- A behavior with `"interval_ms" => nil` → `:missing`.
- A behavior with `"interval_ms" => "1000"` (string) → `:non_integer`.
- A behavior with `"interval_ms" => 1500.0` (float) → `:non_integer`.
- A behavior with `"interval_ms" => 0` → `:non_positive`.
- A behavior with `"interval_ms" => -100` → `:non_positive`.
- A behavior with `"interval_ms" => 500` when base is 1000 → `:non_multiple` (value, base_rate carried in the error payload).
- A behavior with `"interval_ms" => 2000` when base is 1000 → valid.
- A behavior with `"interval_ms" => 1000` when base is 100 → valid (1000 is a multiple of 100).
- Atom-keyed input shape (`%{trigger: "tick", interval_ms: 1000, actions: [...]}`) is also accepted (consistent with feature 009's atom-key handling).
- A non-tick behavior (e.g., `"trigger" => "player_entered"`) is NOT subjected to `interval_ms` validation even if the field is present or malformed.
