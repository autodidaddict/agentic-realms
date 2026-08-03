defmodule AgenticRealmsWeb.GameLive.Helpers do
  @moduledoc """
  Small socket-transforming primitives shared by every GameLive helper
  module. Kept narrow on purpose — anything with meaningful logic
  belongs in `PlayerCommands`, `Communication`, `Wizard`, or
  `UIEvents`.
  """

  import Phoenix.Component, only: [assign: 3, update: 3]

  alias AgenticRealms.World.{MapView, Queries}

  @doc """
  Append a log entry to the rolling `:log` assign. The log is rendered
  newest-at-bottom via CSS `flex-direction: column-reverse`, so the
  in-memory ordering is plain chronological (oldest first).
  """
  def append_log(socket, entry), do: update(socket, :log, &(&1 ++ [entry]))

  @doc """
  Append the `:cmd` echo of the player's literal input and clear the
  input box. Returns the socket — caller wraps in `{:noreply, ...}`.
  """
  def echo(socket, raw) do
    socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
  end

  @doc """
  Echo the raw input and append a system reply. Returns a
  `{:noreply, socket}` tuple ready for return from a handler.
  """
  def echo_then_system(socket, raw, text) do
    {:noreply,
     socket
     |> append_log(%{kind: :cmd, text: String.trim(raw)})
     |> append_log(%{kind: :system, text: text})
     |> assign(:input, "")}
  end

  @doc """
  Recompute the per-player MapView struct. Called every
  time the player's current room changes (own move, other-tab swap, or
  any future region/elevation transition). The MapView query is
  bounded by the configured viewport (default 11×11 cells) so this
  stays cheap.

  FR-015 / SC-005: a region transition is just a current-room change
  whose destination has a different `region_id`. `MapView.for_player/1`
  reads the region from the destination room — no special-casing here.
  """
  def refresh_map_view(socket) do
    assign(socket, :map_view, MapView.for_player(socket.assigns.current_player.id))
  end

  @doc """
  Feature 014 US4 / feature 015 US6 — wizards see Things-in-this-room and
  NPCs-in-this-room panels, each with an Extract essence button. Re-query the
  read model on any event that mutates the current room's object / NPC set.
  """
  def refresh_room_objects(%{assigns: %{is_wizard: true, current_room_id: rid}} = socket)
      when is_binary(rid) do
    socket
    |> assign(:room_objects, Queries.list_objects_in_room_for_wizard(rid))
    |> assign(:room_npcs, Queries.list_npcs_in_room(rid))
  end

  def refresh_room_objects(socket), do: socket

  @doc """
  Re-query the `:presence` assign — other players currently in this
  player's room.
  """
  def refresh_presence(socket) do
    presence =
      Queries.other_occupants_of(
        socket.assigns.current_room_id,
        socket.assigns.current_player.id
      )

    assign(socket, :presence, presence)
  end

  @doc """
  Feature 014 US4/US5 — wizard authoring assigns that refer to a
  specific world Object (Extract source / Edit target) are scoped to
  the room the wizard was in when they focused. Walking into a new
  room invalidates them — the security boundary in
  `Commands.edit_object/3` will refuse a stale commit anyway, but
  carrying the form into the new room is confusing UX. Clear them on
  any move.
  """
  def clear_room_scoped_wizard_state(socket) do
    socket
    |> assign(:focused_object_id, nil)
    |> assign(:focused_object_draft, nil)
    |> assign(:focused_object_edit, nil)
  end
end
