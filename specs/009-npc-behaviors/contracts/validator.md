# Contract: `World.Behaviors.Validator`

Pure module. Validates a behavior-list value (as produced by JSONB decoding — string-keyed maps in a list) against the closed vocabulary of triggers and actions defined for this feature.

## Module shape

```elixir
defmodule AgenticRealms.World.Behaviors.Validator do
  @moduledoc """
  Validates the shape of a behavior list at authoring time. Called by the
  seed before dispatching CreateRoom / CreateNPCBlueprint with behaviors,
  and (in a future feature) by the wizard tab before persisting any
  user-authored behaviors.

  See `specs/009-npc-behaviors/research.md` R3 and `data-model.md` §1.
  """

  @valid_triggers ~w(player_entered player_left)
  @max_say_text_length 500

  @spec validate(any()) :: :ok | {:error, atom() | {atom(), any()}}
  def validate(behaviors)
end
```

## Validation rules

1. **Top level**: input MUST be a list. Otherwise `{:error, :not_a_list}`.
2. **Each entry**: MUST be a map with exactly `"trigger"` and `"actions"` keys. Otherwise `{:error, :invalid_behavior_shape}`.
3. **`"trigger"`**: MUST be a string member of `@valid_triggers`. Otherwise `{:error, {:unknown_trigger, value}}`.
4. **`"actions"`**: MUST be a non-empty list. Otherwise `{:error, :empty_actions}` (or `{:error, :actions_not_a_list}` for non-list).
5. **Each action**: MUST be a map with at minimum a `"type"` key (string). Otherwise `{:error, :invalid_action_shape}`.
6. **For `"type" == "say"`**: action MUST have a `"text"` key (string), non-empty, length ≤ 500. Otherwise:
   - Missing/non-string text: `{:error, :missing_say_text}`
   - Empty string: `{:error, :empty_say_text}`
   - Over cap: `{:error, :text_too_long}`
7. **Other `"type"` values**: REJECTED. `{:error, {:unknown_action_type, value}}`.

## Behavior

- The validator is fail-fast on the first invalid entry it finds. It does NOT return a list of all errors.
- Returns `:ok` on full success.
- Pure function — no Repo, no side effects.

## Callers

- **`Seed`** — calls `Validator.validate/1` for every behavior list it intends to dispatch. A `{:error, _}` result raises (`raise "Seed authoring error: #{inspect(reason)}"`), failing the seed immediately. This makes authoring bugs surface at `mix ecto.reset` time, not at runtime.
- **Future wizard tab** — will call the same validator before persisting user-authored behaviors.

## NOT a caller

- **`World.Behaviors.Interpreter`** — at firing time, the interpreter trusts the stored data shape (it was validated at write time) and pattern-matches on action shape. Malformed actions encountered at runtime are logged and skipped per `contracts/interpreter.md`.

## Example calls

```elixir
iex> Validator.validate([])
:ok

iex> Validator.validate([%{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => "Hi!"}]}])
:ok

iex> Validator.validate([%{"trigger" => "on_attack", "actions" => [%{"type" => "say", "text" => "x"}]}])
{:error, {:unknown_trigger, "on_attack"}}

iex> Validator.validate([%{"trigger" => "player_entered", "actions" => []}])
{:error, :empty_actions}

iex> Validator.validate([%{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => String.duplicate("x", 501)}]}])
{:error, :text_too_long}
```

## Test surface

`test/agenticrealms/world/behaviors/validator_test.exs` — covers each of the rules above (happy paths + each error atom).
