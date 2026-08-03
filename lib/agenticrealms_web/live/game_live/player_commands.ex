defmodule AgenticRealmsWeb.GameLive.PlayerCommands do
  @moduledoc """
  Player command verb handlers — `inventory`, `look`, `look_target`,
  `move`, `take`, `drop` — and the natural-language fallback path
  (`unknown` → LLM intent resolver, `dispatch_resolved_action` to
  re-enter a handler with the resolved action).

  Every public function takes the LiveView socket plus the player's
  raw input and returns a `{:noreply, socket}` tuple, ready for the
  matching `handle_event` clause in `GameLive` to return as-is.

  The `allow_fallback?` parameter on `look_target`, `take`, and `drop`
  is `true` on a fast-path entry — when the noun phrase doesn't
  resolve, the raw input is handed off to the LLM resolver (feature
  005a). It's `false` on an LLM-dispatched retry so a still-failing
  resolution simply refuses instead of looping back into the resolver.
  """

  import Phoenix.Component, only: [assign: 3]

  import AgenticRealmsWeb.GameLive.Helpers,
    only: [
      append_log: 2,
      echo: 2,
      echo_then_system: 3,
      refresh_map_view: 1,
      refresh_room_objects: 1,
      refresh_presence: 1,
      clear_room_scoped_wizard_state: 1
    ]

  alias AgenticRealms.World.{Commands, Examine, IntentResolver, Queries}
  alias AgenticRealms.World.Examine.Match, as: ExamineMatch
  alias AgenticRealmsWeb.GameLive.Communication
  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  @doc """
  Input the fast parser couldn't resolve. Spawn a supervised async
  task to resolve it via the LLM; lock the input and stash the task
  ref + raw text so `handle_info/2` can finish the job when the task
  replies.
  """
  def unknown(socket, raw) do
    player_id = socket.assigns.current_player.id

    task =
      Task.Supervisor.async_nolink(
        AgenticRealms.IntentResolverTaskSupervisor,
        IntentResolver,
        :resolve,
        [player_id, raw]
      )

    {:noreply,
     socket
     |> assign(:resolver_task, %{ref: task.ref, raw_input: raw})
     |> assign(:input_locked, true)
     |> assign(:input, "")}
  end

  @doc """
  Dispatch a resolver-produced action tuple through the same handlers
  the fast-path parser sentinels use. `raw` is the player's literal
  input, so the handlers echo the correct `:cmd` entry.

  `allow_fallback?` is false for every action here — this IS the LLM
  retry; a still-failing take/drop refuses rather than looping.
  """
  def dispatch_resolved_action(socket, raw, action) do
    case action do
      {:look} -> look(socket, raw)
      {:look, target} -> look_target(socket, raw, target, false)
      {:inventory} -> inventory(socket, raw)
      {:move, dir} -> move(socket, raw, dir)
      {:take, name} -> take(socket, raw, name, false)
      {:drop, name} -> drop(socket, raw, name, false)
      {:say, said} -> Communication.say(socket, raw, said)
      {:emote, said} -> Communication.emote(socket, raw, said)
      {:tell, recipient, message} -> Communication.tell(socket, raw, recipient, message)
      {:whisper, recipient, message} -> Communication.whisper(socket, raw, recipient, message)
      {:chat, npc_token, message} -> Communication.chat(socket, raw, npc_token, message)
    end
  end

  def inventory(socket, raw) do
    player_id = socket.assigns.current_player.id
    inventory = Queries.list_inventory(player_id)

    text =
      case inventory do
        [] ->
          "You aren't carrying anything."

        items ->
          "You are carrying:\n" <>
            Enum.map_join(items, "\n", fn item ->
              "  · #{item.name} — #{item.short_description}"
            end)
      end

    {:noreply,
     socket
     |> append_log(%{kind: :cmd, text: String.trim(raw)})
     |> append_log(%{kind: :system, text: text})
     |> assign(:inventory, inventory)
     |> assign(:input, "")}
  end

  def look(socket, raw) do
    player_id = socket.assigns.current_player.id

    case Queries.look_room(player_id) do
      {:ok, room_view} ->
        {:noreply,
         socket
         |> append_log(%{kind: :cmd, text: String.trim(raw)})
         |> append_log(%{kind: :room, room: room_view})
         |> assign(:input, "")}

      {:error, _} ->
        echo_then_system(socket, raw, "You are nowhere.")
    end
  end

  def look_target(socket, raw, target, allow_fallback?) do
    player_id = socket.assigns.current_player.id

    case Examine.examine(player_id, target) do
      {:ok, %ExamineMatch{target_kind: :object, name: name, long_description: ld}} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{
           kind: :detail,
           target_kind: :object,
           name: name,
           long_description: ld
         })}

      {:ok, %ExamineMatch{target_kind: :player, name: name} = m} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{
           kind: :detail,
           target_kind: :player,
           name: name,
           health_tier: m.health_tier,
           power_phrase: m.power_phrase
         })}

      {:ok, %ExamineMatch{target_kind: :npc, name: name, long_description: ld} = m} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{
           kind: :detail,
           target_kind: :npc,
           name: name,
           long_description: ld,
           health_tier: m.health_tier,
           power_phrase: m.power_phrase
         })}

      {:error, :no_such_target} when allow_fallback? ->
        unknown(socket, raw)

      {:error, :no_such_target} ->
        echo_then_system(socket, raw, "You don't see that here.")

      {:error, reason}
      when reason in [
             :ambiguous_in_room,
             :ambiguous_in_inventory,
             :ambiguous_mixed_kind,
             :ambiguous_player,
             :ambiguous_npc,
             :ambiguous_partial
           ] ->
        echo_then_system(socket, raw, "Which one do you mean?")

      {:error, :no_current_room} ->
        echo_then_system(socket, raw, "You are nowhere.")
    end
  end

  def move(socket, raw, dir) do
    player_id = socket.assigns.current_player.id
    from_room_id = socket.assigns.current_room_id
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")

    case Commands.move(player_id, dir) do
      {:ok, to_room_id} ->
        departure_entries =
          AgenticRealms.World.Behaviors.Interpreter.fire_departure_inline(
            player_id,
            from_room_id
          )

        socket = Enum.reduce(departure_entries, socket, &append_log(&2, &1))

        if Phoenix.LiveView.connected?(socket) do
          Phoenix.PubSub.unsubscribe(@pubsub, Topics.room_topic(from_room_id))
          Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(to_room_id))
        end

        case Queries.look_room(player_id) do
          {:ok, room_view} ->
            {:noreply,
             socket
             |> assign(:current_room_id, to_room_id)
             |> assign(:current_room_name, Map.get(room_view, :name))
             |> clear_room_scoped_wizard_state()
             |> refresh_map_view()
             |> refresh_room_objects()
             |> append_log(%{kind: :room, room: room_view})
             |> refresh_presence()}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:current_room_id, to_room_id)
             |> clear_room_scoped_wizard_state()
             |> refresh_map_view()
             |> refresh_room_objects()
             |> append_log(%{kind: :system, text: "You arrive somewhere."})
             |> refresh_presence()}
        end

      {:error, :no_exit_in_direction} ->
        {:noreply, append_log(socket, %{kind: :system, text: "You can't go that way."})}

      {:error, reason} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "You can't move right now (#{inspect(reason)})."
         })}
    end
  end

  def take(socket, raw, name, allow_fallback?) do
    player_id = socket.assigns.current_player.id

    case Commands.take(player_id, name) do
      {:error, :no_such_object} when allow_fallback? ->
        unknown(socket, raw)

      {:ok, %{object_name: object_name}} ->
        inventory = Queries.list_inventory(player_id)

        {:noreply,
         socket
         |> echo(raw)
         |> assign(:inventory, inventory)
         |> append_log(%{kind: :system, text: "You take the #{object_name}."})}

      {:error, err} when err in [:no_such_object, :object_not_in_room] ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "You don't see that here."})}

      {:error, :object_is_fixed} ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "You can't take that."})}

      {:error, :ambiguous} ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "Which one do you mean?"})}

      {:error, :no_current_room} ->
        {:noreply, socket |> echo(raw) |> append_log(%{kind: :system, text: "You are nowhere."})}

      {:error, reason} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{kind: :system, text: "You can't take that (#{inspect(reason)})."})}
    end
  end

  def drop(socket, raw, name, allow_fallback?) do
    player_id = socket.assigns.current_player.id

    case Commands.drop(player_id, name) do
      {:error, :not_in_inventory} when allow_fallback? ->
        unknown(socket, raw)

      {:ok, %{object_name: object_name}} ->
        inventory = Queries.list_inventory(player_id)

        {:noreply,
         socket
         |> echo(raw)
         |> assign(:inventory, inventory)
         |> append_log(%{kind: :system, text: "You drop the #{object_name}."})}

      {:error, :not_in_inventory} ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "You aren't carrying that."})}

      {:error, :ambiguous} ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "Which one do you mean?"})}

      {:error, :no_current_room} ->
        {:noreply, socket |> echo(raw) |> append_log(%{kind: :system, text: "You are nowhere."})}

      {:error, reason} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{kind: :system, text: "You can't drop that (#{inspect(reason)})."})}
    end
  end
end
