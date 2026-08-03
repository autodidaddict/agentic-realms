defmodule AgenticRealmsWeb.GameLive.Creation do
  @moduledoc """
  Feature 021 — the creation dialog's event handlers.

  Every one of these updates the draft in socket assigns and re-renders. None
  touches world state until `confirm/1`, so abandoning creation leaves nothing
  behind.

  ## Why these are round trips

  Principle III asks for the reason whenever an interaction could plausibly be
  local, and feature 020 deliberately kept the character sheet's tabs off the
  server, so the difference is worth stating.

  A sheet tab shows a panel that is already in the DOM; the server has nothing
  to add, so it must not be asked. A creation selection changes *which questions
  exist* — pick an elf and a lineage question appears, pick a dwarf and it does
  not — and the answer comes from compile-time content that lives on the server.
  Rendering that in the browser would mean shipping the rules library to the
  client. That is the "data the client must not hold" case the principle allows
  for.

  Cost: one round trip per click, each a compile-time content read and a struct
  update, with no database access and no world state touched. The name
  availability check is the one that reaches the database, and it is debounced.
  """

  alias AgenticRealms.World.CharacterDraft, as: Draft
  alias AgenticRealms.World.Commands
  alias AgenticRealms.World.PlayerNames
  alias Srd.Rules.Ability

  import Phoenix.Component, only: [assign: 3]

  @doc """
  The name field changed. Re-checks availability, which is the one handler that
  reaches the database.

  A courtesy, not a reservation: the name is checked again for real when the
  player confirms, and `CharacterName` is what decides.
  """
  def name(socket, name) do
    draft = Draft.put_name(socket.assigns.draft, name)
    assign(socket, :draft, Draft.put_name_status(draft, name_status(name)))
  end

  defp name_status(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> :unchecked
      String.length(trimmed) > 32 -> :invalid
      PlayerNames.taken?(trimmed) -> :taken
      true -> :available
    end
  end

  @doc """
  A species, class, or background was chosen. The draft discards exactly what
  the new selection invalidates.
  """
  def select(socket, field, value) do
    assign(socket, :draft, Draft.put_selection(socket.assigns.draft, field, value))
  end

  @doc """
  A point was spent on an ability, or refunded from it. The draft refuses
  either when the budget or the bounds say so.
  """
  def raise_ability(socket, ability) do
    assign(socket, :draft, Draft.increase(socket.assigns.draft, ability))
  end

  def lower_ability(socket, ability) do
    assign(socket, :draft, Draft.decrease(socket.assigns.draft, ability))
  end

  @doc """
  Throw the current spread away and roll another.
  """
  def reroll(socket) do
    assign(socket, :draft, Draft.roll(socket.assigns.draft))
  end

  @doc """
  The background's increases were spread.
  """
  def spread(socket, spread) do
    assign(socket, :draft, Draft.put_spread(socket.assigns.draft, spread))
  end

  @doc """
  A skill was picked or released.
  """
  def toggle_skill(socket, skill) do
    assign(socket, :draft, Draft.toggle_skill(socket.assigns.draft, skill))
  end

  @doc """
  An option was picked or released within one of the keyed choices.

  Knows nothing about what the choice is. The key came from
  `Srd.Character.choices/1` and goes back to the draft unexamined, which is why
  a new kind of choice needs no clause here.
  """
  def toggle_choice(socket, key, option) do
    assign(socket, :draft, Draft.toggle_choice(socket.assigns.draft, key, option))
  end

  @doc """
  Move to another step. The draft refuses one whose prerequisites are not met.
  """
  def step(socket, step) do
    assign(socket, :draft, Draft.put_step(socket.assigns.draft, step))
  end

  @doc """
  Confirm. On success the player enters the world; on failure the dialog stays
  open with every choice intact so they can fix one thing and retry.
  """
  def confirm(socket, enter_world) do
    player_id = socket.assigns.current_player.id

    case Commands.create_character(player_id, socket.assigns.draft) do
      {:ok, :created} ->
        enter_world.(socket)

      {:error, :name_taken} ->
        fail(socket, [{:name, "That name is taken. Choose another."}], :taken)

      {:error, errors} when is_list(errors) ->
        fail(socket, errors, socket.assigns.draft.name_status)

      {:error, _other} ->
        fail(
          socket,
          [{:base, "Something went wrong creating your character. Try again."}],
          socket.assigns.draft.name_status
        )
    end
  end

  defp fail(socket, errors, name_status) do
    draft =
      socket.assigns.draft
      |> Draft.put_errors(errors)
      |> Draft.put_name_status(name_status)

    assign(socket, :draft, draft)
  end

  # --- parameter decoding ---------------------------------------------------
  #
  # Choice keys and options cross the wire as strings, and they come back from a
  # client that can send anything. Each of these resolves against what the
  # package actually offered rather than converting blindly, so a forged
  # parameter finds no match instead of creating an atom or a bogus pick.

  @doc """
  Resolve a choice key and option from their wire forms, against the choices the
  draft's selections actually offer.

  Returns `:error` when nothing matches, which the caller renders as a no-op.
  """
  @spec decode_pick(Draft.t(), String.t(), String.t()) :: {:ok, term(), term()} | :error
  def decode_pick(%Draft{} = draft, key_param, option_param) do
    with {:ok, open} <- find_open(draft, key_param),
         {:ok, option} <- find_option(open.choice.from, option_param) do
      {:ok, open.key, option}
    end
  end

  defp find_open(draft, key_param) do
    case Enum.find(Draft.open_choices(draft), &(Draft.storage_key(&1.key) == key_param)) do
      nil -> :error
      open -> {:ok, open}
    end
  end

  defp find_option(from, option_param) do
    case Enum.find(from, &(option_label(&1) == option_param)) do
      nil -> :error
      option -> {:ok, option_id(option)}
    end
  end

  defp option_label(%{slug: slug}), do: slug
  defp option_label(option) when is_atom(option), do: Atom.to_string(option)
  defp option_label(option) when is_binary(option), do: option
  defp option_label(option), do: to_string(option)

  defp option_id(%{slug: slug}), do: slug
  defp option_id(option), do: option

  @doc """
  Resolve a skill from its wire form against the class' own list.
  """
  @spec decode_skill(Draft.t(), String.t()) :: {:ok, atom()} | :error
  def decode_skill(%Draft{} = draft, skill_param) do
    case Enum.find(Draft.open_choices(draft), &(&1.key == :class_skills)) do
      nil -> :error
      %{choice: choice} -> find_option(choice.from, skill_param)
    end
  end

  @doc """
  Resolve one of the six abilities from its wire form.
  """
  @spec decode_ability(String.t()) :: {:ok, Ability.t()} | :error
  def decode_ability(param) do
    case Enum.find(Ability.all(), &(Atom.to_string(&1) == param)) do
      nil -> :error
      ability -> {:ok, ability}
    end
  end

  @doc """
  Resolve a spread from its wire form, against the abilities the background
  offers.

  `"split:str:con"` is the +2/+1 form; `"even"` is +1 to all three.
  """
  @spec decode_spread(Draft.t(), String.t()) :: {:ok, Draft.spread()} | :error
  def decode_spread(%Draft{} = draft, param) do
    offered = Draft.raisable_abilities(draft)

    case String.split(param, ":") do
      ["even"] ->
        {:ok, {:even, offered}}

      ["split", larger, smaller] ->
        with {:ok, l} <- decode_ability(larger),
             {:ok, s} <- decode_ability(smaller),
             true <- l in offered and s in offered and l != s do
          {:ok, {:split, l, s}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  @doc """
  Resolve one of the steps from its wire form.
  """
  @spec decode_step(String.t()) :: {:ok, Draft.step()} | :error
  def decode_step(param) do
    case Enum.find(Draft.steps(), &(Atom.to_string(&1) == param)) do
      nil -> :error
      step -> {:ok, step}
    end
  end
end
