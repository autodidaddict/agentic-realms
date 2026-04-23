defmodule AgenticRealmsWeb.GameLive do
  use AgenticRealmsWeb, :live_view

  import AgenticRealmsWeb.GameComponents

  alias AgenticRealms.GameData

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:mode, :player)
     |> assign(:modal, nil)
     |> assign(:map_open, false)
     |> assign(:log, GameData.starting_log())
     |> assign(:input, "")
     |> assign(:streaming, false)
     |> assign(:stats, GameData.player_stats())
     |> assign(:inventory, GameData.inventory())
     |> assign(:quests, GameData.quests())
     |> assign(:quest_details, GameData.quest_details())
     |> assign(:presence, GameData.presence())
     |> assign(:suggestions, GameData.suggestions())
     |> assign(:selected_quest, 0)
     |> assign(:wizard_kind, :item)
     |> assign(:wizard_text, GameData.starter_prompts()[:item])
     |> assign(:wizard_user_edited, false)
     |> assign(:wizard_examples, GameData.wizard_examples())
     |> assign(:open_trigger, nil)
     |> assign(:tweaks, build_tweaks(socket.assigns.current_player))}
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :mode, String.to_existing_atom(mode))}
  end

  def handle_event("submit_command", %{"text" => text}, socket) do
    t = String.trim(text)

    if t == "" do
      {:noreply, socket}
    else
      socket = update(socket, :log, &(&1 ++ [%{kind: :cmd, text: t}]))
      socket = assign(socket, :input, "")

      socket =
        cond do
          Regex.match?(~r/read|open|letter/i, t) ->
            socket
            |> assign(:streaming, true)
            |> push_event("stream_text", %{text: GameData.streaming_response()})

          Regex.match?(~r/^(n|north|east|e|w|west|s|south|up|down)$/i, t) ->
            update(
              socket,
              :log,
              &(&1 ++
                  [
                    %{
                      kind: :system,
                      text: "You cannot leave — Sable grips your wrist. 'Not yet.'"
                    }
                  ])
            )

          Regex.match?(~r/attack|hit|strike/i, t) ->
            update(
              socket,
              :log,
              &(&1 ++
                  [
                    %{
                      kind: :combat,
                      text: "Thornwick misjudges — a bar-brawl ignites.",
                      dmg: 6,
                      pct: 0.18
                    }
                  ])
            )

          Regex.match?(~r/^inv(entory)?$/i, t) ->
            assign(socket, :modal, :inv)

          Regex.match?(~r/^quest/i, t) ->
            assign(socket, :modal, :quests)

          true ->
            update(
              socket,
              :log,
              &(&1 ++ [%{kind: :system, text: "The world pauses. You consider your next move."}])
            )
        end

      {:noreply, socket}
    end
  end

  def handle_event("click_suggestion", %{"text" => text}, socket) do
    handle_event("submit_command", %{"text" => text}, socket)
  end

  def handle_event("update_input", %{"text" => text}, socket) do
    {:noreply, assign(socket, :input, text)}
  end

  def handle_event("open_modal", %{"modal" => modal}, socket) do
    {:noreply, assign(socket, :modal, String.to_existing_atom(modal))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :modal, nil)}
  end

  def handle_event("toggle_map", _params, socket) do
    {:noreply, update(socket, :map_open, &(!&1))}
  end

  def handle_event("select_quest", %{"index" => index}, socket) do
    {:noreply, assign(socket, :selected_quest, String.to_integer(index))}
  end

  def handle_event("set_wizard_kind", %{"kind" => kind}, socket) do
    kind_atom = String.to_existing_atom(kind)

    socket =
      socket
      |> assign(:wizard_kind, kind_atom)
      |> then(fn s ->
        if not s.assigns.wizard_user_edited do
          assign(s, :wizard_text, GameData.starter_prompts()[kind_atom] || "")
        else
          s
        end
      end)

    {:noreply, socket}
  end

  def handle_event("update_wizard_text", %{"text" => text}, socket) do
    {:noreply,
     socket
     |> assign(:wizard_text, text)
     |> assign(:wizard_user_edited, true)}
  end

  def handle_event("open_trigger", %{"id" => id}, socket) do
    example = socket.assigns.wizard_examples[socket.assigns.wizard_kind]

    trigger =
      if example do
        Enum.find(example[:triggers] || [], fn t -> t.id == id end)
      end

    {:noreply, assign(socket, :open_trigger, trigger)}
  end

  def handle_event("close_trigger", _params, socket) do
    {:noreply, assign(socket, :open_trigger, nil)}
  end

  def handle_event("stream_done", _params, socket) do
    {:noreply,
     socket
     |> assign(:streaming, false)
     |> update(:log, &(&1 ++ [%{kind: :narrate, text: GameData.streaming_response()}]))}
  end

  defp build_tweaks(player) do
    %{
      theme: player.theme,
      density: player.density,
      player_layout: "classic",
      show_hud: true
    }
  end
end
